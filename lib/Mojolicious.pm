# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious;

use strict;
use warnings;

use base 'Mojo';

use Mojolicious::Commands;
use Mojolicious::Dispatcher;
use Mojolicious::Renderer;
use MojoX::Dispatcher::Static;
use MojoX::Types;
use Time::HiRes ();

__PACKAGE__->attr(controller_class => 'Mojolicious::Controller');
__PACKAGE__->attr(mode => sub { ($ENV{MOJO_MODE} || 'development') });
__PACKAGE__->attr(renderer => sub { Mojolicious::Renderer->new });
__PACKAGE__->attr(routes   => sub { Mojolicious::Dispatcher->new });
__PACKAGE__->attr(static   => sub { MojoX::Dispatcher::Static->new });
__PACKAGE__->attr(types    => sub { MojoX::Types->new });

# It's just like the story of the grasshopper and the octopus.
# All year long, the grasshopper kept burying acorns for the winter,
# while the octopus mooched off his girlfriend and watched TV.
# But then the winter came, and the grasshopper died,
# and the octopus ate all his acorns.
# And also he got a racecar. Is any of this getting through to you?
sub new {
    my $self = shift->SUPER::new(@_);

    # Namespace
    $self->routes->namespace(ref $self);

    # Types
    $self->renderer->types($self->types);
    $self->static->types($self->types);

    # Root
    $self->renderer->root($self->home->rel_dir('templates'));
    $self->static->root($self->home->rel_dir('public'));

    # Hide our methods
    $self->routes->hide(qw/client param pause redirect_to render_json/);
    $self->routes->hide(qw/render_inner render_partial render_text resume/);
    $self->routes->hide('url_for');

    # Mode
    my $mode = $self->mode;

    # Log file
    $self->log->path($self->home->rel_file("log/$mode.log"))
      if -w $self->home->rel_file('log');

    # Run mode
    $mode = $mode . '_mode';
    eval { $self->$mode } if $self->can($mode);
    $self->log->error(qq/Mode "$mode" failed: $@/) if $@;

    # Startup
    eval { $self->startup(@_) };
    $self->log->error("Startup failed: $@") if $@;

    return $self;
}

# The default dispatchers with exception handling
sub dispatch {
    my ($self, $c) = @_;

    # New request
    my $path = $c->req->url->path;
    $path ||= '/';
    $self->log->debug(qq/*** Request for "$path". ***/);

    # Try to find a static file
    my $e = $self->static->dispatch($c);

    # Use routes if we don't have a response yet
    $e = $self->routes->dispatch($c) if $e;

    # Exception
    if (ref $e) {
        $c->render(
            template  => 'exception',
            format    => 'html',
            status    => 500,
            exception => $e
        ) or $self->static->serve_500($c);
    }

    # Nothing found
    elsif ($e) {
        $c->render(
            template => 'not_found',
            format   => 'html',
            status   => 404
        ) or $self->static->serve_404($c);
    }
}

# Bite my shiny metal ass!
sub handler {
    my ($self, $tx) = @_;

    # Start timer
    my $start = [Time::HiRes::gettimeofday()];

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

    # End timer
    my $elapsed = sprintf '%f',
      Time::HiRes::tv_interval($start, [Time::HiRes::gettimeofday()]);
    my $rps = $elapsed == 0 ? '??' : sprintf '%.3f', 1 / $elapsed;
    $self->log->debug("Request took $elapsed seconds ($rps/s).");
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

        my $r = $self->routes;

        $r->route('/:controller/:action')
          ->to(controller => 'foo', action => 'bar');
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

=head2 C<renderer>

    my $renderer = $mojo->renderer;
    $mojo        = $mojo->renderer(Mojolicious::Renderer->new);

=head2 C<routes>

    my $routes = $mojo->routes;
    $mojo      = $mojo->routes(Mojolicious::Dispatcher->new);

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

=head2 C<process>

    $mojo->process($c);

=head2 C<start>

    Mojolicious->start;
    Mojolicious->start('daemon');

=head2 C<startup>

    $mojo->startup($tx);

=cut
