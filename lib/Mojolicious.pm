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
    $self->routes->hide(qw/render_not_found render_partial render_text/);
    $self->routes->hide(qw/resume url_for/);

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

    # Build default controller and process
    eval { $self->process($class->new(app => $self, tx => $tx)) };
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

L<Mojolicous> is a MVC web framework built upon L<Mojo>.

For userfriendly documentation see L<Mojolicious::Book> and
L<Mojolicious::Lite>.

=head1 ATTRIBUTES

L<Mojolicious> inherits all attributes from L<Mojo> and implements the
following new ones.

=head2 C<mode>

    my $mode = $mojo->mode;
    $mojo    = $mojo->mode('production');

=head2 C<plugins>

    my $plugins = $mojo->plugins;
    $mojo       = $mojo->plugins(Mojolicious::Plugins->new);

=head2 C<renderer>

    my $renderer = $mojo->renderer;
    $mojo        = $mojo->renderer(MojoX::Renderer->new);

=head2 C<routes>

    my $routes = $mojo->routes;
    $mojo      = $mojo->routes(MojoX::Dispatcher::Routes->new);

=head2 C<static>

    my $static = $mojo->static;
    $mojo      = $mojo->static(MojoX::Dispatcher::Static->new);

=head2 C<types>

    my $types = $mojo->types;
    $mojo     = $mojo->types(MojoX::Types->new)

=head1 METHODS

L<Mojolicious> inherits all methods from L<Mojo> and implements the following
new ones.

=head2 C<new>

    my $mojo = Mojolicious->new;

=head2 C<dispatch>

    $mojo->dispatch($c);

=head2 C<handler>

    $tx = $mojo->handler($tx);

=head2 C<plugin>

    $mojo->plugin('something');
    $mojo->plugin('something', foo => 23);
    $mojo->plugin('something', {foo => 23});

=head2 C<process>

    $mojo->process($c);

=head2 C<start>

    Mojolicious->start;
    Mojolicious->start('daemon');

=head2 C<startup>

    $mojo->startup($tx);

=cut
