package Mojo::Exception;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use IO::File;

__PACKAGE__->attr([qw/line lines_before lines_after/] => sub { [] });
__PACKAGE__->attr([qw/message raw_message/] => 'Exception!');
__PACKAGE__->attr(verbose => sub { $ENV{MOJO_EXCEPTION_VERBOSE} || 0 });

# Attempted murder? Now honestly, what is that?
# Do they give a Nobel Prize for attempted chemistry?
sub new {
    my $self = shift->SUPER::new();

    # Message
    $self->message(shift);
    my $message = $self->message;
    $self->raw_message($message);

    # Trace name and line
    my @trace;
    while ($message =~ /at\s+(.+)\s+line\s+(\d+)/g) {
        push @trace, {file => $1, line => $2};
    }

    # Frames
    foreach my $frame (reverse @trace) {

        # Frame
        my $file = $frame->{file};
        my $line = $frame->{line};

        # Readable
        if (-r $file) {

            # Slurp
            my $handle = IO::File->new("< $file");
            my @lines  = <$handle>;

            # Line
            $self->_parse_context(\@lines, $line);

            # Done
            last;
        }
    }

    # Parse specific file
    return $self unless my $lines = shift;
    my @lines = split /\n/, $lines;

    # Cleanup plain messages
    unless (ref $message) {
        my $filter = sub {
            my $num  = shift;
            my $new  = "template line $num";
            my $line = $lines[$num];
            $new .= qq/, near "$line"/ if defined $line;
            $new .= '.';
            return $new;
        };
        $message =~ s/\(eval\s+\d+\) line (\d+).*/$filter->($1)/ge;
        $self->message($message);
    }

    # Parse message
    my $line;
    $line = $1 if $self->message =~ /at\s+template\s+line\s+(\d+)/;

    # Context
    $self->_parse_context(\@lines, $line) if $line;

    return $self;
}

# You killed zombie Flanders!
# He was a zombie?
sub to_string {
    my $self = shift;

    # Verbose
    return $self->message unless $self->verbose;

    my $string = '';

    # Message
    $string .= $self->message if $self->message;

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

    return $string;
}

sub _parse_context {
    my ($self, $lines, $line) = @_;

    # Wrong file
    return unless defined $lines->[$line - 1];

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

1;
__END__

=head1 NAME

Mojo::Exception - Exceptions With Context

=head1 SYNOPSIS

    use Mojo::Exception;
    my $e = Mojo::Exception->new;

=head1 DESCRIPTION

L<Mojo::Exception> is a container for exceptions with context information.

=head1 ATTRIBUTES

L<Mojo::Exception> implements the following attributes.

=head2 C<line>

    my $line = $e->line;
    $e       = $e->line([3, 'foo']);

The line where the exception occured.

=head2 C<lines_after>

    my $lines = $e->lines_after;
    $e        = $e->lines_after([[1, 'bar'], [2, 'baz']]);

Lines after the line where the exception occured.

=head2 C<lines_before>

    my $lines = $e->lines_before;
    $e        = $e->lines_before([[4, 'bar'], [5, 'baz']]);

Lines before the line where the exception occured.

=head2 C<message>

    my $message = $e->message;
    $e          = $e->message('Oops!');

Exception message.

=head2 C<raw_message>

    my $message = $e->raw_message;
    $e          = $e->raw_message('Oops!');

Raw unprocessed exception message.

=head2 C<verbose>

    my $verbose = $e->verbose;
    $e          = $e->verbose(1);

Activate verbose rendering.

=head1 METHODS

L<Mojo::Exception> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $e = Mojo::Exception->new('Oops!');
    my $e = Mojo::Exception->new('Oops!', $file);

Construct a new L<Mojo::Exception> object.

=head2 C<to_string>

    my $string = $e->to_string;
    my $string = "$e";

Render exception with context.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
