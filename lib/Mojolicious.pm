package Mojolicious;
use Mojo::Base -base;

# "Fry: Shut up and take my money!"
use Carp ();
use Mojo::DynamicMethods -dispatch;
use Mojo::Exception;
use Mojo::Home;
use Mojo::Log;
use Mojo::Util;
use Mojo::UserAgent;
use Mojolicious::Commands;
use Mojolicious::Controller;
use Mojolicious::Plugins;
use Mojolicious::Renderer;
use Mojolicious::Routes;
use Mojolicious::Sessions;
use Mojolicious::Static;
use Mojolicious::Types;
use Mojolicious::Validator;
use Scalar::Util ();

has commands         => sub { Mojolicious::Commands->new(app => shift) };
has controller_class => 'Mojolicious::Controller';
has home             => sub { Mojo::Home->new->detect(ref shift) };
has log              => sub {
  my $self = shift;

  # Check if we have a log directory that is writable
  my $log  = Mojo::Log->new;
  my $home = $self->home;
  my $mode = $self->mode;
  $log->path($home->child('log', "$mode.log")) if -d $home->child('log') && -w _;

  # Reduced log output outside of development mode
  return $log->level($ENV{MOJO_LOG_LEVEL}) if $ENV{MOJO_LOG_LEVEL};
  return $mode eq 'development' ? $log : $log->level('info');
};
has 'max_request_size';
has mode     => sub { $ENV{MOJO_MODE} || $ENV{PLACK_ENV} || 'development' };
has moniker  => sub { Mojo::Util::decamelize ref shift };
has plugins  => sub { Mojolicious::Plugins->new };
has renderer => sub { Mojolicious::Renderer->new };
has routes   => sub { Mojolicious::Routes->new };
has secrets  => sub {
  my $self = shift;

  # Warn developers about insecure default
  $self->log->debug('Your secret passphrase needs to be changed');

  # Default to moniker
  return [$self->moniker];
};
has sessions  => sub { Mojolicious::Sessions->new };
has static    => sub { Mojolicious::Static->new };
has types     => sub { Mojolicious::Types->new };
has ua        => sub { Mojo::UserAgent->new };
has validator => sub { Mojolicious::Validator->new };

our $CODENAME = 'Supervillain';
our $VERSION  = '8.57';

