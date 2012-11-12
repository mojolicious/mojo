package Mojo::Exception;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Scalar::Util 'blessed';

has [qw(frames line lines_before lines_after)] => sub { [] };
has message => 'Exception!';
has verbose => sub { $ENV{MOJO_EXCEPTION_VERBOSE} || 0 };

sub new {
  my $self = shift->SUPER::new;
  return @_ ? $self->_detect(@_) : $self;
}

# DEPRECATED in Rainbow!
sub raw_message {
  warn "Mojo::Exception->raw_message has been DEPRECATED!\n";
  shift->message(@_);
}

sub throw { die shift->new->trace(2)->_detect(@_) }

sub to_string {
  my $self = shift;

  # Message
  return $self->message unless $self->verbose;
  my $string = $self->message ? $self->message : '';

  # Before
  $string .= $_->[0] . ': ' . $_->[1] . "\n" for @{$self->lines_before};

  # Line
  $string .= ($self->line->[0] . ': ' . $self->line->[1] . "\n")
    if $self->line->[0];

  # After
  $string .= $_->[0] . ': ' . $_->[1] . "\n" for @{$self->lines_after};

  return $string;
}

sub trace {
  my ($self, $start) = @_;
  $start //= 1;
  my @frames;
  while (my @trace = caller($start++)) { push @frames, \@trace }
  return $self->frames(\@frames);
}

sub _context {
  my ($self, $line, $lines) = @_;

  # Wrong file
  return unless defined $lines->[0][$line - 1];

  # Line
  $self->line([$line]);
  for my $l (@$lines) {
    chomp(my $code = $l->[$line - 1]);
    push @{$self->line}, $code;
  }

  # Before
  for my $i (2 .. 6) {
    last if ((my $previous = $line - $i) < 0);
    if (defined $lines->[0][$previous]) {
      unshift @{$self->lines_before}, [$previous + 1];
      for my $l (@$lines) {
        chomp(my $code = $l->[$previous]);
        push @{$self->lines_before->[0]}, $code;
      }
    }
  }

  # After
  for my $i (0 .. 4) {
    next if ((my $next = $line + $i) < 0);
    if (defined $lines->[0][$next]) {
      push @{$self->lines_after}, [$next + 1];
      for my $l (@$lines) {
        next unless defined(my $code = $l->[$next]);
        chomp $code;
        push @{$self->lines_after->[-1]}, $code;
      }
    }
  }
}

sub _detect {
  my $self = shift;

  # Message
  my $msg = shift;
  return $msg if blessed $msg && $msg->isa('Mojo::Exception');
  $self->message($msg);

  # Extract file and line from message
  my @trace;
  while ($msg =~ /at\s+(.+?)\s+line\s+(\d+)/g) { push @trace, [$1, $2] }

  # Extract file and line from stacktrace
  my $first = $self->frames->[0];
  unshift @trace, [$first->[1], $first->[2]] if $first && $first->[1];

  # Search for context in files
  for my $frame (reverse @trace) {
    next unless -r $frame->[0];
    open my $handle, '<:utf8', $frame->[0];
    $self->_context($frame->[1], [[<$handle>]]);
    return $self;
  }

  # More context
  return $self unless my $files = shift;
  $self->_context($trace[0][1], [map { [split /\n/] } @$files]);

  return $self;
}

1;

=head1 NAME

Mojo::Exception - Exceptions with context

=head1 SYNOPSIS

  use Mojo::Exception;

  # Throw exception
  Mojo::Exception->throw('Not again!');

  # Customize exception
  die Mojo::Exception->new('Not again!')->trace(2)->verbose(1);

=head1 DESCRIPTION

L<Mojo::Exception> is a container for exceptions with context information.

=head1 ATTRIBUTES

L<Mojo::Exception> implements the following attributes.

=head2 C<frames>

  my $frames = $e->frames;
  $e         = $e->frames($frames);

Stacktrace.

=head2 C<line>

  my $line = $e->line;
  $e       = $e->line([3 => 'foo']);

The line where the exception occured.

=head2 C<lines_after>

  my $lines = $e->lines_after;
  $e        = $e->lines_after([[1 => 'bar'], [2 => 'baz']]);

Lines after the line where the exception occured.

=head2 C<lines_before>

  my $lines = $e->lines_before;
  $e        = $e->lines_before([[4 => 'bar'], [5 => 'baz']]);

Lines before the line where the exception occured.

=head2 C<message>

  my $msg = $e->message;
  $e      = $e->message('Oops!');

Exception message.

=head2 C<verbose>

  my $verbose = $e->verbose;
  $e          = $e->verbose(1);

Activate verbose rendering, defaults to the value of
C<MOJO_EXCEPTION_VERBOSE> or C<0>.

=head1 METHODS

L<Mojo::Exception> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $e = Mojo::Exception->new('Oops!');
  my $e = Mojo::Exception->new('Oops!', $files);

Construct a new L<Mojo::Exception> object.

=head2 C<throw>

  Mojo::Exception->throw('Oops!');
  Mojo::Exception->throw('Oops!', $files);

Throw exception with stacktrace.

=head2 C<to_string>

  my $string = $e->to_string;
  my $string = "$e";

Render exception with context.

=head2 C<trace>

  $e = $e->trace;
  $e = $e->trace(2);

Store stacktrace.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
