package Mojolicious;
use Mojo::Base 'Mojo';

use Carp 'croak';
use Mojolicious::Commands;
use Mojolicious::Controller;
use Mojolicious::Plugins;
use Mojolicious::Renderer;
use Mojolicious::Routes;
use Mojolicious::Sessions;
use Mojolicious::Static;
use Mojolicious::Types;
use Scalar::Util 'weaken';

# "Robots don't have any emotions, and sometimes that makes me very sad."
has controller_class => 'Mojolicious::Controller';
has mode             => sub { ($ENV{MOJO_MODE} || 'development') };
has on_process       => sub {
  sub { shift->dispatch(@_) }
};
has plugins  => sub { Mojolicious::Plugins->new };
has renderer => sub { Mojolicious::Renderer->new };
has routes   => sub { Mojolicious::Routes->new };
has secret   => sub {
  my $self = shift;

  # Warn developers about unsecure default
  $self->log->debug('Your secret passphrase needs to be changed!!!');

  # Default to application name
  return ref $self;
};
has sessions => sub { Mojolicious::Sessions->new };
has static   => sub { Mojolicious::Static->new };
has types    => sub { Mojolicious::Types->new };

our $CODENAME = 'Smiling Face With Sunglasses';
our $VERSION  = '1.98';

# "These old doomsday devices are dangerously unstable.
#  I'll rest easier not knowing where they are."
sub AUTOLOAD {
  my $self = shift;

  # Method
  my ($package, $method) = our $AUTOLOAD =~ /^([\w\:]+)\:\:(\w+)$/;

  # Check for helper
  croak qq/Can't locate object method "$method" via package "$package"/
    unless my $helper = $self->renderer->helpers->{$method};

  # Call helper with fresh controller
  return $self->controller_class->new(app => $self)->$helper(@_);
}

sub DESTROY { }

# "I personalized each of your meals.
#  For example, Amy: you're cute, so I baked you a pony."
sub new {
  my $self = shift->SUPER::new(@_);

  # Transaction builder
  $self->on_transaction(
    sub {
      my $self = shift;
      my $tx   = Mojo::Transaction::HTTP->new;
      $self->plugins->run_hook(after_build_tx => ($tx, $self));
      return $tx;
    }
  );

  # Root directories
  my $home = $self->home;
  $self->renderer->root($home->rel_dir('templates'));
  $self->static->root($home->rel_dir('public'));

  # Default to application namespace
  my $r = $self->routes;
  $r->namespace(ref $self);

  # Hide own controller methods
  $r->hide(qw/AUTOLOAD DESTROY client cookie delayed finish finished/);
  $r->hide(qw/flash handler helper on_message param redirect_to render/);
  $r->hide(qw/render_content render_data render_exception render_json/);
  $r->hide(qw/render_not_found render_partial render_static render_text/);
  $r->hide(qw/rendered send_message session signed_cookie url_for/);
  $r->hide(qw/write write_chunk/);

  # Prepare log
  my $mode = $self->mode;
  $self->log->path($home->rel_file("log/$mode.log"))
    if -w $home->rel_file('log');

  # Load default plugins
  $self->plugin('CallbackCondition');
  $self->plugin('HeaderCondition');
  $self->plugin('DefaultHelpers');
  $self->plugin('TagHelpers');
  $self->plugin('EPLRenderer');
  $self->plugin('EPRenderer');
  $self->plugin('RequestTimer');
  $self->plugin('PoweredBy');

  # Reduced log output outside of development mode
  $self->log->level('info') unless $mode eq 'development';

  # Run mode
  $mode = $mode . '_mode';
  $self->$mode(@_) if $self->can($mode);

  # Startup
  $self->startup(@_);

  return $self;
}

