# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Dispatcher::Routes;

use strict;
use warnings;

use base 'MojoX::Routes';

use Mojo::ByteStream 'b';
use Mojo::Exception;
use Mojo::Loader;
use MojoX::Routes::Match;

__PACKAGE__->attr(
    controller_base_class => 'MojoX::Dispatcher::Routes::Controller');
__PACKAGE__->attr(hidden => sub { [qw/new app attr render req res stash tx/] }
);
__PACKAGE__->attr('namespace');

# Hey. What kind of party is this? There's no booze and only one hooker.
sub auto_render {
    my ($self, $c) = @_;

    # Render
    return !$c->render
      unless $c->stash->{rendered}
          || $c->res->code
          || $c->tx->is_paused;

    # Nothing to render
    return;
}

sub detour {
    my ($self, $app) = @_;

    # Load app
    unless (ref $app) {

        # Load
        if (my $e = Mojo::Loader->load($app)) {

            # Error
            die $e if ref $e;
        }

        # Instantiate
        $app = $app->new;
    }

    # Add
    $self->add_child($app->routes);

    return $self;
}

sub dispatch {
    my ($self, $c) = @_;

    # Already rendered
    return if $c->res->code;

    # Match
    my $m = MojoX::Routes::Match->new($c->tx);
    $m->match($self);
    $c->match($m);

    # No match
    return 1 unless $m && @{$m->stack};

    # Params
    my $p = $c->stash->{params} = $c->tx->req->params->clone;
    $p->append(%{$m->captures});

    # Route name
    $c->stash->{route} = $m->endpoint->name;

    # Merge in captures
    $c->stash({%{$c->stash}, %{$m->captures}});

    # Walk the stack
    return 1 if $self->_walk_stack($c);

    # Render
    return $self->auto_render($c);
}

sub hide { push @{shift->hidden}, @_ }

sub _dispatch_callback {
    my ($self, $c, $staging) = @_;

    # Debug
    $c->app->log->debug(qq/Dispatching callback./);

    # Dispatch
    my $continue;
    my $cb      = $c->match->captures->{cb};
    my $success = eval {

        # Callback
        $continue = $cb->($c);

        # Success
        1;
    };

    # Callback error
    if (!$success && $@) {
        my $e = Mojo::Exception->new($@);
        $c->app->log->error($e);
        return $e;
    }

    # Success!
    return 1 unless $staging;
    return 1 if $continue;

    return;
}

sub _dispatch_controller {
    my ($self, $c, $staging) = @_;

    # Method
    my $method = $self->_generate_method($c);
    return unless $method;

    # Class
    my $class = $self->_generate_class($c);
    return unless $class;

    # Debug
    $c->app->log->debug(qq/Dispatching "${class}::$method"./);

    # Load class
    unless ($self->{_loaded}->{$class}) {

        # Load
        if (my $e = Mojo::Loader->load($class)) {

            # Doesn't exist
            return unless ref $e;

            # Error
            $c->app->log->error($e);
            return $e;
        }

        # Loaded
        $self->{_loaded}->{$class}++;
    }

    # Not a controller
    $c->app->log->debug(qq/"$class" is not a controller./) and return
      unless $class->isa($self->controller_base_class);

    # Dispatch
    my $continue;
    my $success = eval {

        # Instantiate
        my $new = $class->new($c);

        # Get action
        if (my $code = $new->can($method)) {

            # Call action
            $continue = $new->$code;

            # Copy stash
            $c->stash($new->stash);
        }

        # Success
        1;
    };

    # Controller error
    if (!$success && $@) {
        my $e = Mojo::Exception->new($@);
        $c->app->log->error($e);
        return $e;
    }

    # Success!
    return 1 unless $staging;
    return 1 if $continue;

    return;
}

sub _generate_class {
    my ($self, $c) = @_;

    # Field
    my $field = $c->match->captures;

    # Class
    my $class = $field->{class};
    my $controller = $field->{controller} || '';
    $class = b($controller)->camelize->to_string unless $class;

    # Format
    my $namespace = $field->{namespace} || $self->namespace;
    $class = length $class ? "${namespace}::$class" : $namespace;

    # Invalid
    return unless $class =~ /^[a-zA-Z0-9_:]+$/;

    return $class;
}

sub _generate_method {
    my ($self, $c) = @_;

    # Field
    my $field = $c->match->captures;

    # Prepare hidden
    unless ($self->{_hidden}) {
        $self->{_hidden} = {};
        $self->{_hidden}->{$_}++ for @{$self->hidden};
    }

    my $method = $field->{method};
    $method ||= $field->{action};

    # Shortcut
    return unless $method;

    # Shortcut for hidden methods
    return if $self->{_hidden}->{$method};
    return if index($method, '_') == 0;

    # Invalid
    return unless $method =~ /^[a-zA-Z0-9_:]+$/;

    return $method;
}

sub _walk_stack {
    my ($self, $c) = @_;

    # Walk the stack
    my $staging = $#{$c->match->stack};
    for my $field (@{$c->match->stack}) {

        # Captures
        $c->match->captures($field);

        # Dispatch
        my $e =
            $field->{cb} ? $self->_dispatch_callback($c, $staging)
          : $field->{app} ? $self->_dispatch_app($c, $staging)
          :                 $self->_dispatch_controller($c, $staging);

        # Exception
        if (ref $e) {
            $c->render_exception($e);
            return 1;
        }

        # Break the chain
        return unless $e;
    }

    # Done
    return;
}

1;
__END__

=head1 NAME

MojoX::Dispatcher::Routes - Routes Dispatcher

=head1 SYNOPSIS

    use MojoX::Dispatcher::Routes;

    # New dispatcher
    my $dispatcher = MojoX::Dispatcher::Routes->new;

    # Dispatch
    $dispatcher->dispatch(MojoX::Dispatcher::Routes::Controller->new);

=head1 DESCRIPTION

L<MojoX::Dispatcher::Routes> is a L<MojoX::Routes> based dispatcher.

=head1 ATTRIBUTES

L<MojoX::Dispatcher::Routes> inherits all attributes from L<MojoX::Routes>
and implements the following ones.

=head2 C<controller_base_class>

    my $base    = $dispatcher->controller_base_class;
    $dispatcher = $dispatcher->controller_base_class(
        'MojoX::Dispatcher::Routes::Controller'
    );

Base class used to identify controllers, defaults to
L<MojoX::Dispatcher::Routes::Controller>.

=head2 C<hidden>

    my $hidden  = $dispatcher->hidden;
    $dispatcher = $dispatcher->hidden(
        [qw/new attr tx render req res stash/]
    );

Methods and attributes that are hidden from the dispatcher.

=head2 C<namespace>

    my $namespace = $dispatcher->namespace;
    $dispatcher   = $dispatcher->namespace('Foo::Bar::Controller');

Namespace to search for controllers.

=head1 METHODS

L<MojoX::Dispatcher::Routes> inherits all methods from L<MojoX::Routes> and
implements the following ones.

=head2 C<auto_render>

    $dispatcher->auto_render(MojoX::Dispatcher::Routes::Controller->new);

Automatic rendering.

=head2 C<detour>

    $dispatcher = $dispatcher->detour($app);
    $dispatcher = $dispatcher->detour('MyApp');

Embed routes from secondary application.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<dispatch>

    my $e = $dispatcher->dispatch(
        MojoX::Dispatcher::Routes::Controller->new
    );

Match routes and dispatch.

=head2 C<hide>

    $dispatcher = $dispatcher->hide('new');

Hide method or attribute from the dispatcher.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
