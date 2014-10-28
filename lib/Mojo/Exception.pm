package Mojo::Exception;
use Mojo::Base -base;
use overload bool => sub {1}, '""' => sub { shift->to_string }, fallback => 1;

use Scalar::Util 'blessed';

has [qw(frames line lines_before lines_after)] => sub { [] };
has message => 'Exception!';
has 'verbose';

sub new {
  my $self = shift->SUPER::new;
  return @_ ? $self->_detect(@_) : $self;
}

sub throw { die shift->new->trace(2)->_detect(@_) }

sub to_string {
  my $self = shift;

  return $self->message unless $self->verbose;
  my $str = $self->message ? $self->message : '';

  # Before
  $str .= $_->[0] . ': ' . $_->[1] . "\n" for @{$self->lines_before};

  # Line
  $str .= ($self->line->[0] . ': ' . $self->line->[1] . "\n")
    if $self->line->[0];

  # After
  $str .= $_->[0] . ': ' . $_->[1] . "\n" for @{$self->lines_after};

  return $str;
}

sub trace {
  my ($self, $start) = @_;
  $start //= 1;
  my @frames;
  while (my @trace = caller($start++)) { push @frames, \@trace }
  return $self->frames(\@frames);
}

sub _append {
  my ($stack, $line) = @_;
  chomp $line;
  push @$stack, $line;
}

sub _context {
  my ($self, $num, $lines) = @_;

  # Line
  return unless defined $lines->[0][$num - 1];
  $self->line([$num]);
  _append($self->line, $_->[$num - 1]) for @$lines;

  # Before
  for my $i (2 .. 6) {
    last if ((my $previous = $num - $i) < 0);
    unshift @{$self->lines_before}, [$previous + 1];
    _append($self->lines_before->[0], $_->[$previous]) for @$lines;
  }

  # After
  for my $i (0 .. 4) {
    next if ((my $next = $num + $i) < 0);
    next unless defined $lines->[0][$next];
    push @{$self->lines_after}, [$next + 1];
    _append($self->lines_after->[-1], $_->[$next]) for @$lines;
  }
}

sub _detect {
  my ($self, $msg, $files) = @_;

  return $msg if blessed $msg && $msg->isa('Mojo::Exception');
  $self->message($msg);

  # Extract file and line from message
  my @trace;
  while ($msg =~ /at\s+(.+?)\s+line\s+(\d+)/g) { unshift @trace, [$1, $2] }

  # Extract file and line from stacktrace
  my $first = $self->frames->[0];
  push @trace, [$first->[1], $first->[2]] if $first;

  # Search for context in files
  for my $frame (@trace) {
    next unless -r $frame->[0] && open my $handle, '<:utf8', $frame->[0];
    $self->_context($frame->[1], [[<$handle>]]);
    return $self;
  }

  # More context
  $self->_context($trace[-1][1], [map { [split "\n"] } @$files]) if $files;

  return $self;
}

1;

=encoding utf8

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

=head2 frames

  my $frames = $e->frames;
  $e         = $e->frames($frames);

Stacktrace.

=head2 line

  my $line = $e->line;
  $e       = $e->line([3 => 'foo']);

The line where the exception occurred.

=head2 lines_after

  my $lines = $e->lines_after;
  $e        = $e->lines_after([[1 => 'bar'], [2 => 'baz']]);

Lines after the line where the exception occurred.

=head2 lines_before

  my $lines = $e->lines_before;
  $e        = $e->lines_before([[4 => 'bar'], [5 => 'baz']]);

Lines before the line where the exception occurred.

=head2 message

  my $msg = $e->message;
  $e      = $e->message('Oops!');

Exception message.

=head2 verbose

  my $bool = $e->verbose;
  $e       = $e->verbose($bool);

Render exception with context.

=head1 METHODS

L<Mojo::Exception> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 new

  my $e = Mojo::Exception->new('Oops!');
  my $e = Mojo::Exception->new('Oops!', $files);

Construct a new L<Mojo::Exception> object.

=head2 throw

  Mojo::Exception->throw('Oops!');
  Mojo::Exception->throw('Oops!', $files);

Throw exception with stacktrace.

=head2 to_string

  my $str = $e->to_string;

Render exception.

=head2 trace

  $e = $e->trace;
  $e = $e->trace(2);

Store stacktrace.

=head1 OPERATORS

L<Mojo::Exception> overloads the following operators.

=head2 bool

  my $bool = !!$e;

Always true.

=head2 stringify

  my $str = "$e";

Alias for L</"to_string">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
