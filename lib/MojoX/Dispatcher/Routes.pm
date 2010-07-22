# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Dispatcher::Routes;

use strict;
use warnings;

use base 'MojoX::Routes';

use Mojo::ByteStream 'b';
use Mojo::Exception;
use Mojo::Loader;
use MojoX::Routes::Match;
use Scalar::Util 'weaken';

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
      unless $c->stash->{'mojo.rendered'}
          || $c->res->code
          || $c->tx->is_paused;

    # Nothing to render
    return;
}

sub detour {
    my $self = shift;

    # Partial
    $self->partial('path');

    # Defaults
    $self->to(@_);

    return $self;
}

sub dispatch {
    my ($self, $c) = @_;

    # Already rendered
    return if $c->res->code;

    # Path
    my $path = $c->stash->{path};
    $path = "/$path" if defined $path && $path !~ /^\//;

    # Match
    my $m = MojoX::Routes::Match->new($c->tx, $path);
    $m->match($self);
    $c->match($m);

    # No match
    return 1 unless $m && @{$m->stack};

    # Params
    my $p = $c->stash->{'mojo.params'} = $c->tx->req->params->clone;

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

    # Application
    my $app = $c->match->captures->{app};

    # Class
    $app ||= $self->_generate_class($c);
    return unless $app;

    # Method
    my $method = $self->_generate_method($c);

    # Debug
    $c->app->log->debug('Dispatching controller.');

    # Load class
    unless (ref $app && $self->{_loaded}->{$app}) {

        # Load
        if (my $e = Mojo::Loader->load($app)) {

            # Doesn't exist
            return unless ref $e;

            # Error
            $c->app->log->error($e);
            return $e;
        }

        # Loaded
        $self->{_loaded}->{$app}++;
    }

    # Dispatch
    my $continue;
    my $success = eval {

        # Instantiate
        $app = $app->new($c) unless ref $app;

        # Action
        if ($method && $app->isa($self->controller_base_class)) {

            # Call action
            $continue = $app->$method if $app->can($method);

            # Copy stash
            $c->stash($app->stash);
        }

        # Handler
        elsif ($app->isa('Mojo')) {

            # Connect routes
            if ($app->can('routes')) {
                my $r = $app->routes;
                unless ($r->parent) {
                    $r->parent($c->match->endpoint);
                    weaken $r->{parent};
                }
            }

            # Handler
            $app->handler($c);
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

    # Namespace
    my $namespace = $field->{namespace};
    $namespace = $self->namespace unless defined $namespace;
    $class = length $class ? "${namespace}::$class" : $namespace
      if length $namespace;

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
    if ($self->{_hidden}->{$method} || index($method, '_') == 0) {
        $c->app->log->debug(qq/Action "$method" is not allowed./);
        return;
    }

    # Invalid
    unless ($method =~ /^[a-zA-Z0-9_:]+$/) {
        $c->app->log->debug(qq/Action "$method" is invalid./);
        return;
    }

    return $method;
}

sub _walk_stack {
    my ($self, $c) = @_;

    # Walk the stack
    my $staging = $#{$c->match->stack};
    for my $field (@{$c->match->stack}) {

        # Params
        $c->stash->{'mojo.params'}->append(%{$field});

        # Merge in captures
        $c->stash({%{$c->stash}, %{$field}});

        # Captures
        $c->match->captures($field);

        # Dispatch
        my $e =
            $field->{cb}
          ? $self->_dispatch_callback($c, $staging)
          : $self->_dispatch_controller($c, $staging);

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

    $dispatcher = $dispatcher->detour(action => 'foo');
    $dispatcher = $dispatcher->detour({action => 'foo'});
    $dispatcher = $dispatcher->detour('controller#action');
    $dispatcher = $dispatcher->detour('controller#action', foo => 'bar');
    $dispatcher = $dispatcher->detour('controller#action', {foo => 'bar'});
    $dispatcher = $dispatcher->detour($app);
    $dispatcher = $dispatcher->detour($app, foo => 'bar');
    $dispatcher = $dispatcher->detour($app, {foo => 'bar'});
    $dispatcher = $dispatcher->detour('MyApp');
    $dispatcher = $dispatcher->detour('MyApp', foo => 'bar');
    $dispatcher = $dispatcher->detour('MyApp', {foo => 'bar'});

Set default parameters for this route and allow partial matching to simplify
application embedding.
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
