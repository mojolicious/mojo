# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Loader::Exception;

use strict;
use warnings;

use base 'Mojo::Template::Exception';

use IO::File;

# You killed zombie Flanders!
# He was a zombie?
sub new {
    my $self = shift->SUPER::new(shift);

    # Context
    if ($self->message =~ /at\s+(.+)\s+line\s+(\d+)/) {
        my $file = $1;
        my $line = $2;

        # Readable?
        if (-r $file) {

            # Slurp
            my $handle = IO::File->new("< $file");
            my @lines  = <$handle>;

            # Line
            $self->parse_context(\@lines, $line);
        }
    }

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Loader::Exception - Loader Exception

=head1 SYNOPSIS

    use Mojo::Loader::Exception;
    my $e = Mojo::Loader::Exception->new('Oops!');

=head1 DESCRIPTION

L<Mojo::Loader::Exception> is a container for loader exceptions.

=head1 ATTRIBUTES

L<Mojo::Loader::Exception> inherits all methods from
L<Mojo::Template::Exception>.

=head1 METHODS

L<Mojo::Loader::Exception> inherits all methods from
L<Mojo::Template::Exception> and implements the following new ones.

=head2 C<new>

    my $e = Mojo::Loader::Exception->new('Oops!');

=cut
