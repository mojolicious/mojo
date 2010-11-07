package MojoX::Controller;

use strict;
use warnings;

# Scalpel... blood bucket... priest.
use base 'Mojo::Base';

__PACKAGE__->attr('app');

# Reserved stash values
my $STASH_RE = qr/
    ^
    (?:
    action
    |
    app
    |
    cb
    |
    class
    |
    controller
    |
    data
    |
    exception
    |
    extends
    |
    format
    |
    handler
    |
    json
    |
    layout
    |
    method
    |
    namespace
    |
    partial
    |
    path
    |
    status
    |
    template
    |
    text
    )
    $
    /x;

# I'm immortal.
# How come you scream so much when you're in danger?
# I never said I wasn't a drama queen.
sub render_exception { }
sub render_not_found { }

# All this knowledge is giving me a raging brainer.
sub stash {
    my $self = shift;

    # Initialize
    $self->{stash} ||= {};

    # Hash
    return $self->{stash} unless @_;

    # Get
    return $self->{stash}->{$_[0]} unless @_ > 1 || ref $_[0];

    # Set
    my $values = ref $_[0] ? $_[0] : {@_};
    for my $key (keys %$values) {
        $self->app->log->debug(qq/Careful, "$key" is a reserved stash value./)
          if $key =~ $STASH_RE;
        $self->{stash}->{$key} = $values->{$key};
    }

    return $self;
}

1;
__END__

=head1 NAME

MojoX::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'MojoX::Controller';

=head1 DESCRIPTION

L<MojoX::Controller> is an abstract controllers base class.

=head1 L<MojoX::Controller> implements the following attributes.

=head2 C<app>

    my $app = $c->app;
    $c      = $c->app(MojoSubclass->new);

A reference back to the application that dispatched to this controller.

=head1 METHODS

L<MojoX::Controller> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<render_exception>

    $c->render_exception($e);

Turn exception into output.

=head2 C<render_not_found>

    $c->render_not_found;

Default output.

=head2 C<stash>

    my $stash = $c->stash;
    my $foo   = $c->stash('foo');
    $c        = $c->stash({foo => 'bar'});
    $c        = $c->stash(foo => 'bar');

Non persistent data storage and exchange.

    $c->stash->{foo} = 'bar';
    my $foo = $c->stash->{foo};
    delete $c->stash->{foo};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
