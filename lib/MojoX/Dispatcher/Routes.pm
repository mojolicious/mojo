# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Dispatcher::Routes;

use strict;
use warnings;

use base 'MojoX::Routes';

use Mojo::ByteStream 'b';
use Mojo::Exception;
use Mojo::Loader;

__PACKAGE__->attr(
    controller_base_class => 'MojoX::Dispatcher::Routes::Controller');
__PACKAGE__->attr(hidden => sub { [qw/new app attr render req res stash tx/] }
);
__PACKAGE__->attr('namespace');

__PACKAGE__->attr('_hidden');
__PACKAGE__->attr(_loaded => sub { {} });

# Hey. What kind of party is this? There's no booze and only one hooker.
sub dispatch {
    my ($self, $c) = @_;

    # Match
    my $match = $self->match($c->tx);
    $c->match($match);

    # No match
    return 1 unless $match && @{$match->stack};

    # Initialize stash with captures
    $c->stash($match->captures);

    # Prepare params
    $c->stash->{params} = $c->tx->req->params->clone;
    $c->stash->{params}->append(%{$match->captures});

    # Walk the stack
    my $e = $self->walk_stack($c);
    return $e if $e;

    # Render
    return $self->render($c);
}

sub dispatch_callback {
    my ($self, $c) = @_;

    # Debug
    $c->app->log->debug(qq/Dispatching callback./);

    # Catch errors
    local $SIG{__DIE__} = sub { die Mojo::Exception->new(shift) };

    # Dispatch
    my $continue;
    my $cb = $c->match->captures->{callback};
    eval { $continue = $cb->($c) };

    # Success!
    return 1 if $continue;

    # Callback error
    if ($@) {
        $c->app->log->error($@);
        return $@;
    }

    return;
}

sub dispatch_controller {
    my ($self, $c) = @_;

    # Method
    my $method = $self->generate_method($c);
    return unless $method;

    # Class
    my $class = $self->generate_class($c);
    return unless $class;

    # Debug
    $c->app->log->debug(qq/Dispatching "${class}::$method"./);

    # Load class
    unless ($self->_loaded->{$class}) {

        # Load
        if (my $e = Mojo::Loader->load($class)) {

            # Doesn't exist
            return unless ref $e;

            # Error
            $c->app->log->error($e);
            return $e;
        }

        # Loaded
        $self->_loaded->{$class}++;
    }

    # Not a controller
    $c->app->log->debug(qq/"$class" is not a controller./) and return
      unless $class->isa($self->controller_base_class);

    # Catch errors
    local $SIG{__DIE__} = sub { die Mojo::Exception->new(shift) };

    # Dispatch
    my $continue;
    eval {

        # Instantiate
        my $new = $class->new($c);

        # Get action
        if (my $code = $new->can($method)) {

            # Call action
            $continue = $new->$code;

            # Copy stash
            $c->stash($new->stash);
        }
    };

    # Success!
    return 1 if $continue;

    # Controller error
    if ($@) {
        $c->app->log->error($@);
        return $@;
    }

    return;
}

sub generate_class {
    my ($self, $c) = @_;

    # Field
    my $field = $c->match->captures;

    # Class
    my $class = $field->{class};
    my $controller = $field->{controller} || '';
    unless ($class) {
        my @class;
        for my $part (split /-/, $controller) {

            # Junk
            next unless $part;

            # Camelize
            push @class, b($part)->camelize;
        }
        $class = join '::', @class;
    }

    # Format
    my $namespace = $field->{namespace} || $self->namespace;
    $class = length $class ? "${namespace}::$class" : $namespace;

    # Invalid
    return unless $class =~ /^[a-zA-Z0-9_:]+$/;

    return $class;
}

sub generate_method {
    my ($self, $c) = @_;

    # Field
    my $field = $c->match->captures;

    # Prepare hidden
    unless ($self->_hidden) {
        $self->_hidden({});
        $self->_hidden->{$_}++ for @{$self->hidden};
    }

    my $method = $field->{method};
    $method ||= $field->{action};

    # Shortcut
    return unless $method;

    # Shortcut for hidden methods
    return if $self->_hidden->{$method};
    return if index($method, '_') == 0;

    # Invalid
    return unless $method =~ /^[a-zA-Z0-9_:]+$/;

    return $method;
}

sub hide { push @{shift->hidden}, @_ }

sub render {
    my ($self, $c) = @_;

    # Render
    return !$c->render
      unless $c->stash->{rendered}
          || $c->res->code
          || $c->tx->is_paused;

    # Nothing to render
    return;
}

sub walk_stack {
    my ($self, $c) = @_;

    # Walk the stack
    for my $field (@{$c->match->stack}) {

        # Don't cache errors
        local $@;

        # Captures
        $c->match->captures($field);

        # Dispatch
        my $e =
            $field->{callback}
          ? $self->dispatch_callback($c)
          : $self->dispatch_controller($c);

        # Exception
        return $e if ref $e;

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

    my $dispatcher = MojoX::Dispatcher::Routes->new;

=head1 DESCRIPTION

L<MojoX::Dispatcher::Routes> is a dispatcher based on L<MojoX::Routes>.

=head2 ATTRIBUTES

L<MojoX::Dispatcher::Routes> inherits all attributes from L<MojoX::Routes>
and implements the follwing the ones.

=head2 C<controller_base_class>

    my $base    = $dispatcher->controller_base_class;
    $dispatcher = $dispatcher->controller_base_class(
        'MojoX::Dispatcher::Routes::Controller'
    );

=head2 C<hidden>

    my $hidden  = $dispatcher->hidden;
    $dispatcher = $dispatcher->hidden(
        [qw/new attr tx render req res stash/]
    );

=head2 C<namespace>

    my $namespace = $dispatcher->namespace;
    $dispatcher   = $dispatcher->namespace('Foo::Bar::Controller');

=head1 METHODS

L<MojoX::Dispatcher::Routes> inherits all methods from L<MojoX::Routes> and
implements the follwing the ones.

=head2 C<dispatch>

    my $e = $dispatcher->dispatch(
        MojoX::Dispatcher::Routes::Controller->new
    );

=head2 C<dispatch_callback>

    my $e = $dispatcher->dispatch_callback($c);

=head2 C<dispatch_controller>

    my $e = $dispatcher->dispatch_controller($c);

=head2 C<generate_class>

    my $class = $dispatcher->generate_class($c);

=head2 C<generate_method>

    my $method = $dispatcher->genrate_method($c);

=head2 C<hide>

    $dispatcher = $dispatcher->hide('new');

=head2 C<render>

    $dispatcher->render($c);

=head2 C<walk_stack>

    my $e = $dispatcher->walk_stack($c);

=cut
