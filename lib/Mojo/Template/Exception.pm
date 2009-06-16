# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Template::Exception;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

__PACKAGE__->attr([qw/line lines_before lines_after/] =>
      (chained => 1, default => sub { [] }));
__PACKAGE__->attr('message' => (chained => 1));

# Attempted murder? Now honestly, what is that?
# Do they give a Nobel Prize for attempted chemistry?
sub to_string {
    my $self = shift;

    my $string = '';

    # Header
    my $delim = '-' x 76;
    $string .= ('Error around line ' . $self->line->[0] . ".\n$delim\n")
      if $self->line->[0];

    # Before
    for my $line (@{$self->lines_before}) {
        $string .= $line->[0] . ': ' . $line->[1] . "\n";
    }

    # Line
    $string .= ($self->line->[0] . ': ' . $self->line->[1] . "\n")
      if $self->line->[0];

    # After
    for my $line (@{$self->lines_after}) {
        $string .= $line->[0] . ': ' . $line->[1] . "\n";
    }

    # Message
    $string .= ("$delim\n" . $self->message) if $self->message;

    return $string;
}

1;
__END__

=head1 NAME

Mojo::Template::Exception - Template Exception

=head1 SYNOPSIS

    use Mojo::Template::Exception;
    my $te = Mojo::Template::Exception->new;

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head2 C<line>

    my $line = $te->line;
    $te      = $te->line([3, 'foo']);

=head2 C<lines_after>

    my $lines = $te->lines_after;
    $te       = $te->lines_after([[1, 'bar'], [2, 'baz']]);

=head2 C<lines_before>

    my $lines = $te->lines_before;
    $te       = $te->lines_before([[4, 'bar'], [5, 'baz']]);

=head2 C<message>

    my $message = $te->message;
    $te         = $te->message('oops!');

=head1 METHODS

L<Mojo::Template::Exception> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<to_string>

    my $string = $te->to_string;
    my $string = "$te";

=cut
