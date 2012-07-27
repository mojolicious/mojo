package Mojo::Date;
use Mojo::Base -base;
use overload
  'bool'   => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

use Time::Local 'timegm';

has 'epoch';

# Days and months
my @DAYS   = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MONTHS = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my %MONTHS;
@MONTHS{@MONTHS} = (0 .. 11);

sub new { shift->SUPER::new->parse(@_) }

# "I suggest you leave immediately.
#  Or what? You'll release the dogs or the bees?
#  Or the dogs with bees in their mouths and when they bark they shoot bees
#  at you?"
sub parse {
  my ($self, $date) = @_;

  # Invalid
  return $self unless defined $date;

  # epoch (784111777)
  return $self->epoch($date) if $date =~ /^\d+$/;

  # RFC 822/1123 (Sun, 06 Nov 1994 08:49:37 GMT)
  my ($day, $month, $year, $h, $m, $s);
  if ($date =~ /^\w+\,\s+(\d+)\s+(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+GMT$/) {
    ($day, $month, $year, $h, $m, $s) = ($1, $MONTHS{$2}, $3, $4, $5, $6);
  }

  # RFC 850/1036 (Sunday, 06-Nov-94 08:49:37 GMT)
  elsif ($date =~ /^\w+\,\s+(\d+)-(\w+)-(\d+)\s+(\d+):(\d+):(\d+)\s+GMT$/) {
    ($day, $month, $year, $h, $m, $s) = ($1, $MONTHS{$2}, $3, $4, $5, $6);
  }

  # ANSI C asctime() (Sun Nov  6 08:49:37 1994)
  elsif ($date =~ /^\w+\s+(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)$/) {
    ($month, $day, $h, $m, $s, $year) = ($MONTHS{$1}, $2, $3, $4, $5, $6);
  }

  # Invalid
  else { return $self }

  # Prevent crash
  my $epoch;
  $epoch = eval { timegm($s, $m, $h, $day, $month, $year) };
  $self->epoch($epoch) if !$@ && $epoch >= 0;

  return $self;
}

sub to_string {
  my $self = shift;

  # RFC 2616 (Sun, 06 Nov 1994 08:49:37 GMT)
  my ($s, $m, $h, $mday, $month, $year, $wday) = gmtime($self->epoch // time);
  return sprintf "%s, %02d %s %04d %02d:%02d:%02d GMT", $DAYS[$wday], $mday,
    $MONTHS[$month], $year + 1900, $h, $m, $s;
}

1;

=head1 NAME

Mojo::Date - HTTP date

=head1 SYNOPSIS

  use Mojo::Date;

  my $date = Mojo::Date->new(784111777);
  my $http_date = $date->to_string;
  $date->parse('Sun, 06 Nov 1994 08:49:37 GMT');
  my $epoch = $date->epoch;

=head1 DESCRIPTION

L<Mojo::Date> implements HTTP date and time functions as described in RFC
2616.

  Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
  Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
  Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format

=head1 ATTRIBUTES

L<Mojo::Date> implements the following attributes.

=head2 C<epoch>

  my $epoch = $date->epoch;
  $date     = $date->epoch(784111777);

Epoch seconds.

=head1 METHODS

L<Mojo::Date> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $date = Mojo::Date->new;
  my $date = Mojo::Date->new($string);

Construct a new L<Mojo::Date> object.

=head2 C<parse>

  $date = $date->parse('Sun Nov  6 08:49:37 1994');

Parse date in one of the following formats.

  - Epoch format (784111777)
  - RFC 822/1123 (Sun, 06 Nov 1994 08:49:37 GMT)
  - RFC 850/1036 (Sunday, 06-Nov-94 08:49:37 GMT)
  - ANSI C asctime() (Sun Nov  6 08:49:37 1994)

=head2 C<to_string>

  my $string = $date->to_string;
  my $string = "$date";

Render date suitable for HTTP messages.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