sub BUILD_DYNAMIC {
  my ($class, $method, $dyn_methods) = @_;

  return sub {
    my $self    = shift;
    my $dynamic = $dyn_methods->{$self->renderer}{$method};
    return $self->build_controller->$dynamic(@_) if $dynamic;
    my $package = ref $self;
    Carp::croak qq{Can't locate object method "$method" via package "$package"};
  };
}

sub build_controller {
  my ($self, $tx) = @_;

  # Embedded application
  my $stash = {};
  if ($tx && (my $sub = $tx->can('stash'))) { ($stash, $tx) = ($tx->$sub, $tx->tx) }

  # Build default controller
  my $defaults = $self->defaults;
  @$stash{keys %$defaults} = values %$defaults;
  my $c = $self->controller_class->new(app => $self, stash => $stash, tx => $tx);
  $c->{tx} ||= $self->build_tx;

  return $c;
}

sub build_tx {
  my $self = shift;

  my $tx  = Mojo::Transaction::HTTP->new;
  my $max = $self->max_request_size;
  $tx->req->max_message_size($max) if defined $max;
  $self->plugins->emit_hook(after_build_tx => $tx, $self);

  return $tx;
}

sub config   { Mojo::Util::_stash(config   => @_) }
sub defaults { Mojo::Util::_stash(defaults => @_) }

sub dispatch {
  my ($self, $c) = @_;

  my $plugins = $self->plugins->emit_hook(before_dispatch => $c);

  # Try to find a static file
  my $tx = $c->tx;
  $self->static->dispatch($c) and $plugins->emit_hook(after_static => $c) unless $tx->res->code;

  # Start timer (ignore static files)
  my $stash = $c->stash;
  $c->helpers->log->debug(sub {
    my $req    = $c->req;
    my $method = $req->method;
    my $path   = $req->url->path->to_abs_string;
    $c->helpers->timing->begin('mojo.timer');
    return qq{$method "$path"};
  }) unless $stash->{'mojo.static'};

  # Routes
  $plugins->emit_hook(before_routes => $c);
  $c->helpers->reply->not_found
    unless $tx->res->code || $self->routes->dispatch($c) || $tx->res->code || $c->stash->{'mojo.rendered'};
}

sub handler {
  my $self = shift;

  # Dispatcher has to be last in the chain
  ++$self->{dispatch}
    and $self->hook(around_action   => \&_action)
    and $self->hook(around_dispatch => sub { $_[1]->app->dispatch($_[1]) })
    unless $self->{dispatch};

  # Process with chain
  my $c = $self->build_controller(@_);
  $self->plugins->emit_chain(around_dispatch => $c);

  # Delayed response
  $c->helpers->log->debug('Nothing has been rendered, expecting delayed response') unless $c->stash->{'mojo.rendered'};
}

sub helper { shift->renderer->add_helper(@_) }

sub hook { shift->plugins->on(@_) }

sub new {
  my $self = shift->SUPER::new(@_);

  my $home = $self->home;
  push @{$self->renderer->paths}, $home->child('templates')->to_string;
  push @{$self->static->paths},   $home->child('public')->to_string;

  # Default to controller and application namespace
  my $r = $self->routes->namespaces(["@{[ref $self]}::Controller", ref $self]);

  # Hide controller attributes/methods
  $r->hide(qw(app continue cookie every_cookie every_param every_signed_cookie finish helpers match on param render));
  $r->hide(qw(render_later render_maybe render_to_string rendered req res send session signed_cookie stash tx url_for));
  $r->hide(qw(write write_chunk));

  $self->plugin($_) for qw(HeaderCondition DefaultHelpers TagHelpers EPLRenderer EPRenderer);

  # Exception handling should be first in chain
  $self->hook(around_dispatch => \&_exception);

  $self->startup;

  return $self;
}

sub plugin {
  my $self = shift;
  $self->plugins->register_plugin(shift, $self, @_);
}

sub server { $_[0]->plugins->emit_hook(before_server_start => @_[1, 0]) }

sub start {
  my $self = shift;
  $_->warmup for $self->static, $self->renderer;
  return $self->commands->run(@_ ? @_ : @ARGV);
}

sub startup { }

sub _action {
  my ($next, $c, $action, $last) = @_;
  my $val = $action->($c);
  $val->catch(sub { $c->helpers->reply->exception(shift) }) if Scalar::Util::blessed $val && $val->isa('Mojo::Promise');
  return $val;
}

sub _die { CORE::die ref $_[0] ? $_[0] : Mojo::Exception->new(shift)->trace }

sub _exception {
  my ($next, $c) = @_;
  local $SIG{__DIE__} = \&_die;
  $c->helpers->reply->exception($@) unless eval { $next->(); 1 };
}

1;

=encoding utf8

=head1 NAME

Mojolicious - Real-time web framework

=head1 SYNOPSIS

  # Application
  package MyApp;
  use Mojo::Base 'Mojolicious';

  # Route
  sub startup {
    my $self = shift;
    $self->routes->get('/hello')->to('foo#hello');
  }

  # Controller
  package MyApp::Controller::Foo;
  use Mojo::Base 'Mojolicious::Controller';

  # Action
  sub hello {
    my $self = shift;
    $self->render(text => 'Hello World!');
  }

=head1 DESCRIPTION

An amazing real-time web framework built on top of the powerful L<Mojo> web development toolkit. With support for
RESTful routes, plugins, commands, Perl-ish templates, content negotiation, session management, form validation,
testing framework, static file server, C<CGI>/C<PSGI> detection, first class Unicode support and much more for you to
discover.

Take a look at our excellent documentation in L<Mojolicious::Guides>!

=head1 HOOKS

L<Mojolicious> will emit the following hooks in the listed order.

=head2 before_command

Emitted right before the application runs a command through the command line interface. Note that this hook is
B<EXPERIMENTAL> and might change without warning!

  $app->hook(before_command => sub {
    my ($command, $args) = @_;
    ...
  });

Useful for reconfiguring the application before running a command or to modify the behavior of a command. (Passed the
command object and the command arguments)

=head2 before_server_start

Emitted right before the application server is started, for web servers that support it, which includes all the
built-in ones (except for L<Mojo::Server::CGI>).

  $app->hook(before_server_start => sub {
    my ($server, $app) = @_;
    ...
  });

Useful for reconfiguring application servers dynamically or collecting server diagnostics information. (Passed the
server and application objects)

=head2 after_build_tx

Emitted right after the transaction is built and before the HTTP request gets parsed.

  $app->hook(after_build_tx => sub {
    my ($tx, $app) = @_;
    ...
  });

This is a very powerful hook and should not be used lightly, it makes some rather advanced features such as upload
progress bars possible. Note that this hook will not work for embedded applications, because only the host application
gets to build transactions. (Passed the transaction and application objects)

=head2 around_dispatch

Emitted right after a new request has been received and wraps around the whole dispatch process, so you have to
manually forward to the next hook if you want to continue the chain. Default exception handling with
L<Mojolicious::Plugin::DefaultHelpers/"reply-E<gt>exception"> is the first hook in the chain and a call to
L</"dispatch"> the last, yours will be in between.

  $app->hook(around_dispatch => sub {
    my ($next, $c) = @_;
    ...
    $next->();
    ...
  });

This is a very powerful hook and should not be used lightly, it allows you to, for example, customize application-wide
exception handling, consider it the sledgehammer in your toolbox. (Passed a callback leading to the next hook and the
default controller object)

=head2 before_dispatch

Emitted right before the static file server and router start their work.

  $app->hook(before_dispatch => sub {
    my $c = shift;
    ...
  });

Very useful for rewriting incoming requests and other preprocessing tasks. (Passed the default controller object)

=head2 after_static

Emitted after a static file response has been generated by the static file server.

  $app->hook(after_static => sub {
    my $c = shift;
    ...
  });

Mostly used for post-processing static file responses. (Passed the default controller object)

=head2 before_routes

Emitted after the static file server determined if a static file should be served and before the router starts its
work.

  $app->hook(before_routes => sub {
    my $c = shift;
    ...
  });

Mostly used for custom dispatchers and collecting metrics. (Passed the default controller object)

=head2 around_action

Emitted right before an action gets executed and wraps around it, so you have to manually forward to the next hook if
you want to continue the chain. Default action dispatching is the last hook in the chain, yours will run before it.

  $app->hook(around_action => sub {
    my ($next, $c, $action, $last) = @_;
    ...
    return $next->();
  });

This is a very powerful hook and should not be used lightly, it allows you for example to pass additional arguments to
actions or handle return values differently. Note that this hook can trigger more than once for the same request if
there are nested routes. (Passed a callback leading to the next hook, the current controller object, the action
callback and a flag indicating if this action is an endpoint)

=head2 before_render

Emitted before content is generated by the renderer. Note that this hook can trigger out of order due to its dynamic
nature, and with embedded applications will only work for the application that is rendering.

  $app->hook(before_render => sub {
    my ($c, $args) = @_;
    ...
  });

Mostly used for pre-processing arguments passed to the renderer. (Passed the current controller object and the render
arguments)

=head2 after_render

Emitted after content has been generated by the renderer that will be assigned to the response. Note that this hook can
trigger out of order due to its dynamic nature, and with embedded applications will only work for the application that
is rendering.

  $app->hook(after_render => sub {
    my ($c, $output, $format) = @_;
    ...
  });

Mostly used for post-processing dynamically generated content. (Passed the current controller object, a reference to
the content and the format)

=head2 after_dispatch

Emitted in reverse order after a response has been generated. Note that this hook can trigger out of order due to its
dynamic nature, and with embedded applications will only work for the application that is generating the response.

  $app->hook(after_dispatch => sub {
    my $c = shift;
    ...
  });

Useful for rewriting outgoing responses and other post-processing tasks. (Passed the current controller object)

=head1 ATTRIBUTES

L<Mojolicious> implements the following attributes.

=head2 commands

  my $commands = $app->commands;
  $app         = $app->commands(Mojolicious::Commands->new);

Command line interface for your application, defaults to a L<Mojolicious::Commands> object.

  # Add another namespace to load commands from
  push @{$app->commands->namespaces}, 'MyApp::Command';

=head2 controller_class

  my $class = $app->controller_class;
  $app      = $app->controller_class('Mojolicious::Controller');

Class to be used for the default controller, defaults to L<Mojolicious::Controller>. Note that this class needs to have
already been loaded before the first request arrives.

=head2 home

  my $home = $app->home;
  $app     = $app->home(Mojo::Home->new);

The home directory of your application, defaults to a L<Mojo::Home> object which stringifies to the actual path.

  # Portably generate path relative to home directory
  my $path = $app->home->child('data', 'important.txt');

=head2 log

  my $log = $app->log;
  $app    = $app->log(Mojo::Log->new);

The logging layer of your application, defaults to a L<Mojo::Log> object. The level will default to either the
C<MOJO_LOG_LEVEL> environment variable, C<debug> if the L</mode> is C<development>, or C<info> otherwise. All messages
will be written to C<STDERR>, or a C<log/$mode.log> file if a C<log> directory exists.

  # Log debug message
  $app->log->debug('It works');

=head2 max_request_size

  my $max = $app->max_request_size;
  $app    = $app->max_request_size(16777216);

Maximum request size in bytes, defaults to the value of L<Mojo::Message/"max_message_size">. Setting the value to C<0>
will allow requests of indefinite size. Note that increasing this value can also drastically increase memory usage,
should you for example attempt to parse an excessively large request body with the methods L<Mojo::Message/"dom"> or
L<Mojo::Message/"json">.

=head2 mode

  my $mode = $app->mode;
  $app     = $app->mode('production');

The operating mode for your application, defaults to a value from the C<MOJO_MODE> and C<PLACK_ENV> environment
variables or C<development>.

=head2 moniker

  my $moniker = $app->moniker;
  $app        = $app->moniker('foo_bar');

Moniker of this application, often used as default filename for configuration files and the like, defaults to
decamelizing the application class with L<Mojo::Util/"decamelize">.

=head2 plugins

  my $plugins = $app->plugins;
  $app        = $app->plugins(Mojolicious::Plugins->new);

The plugin manager, defaults to a L<Mojolicious::Plugins> object. See the L</"plugin"> method below if you want to load
a plugin.

  # Add another namespace to load plugins from
  push @{$app->plugins->namespaces}, 'MyApp::Plugin';

=head2 renderer

  my $renderer = $app->renderer;
  $app         = $app->renderer(Mojolicious::Renderer->new);

Used to render content, defaults to a L<Mojolicious::Renderer> object. For more information about how to generate
content see L<Mojolicious::Guides::Rendering>.

  # Enable compression
  $app->renderer->compress(1);

  # Add another "templates" directory
  push @{$app->renderer->paths}, '/home/sri/templates';

  # Add another "templates" directory with higher precedence
  unshift @{$app->renderer->paths}, '/home/sri/themes/blue/templates';

  # Add another class with templates in DATA section
  push @{$app->renderer->classes}, 'Mojolicious::Plugin::Fun';

=head2 routes

  my $routes = $app->routes;
  $app       = $app->routes(Mojolicious::Routes->new);

The router, defaults to a L<Mojolicious::Routes> object. You use this in your startup method to define the url
endpoints for your application.

  # Add routes
  my $r = $app->routes;
  $r->get('/foo/bar')->to('test#foo', title => 'Hello Mojo!');
  $r->post('/baz')->to('test#baz');

  # Add another namespace to load controllers from
  push @{$app->routes->namespaces}, 'MyApp::MyController';

=head2 secrets

  my $secrets = $app->secrets;
  $app        = $app->secrets([$bytes]);

Secret passphrases used for signed cookies and the like, defaults to the L</"moniker"> of this application, which is
not very secure, so you should change it!!! As long as you are using the insecure default there will be debug messages
in the log file reminding you to change your passphrase. Only the first passphrase is used to create new signatures,
but all of them for verification. So you can increase security without invalidating all your existing signed cookies by
rotating passphrases, just add new ones to the front and remove old ones from the back.

  # Rotate passphrases
  $app->secrets(['new_passw0rd', 'old_passw0rd', 'very_old_passw0rd']);

=head2 sessions

  my $sessions = $app->sessions;
  $app         = $app->sessions(Mojolicious::Sessions->new);

Signed cookie based session manager, defaults to a L<Mojolicious::Sessions> object. You can usually leave this alone,
see L<Mojolicious::Controller/"session"> for more information about working with session data.

  # Change name of cookie used for all sessions
  $app->sessions->cookie_name('mysession');

  # Disable SameSite feature
  $app->sessions->samesite(undef);

=head2 static

  my $static = $app->static;
  $app       = $app->static(Mojolicious::Static->new);

For serving static files from your C<public> directories, defaults to a L<Mojolicious::Static> object.

  # Add another "public" directory
  push @{$app->static->paths}, '/home/sri/public';

  # Add another "public" directory with higher precedence
  unshift @{$app->static->paths}, '/home/sri/themes/blue/public';

  # Add another class with static files in DATA section
  push @{$app->static->classes}, 'Mojolicious::Plugin::Fun';

  # Remove built-in favicon
  delete $app->static->extra->{'favicon.ico'};

=head2 types

  my $types = $app->types;
  $app      = $app->types(Mojolicious::Types->new);

Responsible for connecting file extensions with MIME types, defaults to a L<Mojolicious::Types> object.

  # Add custom MIME type
  $app->types->type(twt => 'text/tweet');

=head2 ua

  my $ua = $app->ua;
  $app   = $app->ua(Mojo::UserAgent->new);

A full featured HTTP user agent for use in your applications, defaults to a L<Mojo::UserAgent> object.

  # Perform blocking request
  say $app->ua->get('example.com')->result->body;

=head2 validator

  my $validator = $app->validator;
  $app          = $app->validator(Mojolicious::Validator->new);

Validate values, defaults to a L<Mojolicious::Validator> object.

  # Add validation check
  $app->validator->add_check(foo => sub {
    my ($v, $name, $value) = @_;
    return $value ne 'foo';
  });

  # Add validation filter
  $app->validator->add_filter(quotemeta => sub {
    my ($v, $name, $value) = @_;
    return quotemeta $value;
  });

=head1 METHODS

L<Mojolicious> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 build_controller

  my $c = $app->build_controller;
  my $c = $app->build_controller(Mojo::Transaction::HTTP->new);
  my $c = $app->build_controller(Mojolicious::Controller->new);

Build default controller object with L</"controller_class">.

  # Render template from application
  my $foo = $app->build_controller->render_to_string(template => 'foo');

=head2 build_tx

  my $tx = $app->build_tx;

Build L<Mojo::Transaction::HTTP> object and emit L</"after_build_tx"> hook.

=head2 config

  my $hash = $app->config;
  my $foo  = $app->config('foo');
  $app     = $app->config({foo => 'bar', baz => 23});
  $app     = $app->config(foo => 'bar', baz => 23);

Application configuration.

  # Remove value
  my $foo = delete $app->config->{foo};

  # Assign multiple values at once
  $app->config(foo => 'test', bar => 23);

=head2 defaults

  my $hash = $app->defaults;
  my $foo  = $app->defaults('foo');
  $app     = $app->defaults({foo => 'bar', baz => 23});
  $app     = $app->defaults(foo => 'bar', baz => 23);

Default values for L<Mojolicious::Controller/"stash">, assigned for every new request.

  # Remove value
  my $foo = delete $app->defaults->{foo};

  # Assign multiple values at once
  $app->defaults(foo => 'test', bar => 23);

=head2 dispatch

  $app->dispatch(Mojolicious::Controller->new);

The heart of every L<Mojolicious> application, calls the L</"static"> and L</"routes"> dispatchers for every request
and passes them a L<Mojolicious::Controller> object.

=head2 handler

  $app->handler(Mojo::Transaction::HTTP->new);
  $app->handler(Mojolicious::Controller->new);

Sets up the default controller and emits the L</"around_dispatch"> hook for every request.

=head2 helper

  $app->helper(foo => sub {...});

Add or replace a helper that will be available as a method of the controller object and the application object, as well
as a function in C<ep> templates. For a full list of helpers that are available by default see
L<Mojolicious::Plugin::DefaultHelpers> and L<Mojolicious::Plugin::TagHelpers>.

  # Helper
  $app->helper(cache => sub { state $cache = {} });

  # Application
  $app->cache->{foo} = 'bar';
  my $result = $app->cache->{foo};

  # Controller
  $c->cache->{foo} = 'bar';
  my $result = $c->cache->{foo};

  # Template
  % cache->{foo} = 'bar';
  %= cache->{foo}

=head2 hook

  $app->hook(after_dispatch => sub {...});

Extend L<Mojolicious> with hooks, which allow code to be shared with all requests indiscriminately, for a full list of
available hooks see L</"HOOKS">.

  # Dispatchers will not run if there's already a response code defined
  $app->hook(before_dispatch => sub {
    my $c = shift;
    $c->render(text => 'Skipped static file server and router!')
      if $c->req->url->path->to_route =~ /do_not_dispatch/;
  });

=head2 new

  my $app = Mojolicious->new;
  my $app = Mojolicious->new(moniker => 'foo_bar');
  my $app = Mojolicious->new({moniker => 'foo_bar'});

Construct a new L<Mojolicious> application and call L</"startup">. Will automatically detect your home directory. Also
sets up the renderer, static file server, a default set of plugins and an L</"around_dispatch"> hook with the default
exception handling.

=head2 plugin

  $app->plugin('some_thing');
  $app->plugin('some_thing', foo => 23);
  $app->plugin('some_thing', {foo => 23});
  $app->plugin('SomeThing');
  $app->plugin('SomeThing', foo => 23);
  $app->plugin('SomeThing', {foo => 23});
  $app->plugin('MyApp::Plugin::SomeThing');
  $app->plugin('MyApp::Plugin::SomeThing', foo => 23);
  $app->plugin('MyApp::Plugin::SomeThing', {foo => 23});

Load a plugin, for a full list of example plugins included in the L<Mojolicious> distribution see
L<Mojolicious::Plugins/"PLUGINS">.

=head2 server

  $app->server(Mojo::Server->new);

Emits the L</"before_server_start"> hook.

=head2 start

  $app->start;
  $app->start(@ARGV);

Start the command line interface for your application. For a full list of commands that are available by default see
L<Mojolicious::Commands/"COMMANDS">. Note that the options C<-h>/C<--help>, C<--home> and C<-m>/C<--mode>, which are
shared by all commands, will be parsed from C<@ARGV> during compile time.

  # Always start daemon
  $app->start('daemon', '-l', 'http://*:8080');

=head2 startup

  $app->startup;

This is your main hook into the application, it will be called at application startup. Meant to be overloaded in a
subclass.

  sub startup {
    my $self = shift;
    ...
  }

=head1 HELPERS

In addition to the L</"ATTRIBUTES"> and L</"METHODS"> above you can also call helpers on L<Mojolicious> objects. This
includes all helpers from L<Mojolicious::Plugin::DefaultHelpers> and L<Mojolicious::Plugin::TagHelpers>. Note that
application helpers are always called with a new default controller object, so they can't depend on or change
controller state, which includes request, response and stash.

  # Call helper
  say $app->dumper({foo => 'bar'});

  # Longer version
  say $app->build_controller->helpers->dumper({foo => 'bar'});

=head1 BUNDLED FILES

The L<Mojolicious> distribution includes a few files with different licenses that have been bundled for internal use.

=head2 Mojolicious Artwork

  Copyright (C) 2010-2020, Sebastian Riedel.

Licensed under the CC-SA License, Version 4.0 L<http://creativecommons.org/licenses/by-sa/4.0>.

=head2 jQuery

  Copyright (C) jQuery Foundation.

Licensed under the MIT License, L<http://creativecommons.org/licenses/MIT>.

=head2 prettify.js

  Copyright (C) 2006, 2013 Google Inc..

Licensed under the Apache License, Version 2.0 L<http://www.apache.org/licenses/LICENSE-2.0>.

=head1 CODE NAMES

Every major release of L<Mojolicious> has a code name, these are the ones that have been used in the past.

8.0, C<Supervillain> (U+1F9B9)

7.0, C<Doughnut> (U+1F369)

6.0, C<Clinking Beer Mugs> (U+1F37B)

5.0, C<Tiger Face> (U+1F42F)

4.0, C<Top Hat> (U+1F3A9)

3.0, C<Rainbow> (U+1F308)

2.0, C<Leaf Fluttering In Wind> (U+1F343)

1.0, C<Snowflake> (U+2744)

=head1 SPONSORS

=over 2

=item

L<Stix|https://stix.no> sponsored the creation of the Mojolicious logo (designed by Nicolai Graesdal) and transferred
its copyright to Sebastian Riedel.

=item

Some of the work on this distribution has been sponsored by L<The Perl Foundation|http://www.perlfoundation.org>.

=back

=head1 PROJECT FOUNDER

Sebastian Riedel, C<kraih@mojolicious.org>

=head1 CORE DEVELOPERS

Current voting members of the core team in alphabetical order:

=over 2

CandyAngel, C<candyangel@mojolicious.org>

Christopher Rasch-Olsen Raa, C<christopher@mojolicious.org>

Dan Book, C<grinnz@mojolicious.org>

Jan Henning Thorsen, C<batman@mojolicious.org>

Joel Berger, C<jberger@mojolicious.org>

Marcus Ramberg, C<marcus@mojolicious.org>

=back

The following members of the core team are currently on hiatus:

=over 2

Abhijit Menon-Sen, C<ams@cpan.org>

Glen Hinkle, C<tempire@cpan.org>

=back

=head1 CREDITS

In alphabetical order:

=over 2

Adam Kennedy

Adriano Ferreira

Al Newkirk

Alex Efros

Alex Salimon

Alexander Karelas

Alexey Likhatskiy

Anatoly Sharifulin

Andre Parker

Andre Vieth

Andreas Guldstrand

Andreas Jaekel

Andreas Koenig

Andrew Fresh

Andrew Nugged

Andrey Khozov

Andrey Kuzmin

Andy Grundman

Aristotle Pagaltzis

Ashley Dev

Ask Bjoern Hansen

Audrey Tang

Ben Tyler

Ben van Staveren

Benjamin Erhart

Bernhard Graf

Breno G. de Oliveira

Brian Duggan

Brian Medley

Burak Gursoy

Ch Lamprecht

Charlie Brady

Chas. J. Owens IV

Chase Whitener

Christian Hansen

chromatic

Curt Tilmes

Daniel Kimsey

Daniel Mantovani

Danijel Tasov

Dagfinn Ilmari Manns�ker

Danny Thomas

David Davis

David Webb

Diego Kuperman

Dmitriy Shalashov

Dmitry Konstantinov

Dominik Jarmulowicz

Dominique Dumont

Dotan Dimet

Douglas Christopher Wilson

Ettore Di Giacinto

Eugen Konkov

Eugene Toropov

Flavio Poletti

Gisle Aas

Graham Barr

Graham Knop

Henry Tang

Hideki Yamamura

Hiroki Toyokawa

Ian Goodacre

Ilya Chesnokov

Ilya Rassadin

James Duncan

Jan Jona Javorsek

Jan Schmidt

Jaroslav Muhin

Jesse Vincent

Johannes Plunien

John Kingsley

Jonathan Yu

Josh Leder

Kamen Naydenov

Karen Etheridge

Kazuhiro Shibuya

Kevin Old

Kitamura Akatsuki

Klaus S. Madsen

Knut Arne Bjorndal

Lars Balker Rasmussen

Lee Johnson

Leon Brocard

Magnus Holm

Maik Fischer

Mark Fowler

Mark Grimes

Mark Stosberg

Martin McGrath

Marty Tennison

Matt S Trout

Matthew Lineen

Maksym Komar

Maxim Vuets

Michael Gregorowicz

Michael Harris

Michael Jemmeson

Mike Magowan

Mirko Westermeier

Mons Anderson

Moritz Lenz

Neil Watkiss

Nic Sandfield

Nils Diewald

Oleg Zhelo

Olivier Mengue

Pascal Gaudette

Paul Evans

Paul Robins

Paul Tomlin

Pavel Shaydo

Pedro Melo

Peter Edwards

Pierre-Yves Ritschard

Piotr Roszatycki

Quentin Carbonneaux

Rafal Pocztarski

Randal Schwartz

Richard Elberger

Rick Delaney

Robert Hicks

Robin Lee

Roland Lammel

Roy Storey

Ryan Jendoubi

Salvador Fandino

Santiago Zarate

Sascha Kiefer

Scott Wiersdorf

Sebastian Paaske Torholm

Sergey Zasenko

Simon Bertrang

Simone Tampieri

Shoichi Kaji

Shu Cho

Skye Shaw

Stanis Trendelenburg

Stefan Adams

Steffen Ullrich

Stephan Kulow

Stephane Este-Gracias

Stevan Little

Steve Atkins

Tatsuhiko Miyagawa

Terrence Brannon

Tianon Gravi

Tomas Znamenacek

Tudor Constantin

Ulrich Habel

Ulrich Kautz

Uwe Voelker

Veesh Goldman

Viacheslav Tykhanovskyi

Victor Engmark

Viliam Pucik

Wes Cravens

William Lindley

Yaroslav Korshak

Yuki Kimoto

Zak B. Elep

Zoffix Znet

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020, Sebastian Riedel and others.

This program is free software, you can redistribute it and/or modify it under the terms of the Artistic License version
2.0.

=head1 SEE ALSO

L<https://github.com/mojolicious/mojo>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
