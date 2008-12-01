# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Dispatcher::Routes;

use strict;
use warnings;

use base 'MojoX::Routes';

use Mojo::ByteStream;
use Mojo::Loader;

__PACKAGE__->attr(
    disallow => (
        chained => 1,
        default => sub { [qw/new attr render req res stash/] }
    )
);
__PACKAGE__->attr(namespace => (chained => 1));

# Hey. What kind of party is this? There's no booze and only one hooker.
sub dispatch {
    my ($self, $c, $match) = @_;

    $match ||= $self->match($c->tx);
    $c->match($match);

    # Shortcut
    return 0 unless $match;

    # Initialize stash with captures
    $c->stash({%{$match->captures}});

    # Prepare disallow
    unless ($self->{_disallow}) {
        $self->{_disallow} = {};
        $self->{_disallow}->{$_}++ for @{$self->disallow};
    }

    # Walk the stack
    my $stack = $match->stack;
    for my $field (@$stack) {

        # Method
        my $method = $field->{method};
        $method ||= $field->{action};

        # Shortcut for disallowed methods
        next if $self->{_disallow}->{$method};
        next if index($method, '_') == 0;

        # Class
        my $class = $field->{class};
        my $controller = $field->{controller} || '';
        unless ($class) {
            my @class;
            for my $part (split /-/, $controller) {

                # Junk
                next unless $part;

                # Camelize
                push @class, Mojo::ByteStream->new($part)->camelize;
            }
            $class = join '::', @class;
        }

        # Format
        my $namespace = $field->{namespace} || $self->namespace;
        $class = "${namespace}::$class";

        # Debug
        $c->app->log->debug(
            qq/Dispatching "$method" in "$controller($class)"/);

        # Shortcut for invalid class and method
        next
          unless $class =~ /^[a-zA-Z0-9_:]+$/
              && $method =~ /^[a-zA-Z0-9_]+$/;

        # Captures
        $c->match->captures($field);

        # Load
        $self->{_loaded} ||= {};
        eval {
            Mojo::Loader->new->load($class);
            $self->{_loaded}->{$class}++;
        } unless $self->{_loaded}->{$class};

        # Load error
        if ($@) {
            $c->app->log->debug(
                qq/Couldn't load controller class "$class":\n$@/);
            return 0;
        }

        # Dispatch
        my $done;
        eval {
            die "$class is not a controller"
              unless $class->isa('MojoX::Dispatcher::Routes::Controller');
            $done = $class->new(ctx => $c)->$method($c);
        };

        # Controller error
        if ($@) {
            $c->app->log->debug(
                qq/Controller error in "${class}::$method":\n$@/);
            return 0;
        }

        # Break the chain
        last unless $done;
    }

    # No stack, fail
    return 0 unless @$stack;

    # All seems ok
    return 1;
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

    my $success = $dispatcher->dispatch(
        MojoX::Dispatcher::Routes::Context->new
    );
    my $success = $dispatcher->dispatch(
        MojoX::Dispatcher::Routes::Context->new,
        MojoX::Routes::Match->new
    );

=cut
