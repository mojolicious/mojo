# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Template::Exception;

use strict;
use warnings;

use base 'Mojo::Exception';

# You killed zombie Flanders!
# He was a zombie?
sub new {
    my $self = shift->SUPER::new(@_);

    # Lines
    my $lines = $_[1];

    # Shortcut
    return $self unless $lines;

    # Parse message
    my $line;
    $line = $1 if $self->message =~ /at\s+\(eval\s+\d+\)\s+line\s+(\d+)/;

    # Caller
    my $caller = (caller)[0];

    # Search template in callstack
    for my $frame (@{$self->stack}) {

        my ($p, $f, $l) = @$frame;

        # Try to find template
        if ($p eq $caller && $f =~ /^\(eval\s+\d+\)$/ && !$line) {

            # Done
            $line = $l;
        }
    }

    # Context
    my @lines = split /\n/, $lines;
    $self->parse_context(\@lines, $line) if $line;

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Template::Exception - Template Exception

=head1 SYNOPSIS

    use Mojo::Template::Exception;
    my $e = Mojo::Template::Exception->new;

=head1 DESCRIPTION

L<Mojo::Template::Exception> is a container for template exceptions.

=head1 ATTRIBUTES

L<Mojo::Template::Exception> inherits all attributes from L<Mojo::Exception>.

=head1 METHODS

L<Mojo::Template::Exception> inherits all methods from L<Mojo::Exception> and
implements the following new ones.

=head2 C<new>

    my $e = Mojo::Template::Exception->new('Oops!', $template);

=cut