# "Amy, technology isn't intrinsically good or evil. It's how it's used.
#  Like the Death Ray."
sub defaults {
  my $self = shift;

  # Hash
  $self->{defaults} ||= {};
  return $self->{defaults} unless @_;

  # Get
  return $self->{defaults}->{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  my $values = ref $_[0] ? $_[0] : {@_};
  for my $key (keys %$values) {
    $self->{defaults}->{$key} = $values->{$key};
  }

  return $self;
}

# The default dispatchers with exception handling
sub dispatch {
  my ($self, $c) = @_;

  # Prepare transaction
  my $tx = $c->tx;
  $c->res->code(undef) if $tx->is_websocket;
  $self->sessions->load($c);
  my $plugins = $self->plugins;
  $plugins->run_hook(before_dispatch => $c);

  # Try to find a static file
  $self->static->dispatch($c);
  $plugins->run_hook_reverse(after_static_dispatch => $c);

  # Routes
  my $res = $tx->res;
  return if $res->code;
  if (my $code = ($tx->req->error)[1]) { $res->code($code) }
  elsif ($tx->is_websocket) { $res->code(426) }
  unless ($self->routes->dispatch($c)) {
    $c->render_not_found
      unless $res->code;
  }
}

# "Bite my shiny metal ass!"
sub handler {
  my ($self, $tx) = @_;

  # Embedded application
  my $stash = {};
  if ($tx->can('stash')) {
    $stash = $tx->stash;
    $tx    = $tx->tx;
  }

  # Build default controller and process
  my $defaults = $self->defaults;
  @{$stash}{keys %$defaults} = values %$defaults;
  my $c =
    $self->controller_class->new(app => $self, stash => $stash, tx => $tx);
  weaken $c->{app};
  unless (eval { $self->on_process->($self, $c); 1 }) {
    $self->log->fatal("Processing request failed: $@");
    $tx->res->code(500);
    $tx->resume;
  }

  # Delayed
  $self->log->debug('Nothing has been rendered, assuming delayed response.')
    unless $stash->{'mojo.rendered'} || $tx->is_writing;
}

# "This snow is beautiful. I'm glad global warming never happened.
#  Actually, it did. But thank God nuclear winter canceled it out."
sub helper {
  my $self = shift;
  my $name = shift;
  my $r    = $self->renderer;
  $self->log->debug(qq/Helper "$name" already exists, replacing./)
    if exists $r->helpers->{$name};
  $r->add_helper($name, @_);
}

# "He knows when you are sleeping.
#  He knows when you're on the can.
#  He'll hunt you down and blast your ass, from here to Pakistan.
#  Oh...
#  You better not breathe, you better not move.
#  You're better off dead, I'm tellin' you, dude.
#  Santa Claus is gunning you down!"
sub hook { shift->plugins->add_hook(@_) }

sub plugin {
  my $self = shift;
  $self->plugins->register_plugin(shift, $self, @_);
}

# Start command system
sub start {
  my $class = shift;

  # Executable
  $ENV{MOJO_EXE} ||= (caller)[1];

  # We are the application
  $ENV{MOJO_APP} = ref $class ? $class : $class->new;

  # Start!
  Mojolicious::Commands->start(@_);
}

# This will run once at startup
sub startup { }

1;
__END__

=head1 NAME

Mojolicious - Duct Tape For The Web!

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
  package MyApp::Foo;
  use Mojo::Base 'Mojolicious::Controller';

  # Action
  sub hello {
    my $self = shift;
    $self->render_text('Hello World!');
  }

=head1 DESCRIPTION

Web development for humans, making hard things possible and everything fun.

  use Mojolicious::Lite;

  # Simple plain text response
  get '/' => sub {
    my $self = shift;
    $self->render_text('Hello World!');
  };

  # Route associating the "/time" URL to template in DATA section
  get '/time' => 'clock';

  # RESTful web service sending JSON responses
  get '/list/:offset' => sub {
    my $self = shift;
    $self->render_json({list => [0 .. $self->param('offset')]});
  };

  # Scrape and return information from remote sites
  post '/title' => sub {
    my $self = shift;
    my $url  = $self->param('url') || 'http://mojolicio.us';
    $self->render_text(
      $self->ua->get($url)->res->dom->html->head->title->text);
  };

  # WebSocket echo service
  websocket '/echo' => sub {
    my $self = shift;
    $self->on_message(sub {
      my ($self, $message) = @_;
      $self->send_message("echo: $message");
    });
  };

  app->start;
  __DATA__

  @@ clock.html.ep
  % use Time::Piece;
  % my $now = localtime;
  <%= link_to clock => begin %>
    The time is <%= $now->hms %>.
  <% end %>

Single file prototypes can easily grow into well-structured applications.
A controller collects several actions together.

  package MyApp::Example;
  use Mojo::Base 'Mojolicious::Controller';

  # Plain text response
  sub hello {
    my $self = shift;
    $self->render_text('Hello World!');
  }

  # Render external template "templates/example/clock.html.ep"
  sub clock { }

  # RESTful web service sending JSON responses
  sub restful {
    my $self = shift;
    $self->render_json({list => [0 .. $self->param('offset')]});
  }

  # Scrape and return information from remote sites
  sub title {
    my $self = shift;
    my $url  = $self->param('url') || 'http://mojolicio.us';
    $self->render_text(
      $self->ua->get($url)->res->dom->html->head->title->text);
  }

  1;

While the application class is unique, you can have as many controllers as
you like.

  package MyApp::Realtime;
  use Mojo::Base 'Mojolicious::Controller';

  # WebSocket echo service
  sub echo {
    my $self = shift;
    $self->on_message(sub {
      my ($self, $message) = @_;
      $self->send_message("echo: $message");
    });
  }

  1;

Larger applications benefit from the separation of actions and routes,
especially when working in a team.

  package MyApp;
  use Mojo::Base 'Mojolicious';

  # Runs once on application startup
  sub startup {
    my $self = shift;
    my $r    = $self->routes;

    # Create a route at "/example" for the "MyApp::Example" controller
    my $example = $r->route('/example')->to('example#');

    # Connect these HTTP GET routes to actions in the controller
    # (paths are relative to the controller)
    $example->get('/')->to('#hello');
    $example->get('/time')->to('#clock');
    $example->get('/list/:offset')->to('#restful');

    # All common HTTP verbs are supported
    $example->post('/title')->to('#title');

    # ...and much, much more
    # (including multiple, auto-discovered controllers)
    $r->websocket('/echo')->to('realtime#echo');
  }

  1;

Through all of these changes, your action code and templates can stay almost
exactly the same.

  % use Time::Piece;
  % my $now = localtime;
  <%= link_to clock => begin %>
    The time is <%= $now->hms %>.
  <% end %>

Mojolicious has been designed from the ground up for a fun and unique
workflow.

=head2 Want To Know More?

Take a look at our excellent documentation in L<Mojolicious::Guides>!

=head1 ATTRIBUTES

L<Mojolicious> inherits all attributes from L<Mojo> and implements the
following new ones.

=head2 C<controller_class>

  my $class = $app->controller_class;
  $app      = $app->controller_class('Mojolicious::Controller');

Class to be used for the default controller, defaults to
L<Mojolicious::Controller>.

=head2 C<mode>

  my $mode = $app->mode;
  $app     = $app->mode('production');

The operating mode for your application, defaults to the value of the
C<MOJO_MODE> environment variable or C<development>.
You can also add per mode logic to your application by defining methods named
C<${mode}_mode> in the application class, which will be called right before
C<startup>.

  sub development_mode {
    my $self = shift;
    ...
  }

  sub production_mode {
    my $self = shift;
    ...
  }

Right before calling C<startup> and mode specific methods, L<Mojolicious>
will pick up the current mode, name the log file after it and raise the log
level from C<debug> to C<info> if it has a value other than C<development>.

=head2 C<on_process>

  my $process = $app->on_process;
  $app        = $app->on_process(sub {...});

Request processing callback, defaults to calling the C<dispatch> method.
Generally you will use a plugin or controller instead of this, consider it
the sledgehammer in your toolbox.

  $app->on_process(sub {
    my ($self, $c) = @_;
    $self->dispatch($c);
  });

=head2 C<plugins>

  my $plugins = $app->plugins;
  $app        = $app->plugins(Mojolicious::Plugins->new);

The plugin loader, defaults to a L<Mojolicious::Plugins> object.
You can usually leave this alone, see L<Mojolicious::Plugin> if you want to
write a plugin or the C<plugin> method below if you want to load a plugin.

=head2 C<renderer>

  my $renderer = $app->renderer;
  $app         = $app->renderer(Mojolicious::Renderer->new);

Used in your application to render content, defaults to a
L<Mojolicious::Renderer> object.
The two main renderer plugins L<Mojolicious::Plugin::EPRenderer> and
L<Mojolicious::Plugin::EPLRenderer> contain more information.

=head2 C<routes>

  my $routes = $app->routes;
  $app       = $app->routes(Mojolicious::Routes->new);

The routes dispatcher, defaults to a L<Mojolicious::Routes> object.
You use this in your startup method to define the url endpoints for your
application.

  sub startup {
    my $self = shift;

    my $r = $self->routes;
    $r->route('/:controller/:action')->to('test#welcome');
  }

=head2 C<secret>

  my $secret = $app->secret;
  $app       = $app->secret('passw0rd');

A secret passphrase used for signed cookies and the like, defaults to the
application name which is not very secure, so you should change it!!!
As long as you are using the unsecure default there will be debug messages in
the log file reminding you to change your passphrase.

=head2 C<sessions>

  my $sessions = $app->sessions;
  $app         = $app->sessions(Mojolicious::Sessions->new);

Simple signed cookie based sessions, defaults to a L<Mojolicious::Sessions>
object.
You can usually leave this alone, see L<Mojolicious::Controller/"session">
for more information about working with session data.

=head2 C<static>

  my $static = $app->static;
  $app       = $app->static(Mojolicious::Static->new);

For serving static assets from your C<public> directory, defaults to a
L<Mojolicious::Static> object.

=head2 C<types>

  my $types = $app->types;
  $app      = $app->types(Mojolicious::Types->new);

Responsible for connecting file extensions with MIME types, defaults to a
L<Mojolicious::Types> object.

  $app->types->type(twt => 'text/tweet');

=head1 METHODS

L<Mojolicious> inherits all methods from L<Mojo> and implements the following
new ones.

=head2 C<new>

  my $app = Mojolicious->new;

Construct a new L<Mojolicious> application.
Will automatically detect your home directory and set up logging based on
your current operating mode.
Also sets up the renderer, static dispatcher and a default set of plugins.

=head2 C<defaults>

  my $defaults = $app->defaults;
  my $foo      = $app->defaults('foo');
  $app         = $app->defaults({foo => 'bar'});
  $app         = $app->defaults(foo => 'bar');

Default values for the stash, assigned for every new request.

  $app->defaults->{foo} = 'bar';
  my $foo = $app->defaults->{foo};
  delete $app->defaults->{foo};

=head2 C<dispatch>

  $app->dispatch($c);

The heart of every Mojolicious application, calls the static and routes
dispatchers for every request and passes them a L<Mojolicious::Controller>
object.

=head2 C<handler>

  $tx = $app->handler($tx);

Sets up the default controller and calls process for every request.

=head2 C<helper>

  $app->helper(foo => sub {...});

Add a new helper that will be available as a method of the controller object
and the application object, as well as a function in C<ep> templates.

  # Helper
  $app->helper(add => sub { $_[1] + $_[2] });

  # Controller/Application
  my $result = $self->add(2, 3);

  # Template
  <%= add 2, 3 %>

=head2 C<hook>

  $app->hook(after_dispatch => sub {...});

Extend L<Mojolicious> by adding hooks to named events.

The following events are available and run in the listed order.

=over 2

=item after_build_tx

Triggered right after the transaction is built and before the HTTP request
gets parsed, the callbacks of this hook run in the order they were added.
One use case would be upload progress bars.
(Passed the transaction and application instances)

  $app->hook(after_build_tx => sub {
    my ($tx, $app) = @_;
  });

=item before_dispatch

Triggered right before the static and routes dispatchers start their work,
the callbacks of this hook run in the order they were added.
Very useful for rewriting incoming requests and other preprocessing tasks.
(Passed the default controller instance)

  $app->hook(before_dispatch => sub {
    my $self = shift;
  });

=item after_static_dispatch

Triggered after the static dispatcher determined if a static file should be
served and before the routes dispatcher starts its work, the callbacks of
this hook run in reverse order.
Mostly used for custom dispatchers and postprocessing static file responses.
(Passed the default controller instance)

  $app->hook(after_static_dispatch => sub {
    my $self = shift;
  });

=item before_render

Triggered right before the renderer turns the stash into a response, the
callbacks of this hook run in the order they were added.
Very useful for making adjustments to the stash right before rendering.
(Passed the current controller instance and argument hash)

  $app->hook(before_render => sub {
    my ($self, $args) = @_;
  });

Note that this hook is EXPERIMENTAL and might change without warning!

=item after_dispatch

Triggered after a response has been rendered, the callbacks of this hook run
in reverse order.
Note that this hook can trigger before C<after_static_dispatch> due to its
dynamic nature.
Useful for all kinds of postprocessing tasks.
(Passed the current controller instance)

  $app->hook(after_dispatch => sub {
    my $self = shift;
  });

=back

=head2 C<plugin>

  $app->plugin('some_thing');
  $app->plugin('some_thing', foo => 23);
  $app->plugin('some_thing', {foo => 23});
  $app->plugin('SomeThing');
  $app->plugin('SomeThing', foo => 23);
  $app->plugin('SomeThing', {foo => 23});
  $app->plugin('MyApp::Plugin::SomeThing');
  $app->plugin('MyApp::Plugin::SomeThing', foo => 23);
  $app->plugin('MyApp::Plugin::SomeThing', {foo => 23});

Load a plugin with L<Mojolicious::Plugins/"register_plugin">.

The following plugins are included in the L<Mojolicious> distribution as
examples.

=over 2

=item L<Mojolicious::Plugin::CallbackCondition>

Very versatile route condition for arbitrary callbacks.

=item L<Mojolicious::Plugin::Charset>

Change the application charset.

=item L<Mojolicious::Plugin::Config>

Perl-ish configuration files.

=item L<Mojolicious::Plugin::DefaultHelpers>

General purpose helper collection.

=item L<Mojolicious::Plugin::EPLRenderer>

Renderer for plain embedded Perl templates.

=item L<Mojolicious::Plugin::EPRenderer>

Renderer for more sophisiticated embedded Perl templates.

=item L<Mojolicious::Plugin::HeaderCondition>

Route condition for all kinds of headers.

=item L<Mojolicious::Plugin::I18N>

Internationalization helpers.

=item L<Mojolicious::Plugin::JSONConfig>

JSON configuration files.

=item L<Mojolicious::Plugin::Mount>

Mount whole L<Mojolicious> applications.

=item L<Mojolicious::Plugin::PODRenderer>

Renderer for POD files and documentation browser.

=item L<Mojolicious::Plugin::PoweredBy>

Add an C<X-Powered-By> header to outgoing responses.

=item L<Mojolicious::Plugin::RequestTimer>

Log timing information.

=item L<Mojolicious::Plugin::TagHelpers>

Template specific helper collection.

=back

=head2 C<start>

  Mojolicious->start;
  Mojolicious->start('daemon');

Start the L<Mojolicious::Commands> command line interface for your
application.

=head2 C<startup>

  $app->startup;

This is your main hook into the application, it will be called at application
startup.

  sub startup {
    my $self = shift;
  }

=head1 HELPERS

In addition to the attributes and methods above you can also call helpers on
instances of L<Mojolicious>.
This includes all helpers from L<Mojolicious::Plugin::DefaultHelpers> and
L<Mojolicious::Plugin::TagHelpers>.

  $app->log->debug($app->dumper({foo => 'bar'}));

=head1 SUPPORT

=head2 Web

  http://mojolicio.us

=head2 IRC

  #mojo on irc.perl.org

=head2 Mailing-List

  http://groups.google.com/group/mojolicious

=head1 DEVELOPMENT

=head2 Repository

  http://github.com/kraih/mojo

=head1 BUNDLED FILES

L<Mojolicious> ships with a few popular static files bundled in the C<public>
directory.

=head2 Mojolicious Artwork

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 jQuery

  Version 1.6.3

jQuery is a fast and concise JavaScript Library that simplifies HTML document
traversing, event handling, animating, and Ajax interactions for rapid web
development. jQuery is designed to change the way that you write JavaScript.

  Copyright 2011, John Resig.

Licensed under the MIT License, L<http://creativecommons.org/licenses/MIT>.

=head2 prettify.js

  Version 1-Jun-2011

A Javascript module and CSS file that allows syntax highlighting of source
code snippets in an html page.

  Copyright (C) 2006, Google Inc.

Licensed under the Apache License, Version 2.0
L<http://www.apache.org/licenses/LICENSE-2.0>.

=head1 CODE NAMES

Every major release of L<Mojolicious> has a code name, these are the ones
that have been used in the past.

1.4, C<Smiling Face With Sunglasses> (u1F60E)

1.3, C<Tropical Drink> (u1F379)

1.1, C<Smiling Cat Face With Heart-Shaped Eyes> (u1F63B)

1.0, C<Snowflake> (u2744)

0.999930, C<Hot Beverage> (u2615)

0.999927, C<Comet> (u2604)

0.999920, C<Snowman> (u2603)

=head1 AUTHOR

Sebastian Riedel, C<sri@cpan.org>.

=head1 CREDITS

In alphabetical order.

=over 2

Abhijit Menon-Sen

Adam Kennedy

Adriano Ferreira

Al Newkirk

Alex Salimon

Alexey Likhatskiy

Anatoly Sharifulin

Andre Vieth

Andrew Fresh

Andreas Koenig

Andy Grundman

Aristotle Pagaltzis

Ashley Dev

Ask Bjoern Hansen

Audrey Tang

Ben van Staveren

Breno G. de Oliveira

Brian Duggan

Burak Gursoy

Ch Lamprecht

Charlie Brady

Chas. J. Owens IV

Christian Hansen

chromatic

Curt Tilmes

Daniel Kimsey

Danijel Tasov

David Davis

Dmitriy Shalashov

Dmitry Konstantinov

Eugene Toropov

Gisle Aas

Glen Hinkle

Graham Barr

Henry Tang

Hideki Yamamura

James Duncan

Jan Jona Javorsek

Jaroslav Muhin

Jesse Vincent

John Kingsley

Jonathan Yu

Kazuhiro Shibuya

Kevin Old

KITAMURA Akatsuki

Lars Balker Rasmussen

Leon Brocard

Magnus Holm

Maik Fischer

Marcus Ramberg

Mark Stosberg

Matthew Lineen

Maksym Komar

Maxim Vuets

Michael Harris

Mirko Westermeier

Mons Anderson

Moritz Lenz

Nils Diewald

Oleg Zhelo

Pascal Gaudette

Paul Tomlin

Pedro Melo

Peter Edwards

Pierre-Yves Ritschard

Quentin Carbonneaux

Rafal Pocztarski

Randal Schwartz

Robert Hicks

Robin Lee

Roland Lammel

Ryan Jendoubi

Sascha Kiefer

Sergey Zasenko

Simon Bertrang

Simone Tampieri

Shu Cho

Skye Shaw

Stanis Trendelenburg

Tatsuhiko Miyagawa

Terrence Brannon

The Perl Foundation

Tomas Znamenacek

Ulrich Habel

Ulrich Kautz

Uwe Voelker

Viacheslav Tykhanovskyi

Victor Engmark

Viliam Pucik

Yaroslav Korshak

Yuki Kimoto

Zak B. Elep

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2011, Sebastian Riedel.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=cut
