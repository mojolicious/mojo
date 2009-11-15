# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Exception;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use IO::File;

__PACKAGE__->attr([qw/line lines_before lines_after stack/] => sub { [] });
__PACKAGE__->attr(message => 'Exception!');

# Attempted murder? Now honestly, what is that?
# Do they give a Nobel Prize for attempted chemistry?
sub new {
    my $self = shift->SUPER::new();

    # Message
    $self->message(shift);

    # Stack
    my $i = 1;
    while (my ($p, $f, $l) = caller($i++)) {

        # Stack
        push @{$self->stack}, [$p, $f, $l];
    }

    # Trace name and line
    my $message = $self->message;
    my @trace;
    while ($message =~ /at\s+(.+)\s+line\s+(\d+)/g) {
        push @trace, {file => $1, line => $2};
    }

    # Frames
    foreach my $frame (reverse @trace) {

        # Frame
        my $file = $frame->{file};
        my $line = $frame->{line};

        # Readable?
        if (-r $file) {

            # Slurp
            my $handle = IO::File->new("< $file");
            my @lines  = <$handle>;

            # Line
            $self->parse_context(\@lines, $line);

            # Done
            last;
        }
    }

    return $self;
}

sub parse_context {
    my ($self, $lines, $line) = @_;

    # Context
    my $code = $lines->[$line - 1];
    chomp $code;
    $self->line([$line, $code]);

    # Cleanup
    $self->lines_before([]);
    $self->lines_after([]);

    # -2
    my $previous_line = $line - 3;
    $code = $previous_line >= 0 ? $lines->[$previous_line] : undef;
    if (defined $code) {
        chomp $code;
        push @{$self->lines_before}, [$line - 2, $code];
    }

    # -1
    $previous_line = $line - 2;
    $code = $previous_line >= 0 ? $lines->[$previous_line] : undef;
    if (defined $code) {
        chomp $code;
        push @{$self->lines_before}, [$line - 1, $code];
    }

    # +1
    my $next_line = $line;
    $code = $next_line >= 0 ? $lines->[$next_line] : undef;
    if (defined $code) {
        chomp $code;
        push @{$self->lines_after}, [$line + 1, $code];
    }

    # +2
    $next_line = $line + 1;
    $code = $next_line >= 0 ? $lines->[$next_line] : undef;
    if (defined $code) {
        chomp $code;
        push @{$self->lines_after}, [$line + 2, $code];
    }

    return $self;
}

sub to_string {
    my $self = shift;

    my $string = '';

    # Header
    $string .= ('Error around line ' . $self->line->[0] . ".\n")
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

    # Stack
    if (@{$self->stack} && $ENV{MOJO_EXCEPTION_VERBOSE}) {
        for my $frame (@{$self->stack}) {
            my $file = $frame->[1];
            my $line = $frame->[2];
            $string .= "$file: $line\n";
        }
    }

    # Message
    $string .= $self->message if $self->message;

    return $string;
}

1;
__END__

=head1 NAME

Mojo::Exception - Exception

=head1 SYNOPSIS

    use Mojo::Exception;
    my $e = Mojo::Exception->new;

=head1 DESCRIPTION

L<Mojo::Exception> is a container for exceptions.

=head1 ATTRIBUTES

L<Mojo::Exception> implements the following attributes.

=head2 C<line>

    my $line = $e->line;
    $e       = $e->line([3, 'foo']);

=head2 C<lines_after>

    my $lines = $e->lines_after;
    $e        = $e->lines_after([[1, 'bar'], [2, 'baz']]);

=head2 C<lines_before>

    my $lines = $e->lines_before;
    $e        = $e->lines_before([[4, 'bar'], [5, 'baz']]);

=head2 C<message>

    my $message = $e->message;
    $e          = $e->message('Oops!');

=head2 C<stack>

    my $stack = $e->stack;
    $e        = $e->stack([['Foo::Bar', '/foo/bar.pl', 23]]);

=head1 METHODS

L<Mojo::Exception> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $e = Mojo::Exception->new('Oops!');

=head2 C<parse_context>

    $e = $e->parse_context($lines, $line);

=head2 C<to_string>

    my $string = $e->to_string;
    my $string = "$e";

=cut
