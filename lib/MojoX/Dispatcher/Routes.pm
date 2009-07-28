# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoX::Dispatcher::Routes;

use strict;
use warnings;

use base 'MojoX::Routes';

use Mojo::ByteStream 'b';
use Mojo::Loader;
use Mojo::Loader::Exception;

__PACKAGE__->attr('disallow',
    default =>
      sub { [qw/new app attr render render_partial req res stash url_for/] });
__PACKAGE__->attr('namespace');

# Hey. What kind of party is this? There's no booze and only one hooker.
sub dispatch {
    my ($self, $c) = @_;

    # Match
    my $match = $self->match($c->req->method, $c->req->url->path->to_string);
    $c->match($match);

    # No match
    return 1 unless $match && @{$match->stack};

    # Initialize stash with captures
    my %captures = %{$match->captures};
    foreach my $key (keys %captures) {
        $captures{$key} = b($captures{$key})->url_unescape->to_string;
    }
    $c->stash({%captures});

    # Walk the stack
    my $e = $self->walk_stack($c);
    return $e if $e;

    # Render
    $self->render($c);

    # All seems ok
    return;
}

sub dispatch_callback {
    my ($self, $c) = @_;

    # Debug
    $c->app->log->debug(qq/Dispatching callback./);

    # Catch errors
    local $SIG{__DIE__} = sub { die Mojo::Loader::Exception->new(shift) };

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
    $self->{_loaded} ||= {};
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

    # Not a conroller
    unless ($class->isa('MojoX::Dispatcher::Routes::Controller')) {
        $c->app->log->debug(qq/"$class" is not a controller./);
        return;
    }

    # Catch errors
    local $SIG{__DIE__} = sub { die Mojo::Loader::Exception->new(shift) };

    # Dispatch
    my $continue;
    eval { $continue = $class->new(ctx => $c)->$method($c) };

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

    # Prepare disallow
    unless ($self->{_disallow}) {
        $self->{_disallow} = {};
        $self->{_disallow}->{$_}++ for @{$self->disallow};
    }

    my $method = $field->{method};
    $method ||= $field->{action};

    # Shortcut
    return unless $method;

    # Shortcut for disallowed methods
    return if $self->{_disallow}->{$method};
    return if index($method, '_') == 0;

    # Invalid
    return unless $method =~ /^[a-zA-Z0-9_:]+$/;

    return $method;
}

sub render {
    my ($self, $c) = @_;

    # Render
    $c->render unless $c->stash->{rendered};
}

sub walk_stack {
    my ($self, $c) = @_;

    # Walk the stack
    my $hit;
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
        return $hit unless $e;
        $hit++;
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

=head2 C<disallow>

    my $disallow = $dispatcher->disallow;
    $dispatcher  = $dispatcher->disallow(
        [qw/new attr ctx render req res stash/]
    );

=head2 C<namespace>

    my $namespace = $dispatcher->namespace;
    $dispatcher   = $dispatcher->namespace('Foo::Bar::Controller');

=head1 METHODS

L<MojoX::Dispatcher::Routes> inherits all methods from L<MojoX::Routes> and
implements the follwing the ones.

=head2 C<dispatch>

    my $e = $dispatcher->dispatch(
        MojoX::Dispatcher::Routes::Context->new
    );

=head2 C<dispatch_callback>

    my $e = $dispatcher->dispatch_callback($c);

=head2 C<dispatch_controller>

    my $e = $dispatcher->dispatch_controller($c);

=head2 C<generate_class>

    my $class = $dispatcher->generate_class($c);

=head2 C<generate_method>

    my $method = $dispatcher->genrate_method($c);

=head2 C<render>

    $dispatcher->render($c);

=head2 C<walk_stack>

    my $e = $dispatcher->walk_stack($c);

=cut
