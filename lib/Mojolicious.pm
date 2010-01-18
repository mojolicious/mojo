# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious;

use strict;
use warnings;

use base 'Mojo';

use Mojolicious::Commands;
use Mojolicious::Plugins;
use MojoX::Dispatcher::Routes;
use MojoX::Dispatcher::Static;
use MojoX::Renderer;
use MojoX::Types;

__PACKAGE__->attr(controller_class => 'Mojolicious::Controller');
__PACKAGE__->attr(mode => sub { ($ENV{MOJO_MODE} || 'development') });
__PACKAGE__->attr(plugins  => sub { Mojolicious::Plugins->new });
__PACKAGE__->attr(renderer => sub { MojoX::Renderer->new });
__PACKAGE__->attr(routes   => sub { MojoX::Dispatcher::Routes->new });
__PACKAGE__->attr(static   => sub { MojoX::Dispatcher::Static->new });
__PACKAGE__->attr(types    => sub { MojoX::Types->new });

sub new {
    my $self = shift->SUPER::new(@_);

    # Transaction builder
    $self->build_tx_cb(
        sub {

            # Build
            my $tx = Mojo::Transaction::Single->new;

            # Hook
            $self->plugins->run_hook_reverse(after_build_tx => $tx);

            return $tx;
        }
    );

    # Namespace
    $self->routes->namespace(ref $self);

    # Types
    $self->renderer->types($self->types);
    $self->static->types($self->types);

    # Root
    $self->renderer->root($self->home->rel_dir('templates'));
    $self->static->root($self->home->rel_dir('public'));

    # Hide own controller methods
    $self->routes->hide(qw/client helper param pause redirect_to/);
    $self->routes->hide(qw/render_exception render_json render_inner/);
    $self->routes->hide(qw/render_not_found render_partial render_static/);
    $self->routes->hide(qw/render_text resume url_for/);

    # Mode
    my $mode = $self->mode;

    # Log file
    $self->log->path($self->home->rel_file("log/$mode.log"))
      if -w $self->home->rel_file('log');

    # Plugins
    $self->plugin('agent_condition');
    $self->plugin('default_helpers');
    $self->plugin('epl_renderer');
    $self->plugin('ep_renderer');
    $self->plugin('request_timer');
    $self->plugin('powered_by');

    # Run mode
    $mode = $mode . '_mode';
    $self->$mode(@_) if $self->can($mode);

    # Reduced log output outside of development mode
    $self->log->level('error') unless $mode eq 'development';

    # Startup
    $self->startup(@_);

    return $self;
}

# The default dispatchers with exception handling
sub dispatch {
    my ($self, $c) = @_;

    # Hook
    $self->plugins->run_hook(before_dispatch => $c);

    # New request
    my $path = $c->req->url->path;
    $path ||= '/';
    $self->log->debug(qq/*** Request for "$path". ***/);

    # Try to find a static file
    my $e = $self->static->dispatch($c);

    # Hook
    $self->plugins->run_hook_reverse(after_static_dispatch => $c);

    # Use routes if we don't have a response yet
    $e = $self->routes->dispatch($c) if $e;

    # Exception
    if (ref $e) { $c->render_exception($e) }

    # Nothing found
    elsif ($e) { $c->render_not_found }

    # Hook
    $self->plugins->run_hook_reverse(after_dispatch => $c);
}

# Bite my shiny metal ass!
sub handler {
    my ($self, $tx) = @_;

    # Load controller class
    my $class = $self->controller_class;
    if (my $e = Mojo::Loader->load($class)) {
        $self->log->error(
            ref $e
            ? qq/Can't load controller class "$class": $e/
            : qq/Controller class "$class" doesn't exist./
        );
    }

    # Embedded application?
    my $stash = {};
    if ($tx->can('stash')) {
        $stash = $tx->stash;
        $tx    = $tx->tx;
    }

    # Build default controller and process
    eval {
        $self->process($class->new(app => $self, stash => $stash, tx => $tx));
    };
    $self->log->error("Processing request failed: $@") if $@;
}

sub plugin {
    my $self = shift;
    $self->plugins->load_plugin($self, @_);
}

# This will run for each request
sub process { shift->dispatch(@_) }

# Start command system
sub start {
    my $class = shift;

    # We can be called on class or instance
    $class = ref $class || $class;

    # We are the application
    $ENV{MOJO_APP} ||= $class;

    # Start!
    Mojolicious::Commands->start(@_);
}

# This will run once at startup
sub startup { }

1;
__END__

=head1 NAME

Mojolicious - Web Framework

=head1 SYNOPSIS

    use base 'Mojolicious';

    sub startup {
        my $self = shift;

        # Routes
        my $r = $self->routes;

        # Default route
        $r->route('/:controller/:action/:id')->to('foo#bar', id => 1);
    }

=head1 DESCRIPTION

L<Mojolicous> is a full stack MVC web framework built upon L<Mojo>.

For more user friendly documentation see L<Mojolicious::Book> and
L<Mojolicious::Lite>.

=head1 ATTRIBUTES

L<Mojolicious> inherits all attributes from L<Mojo> and implements the
following new ones.

=head2 C<mode>

    my $mode = $mojo->mode;
    $mojo    = $mojo->mode('production');

The operating mode for your application.
It defaults to the value of the environment variable C<MOJO_MODE> or
C<development>.
Mojo will name the log file after the current mode and modes other than
C<development> will result in limited log output.

If you want to add per mode logic to your application, you can add a sub
to your application named C<mode_$mode>.

    sub mode_development {
        my $self = shift;
    }

    sub mode_production {
        my $self = shift;
    }

=head2 C<plugins>

    my $plugins = $mojo->plugins;
    $mojo       = $mojo->plugins(Mojolicious::Plugins->new);

The plugin loader, by default a L<Mojolicious::Plugins> object.
You can usually leave this alone, see L<Mojolicious::Plugin> if you want to
write a plugin.

=head2 C<renderer>

    my $renderer = $mojo->renderer;
    $mojo        = $mojo->renderer(MojoX::Renderer->new);

Used in your application to render content, by default a L<MojoX::Renderer>
object.
The two main renderer plugins L<Mojolicious::Plugin::EpRenderer> and
L<Mojolicious::Plugin::EplRenderer> contain more specific information.

=head2 C<routes>

    my $routes = $mojo->routes;
    $mojo      = $mojo->routes(MojoX::Dispatcher::Routes->new);

The routes dispatcher, by default a L<MojoX::Dispatcher::Routes> object.
You use this in your startup method to define the url endpoints for your
application.

    sub startup {
        my $self = shift;

        my $r = $self->routes;
        $r->route('/:controller/:action')->to('test#welcome');
    }

=head2 C<static>

    my $static = $mojo->static;
    $mojo      = $mojo->static(MojoX::Dispatcher::Static->new);

For serving static assets from your C<public> directory, by default a
L<MojoX::Dispatcher::Static> object.

=head2 C<types>

    my $types = $mojo->types;
    $mojo     = $mojo->types(MojoX::Types->new);

Responsible for tracking the types of content you want to serve in your
application, by default a L<MojoX::Types> object.
You can easily register new types.

    $mojo->types->type(vti => 'help/vampire');

=head1 METHODS

L<Mojolicious> inherits all methods from L<Mojo> and implements the following
new ones.

=head2 C<new>

    my $mojo = Mojolicious->new;

Construct a new L<Mojolicious> application.
Will automatically detect your home directory and set up logging based on
your current operating mode.
Also sets up the renderer, static dispatcher and a default set of plugins.

=head2 C<dispatch>

    $mojo->dispatch($c);

The heart of every Mojolicious application, calls the static and routes
dispatchers for every request.

=head2 C<handler>

    $tx = $mojo->handler($tx);

Sets up the default controller and calls process for every request.

=head2 C<plugin>

    $mojo->plugin('something');
    $mojo->plugin('something', foo => 23);
    $mojo->plugin('something', {foo => 23});

Load a plugin.

=head2 C<process>

    $mojo->process($c);

This method can be overloaded to do logic on a per request basis, by default
just calls dispatch.
Generally you will use a plugin or controller instead of this, consider it
the sledgehammer in your toolbox.

    sub process {
        my ($self, $c) = @_;
        $self->dispatch($c);
    }

=head2 C<start>

    Mojolicious->start;
    Mojolicious->start('daemon');

Start the L<Mojolicious::Commands> command line interface for your
application.

=head2 C<startup>

    $mojo->startup;

This is your main hook into the application, it will be called at application
startup.

    sub startup {
        my $self = shift;
    }

=cut
