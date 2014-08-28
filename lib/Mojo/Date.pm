package Mojo::Date;
use Mojo::Base -base;
use overload bool => sub {1}, '""' => sub { shift->to_string }, fallback => 1;

use Time::Local 1.2 'timegm';

has epoch => sub {time};

my $RFC3339_RE = qr/
  ^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+(?:\.\d+)?)   # Date and time
  (?:Z|([+-])(\d+):(\d+))?$                        # Offset
/xi;

my @DAYS   = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MONTHS = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my %MONTHS;
@MONTHS{@MONTHS} = (0 .. 11);

sub new { @_ > 1 ? shift->SUPER::new->parse(@_) : shift->SUPER::new }

sub parse {
  my ($self, $date) = @_;

  # epoch (784111777)
  return $self->epoch($date) if $date =~ /^\d+$|^\d+\.\d+$/;

  # RFC 822/1123 (Sun, 06 Nov 1994 08:49:37 GMT)
  my $offset = 0;
  my ($day, $month, $year, $h, $m, $s);
  if ($date =~ /^\w+\,\s+(\d+)\s+(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+GMT$/) {
    ($day, $month, $year, $h, $m, $s) = ($1, $MONTHS{$2}, $3, $4, $5, $6);
  }

  # RFC 3339 (1994-11-06T08:49:37Z)
  elsif ($date =~ $RFC3339_RE) {
    ($year, $month, $day, $h, $m, $s) = ($1, $2 - 1, $3, $4, $5, $6);
    $offset = (($8 * 3600) + ($9 * 60)) * ($7 eq '+' ? -1 : 1) if $7;
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
  else { return $self->epoch(undef) }

  # Prevent crash
  my $epoch = eval { timegm $s, $m, $h, $day, $month, $year };
  return $self->epoch(
    (defined $epoch && ($epoch += $offset) >= 0) ? $epoch : undef);
}

sub to_datetime {

  # RFC 3339 (1994-11-06T08:49:37Z)
  my ($s, $m, $h, $day, $month, $year) = gmtime(my $epoch = shift->epoch);
  my $str = sprintf '%04d-%02d-%02dT%02d:%02d:%02d', $year + 1900, $month + 1,
    $day, $h, $m, $s;
  return $str . ($epoch =~ /(\.\d+)$/ ? "$1Z" : 'Z');
}

sub to_string {

  # RFC 7231 (Sun, 06 Nov 1994 08:49:37 GMT)
  my ($s, $m, $h, $mday, $month, $year, $wday) = gmtime shift->epoch;
  return sprintf '%s, %02d %s %04d %02d:%02d:%02d GMT', $DAYS[$wday], $mday,
    $MONTHS[$month], $year + 1900, $h, $m, $s;
}

sub to_words {
  my $self = shift;

  my $s = (shift // time) - $self->epoch;
  $s = $s * -1 if my $in = $s < 0;
  return _wrap($in, 'less than a minute') if $s < 45;
  return _wrap($in, 'about a minute')     if $s < 90;

  my $m = int($s / 60);
  return _wrap($in, "$m minutes")    if $m < 45;
  return _wrap($in, 'about an hour') if $m < 90;

  my $h = int($m / 60);
  return _wrap($in, "$h hours") if $h < 24;
  return _wrap($in, 'a day')    if $h < 42;

  my $days = int($h / 24);
  return _wrap($in, "$days days")                  if $days < 30;
  return _wrap($in, 'about a month')               if $days < 45;
  return _wrap($in, "@{[int($days / 30)]} months") if $days < 365;

  my $years = $days / 365;
  return _wrap($in, 'about a year') if $years < 1.5;
  return _wrap($in, "@{[int $years]} years");
}

sub _wrap { $_[0] ? "in $_[1]" : "$_[1] ago" }

1;

=encoding utf8

=head1 NAME

Mojo::Date - HTTP date

=head1 SYNOPSIS

  use Mojo::Date;

  # Parse
  my $date = Mojo::Date->new('Sun, 06 Nov 1994 08:49:37 GMT');
  say $date->epoch;

  # Build
  my $date = Mojo::Date->new(time + 60);
  say "$date";

=head1 DESCRIPTION

L<Mojo::Date> implements HTTP date and time functions based on
L<RFC 7230|http://tools.ietf.org/html/rfc7230>,
L<RFC 7231|http://tools.ietf.org/html/rfc7231> and
L<RFC 3339|http://tools.ietf.org/html/rfc3339>.

=head1 ATTRIBUTES

L<Mojo::Date> implements the following attributes.

=head2 epoch

  my $epoch = $date->epoch;
  $date     = $date->epoch(784111777);

Epoch seconds, defaults to the current time.

=head1 METHODS

L<Mojo::Date> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 new

  my $date = Mojo::Date->new;
  my $date = Mojo::Date->new('Sun Nov  6 08:49:37 1994');

Construct a new L<Mojo::Date> object and L</"parse"> date if necessary.

=head2 parse

  $date = $date->parse('Sun Nov  6 08:49:37 1994');

Parse date.

  # Epoch
  say Mojo::Date->new('784111777')->epoch;
  say Mojo::Date->new('784111777.21')->epoch;

  # RFC 822/1123
  say Mojo::Date->new('Sun, 06 Nov 1994 08:49:37 GMT')->epoch;

  # RFC 850/1036
  say Mojo::Date->new('Sunday, 06-Nov-94 08:49:37 GMT')->epoch;

  # Ansi C asctime()
  say Mojo::Date->new('Sun Nov  6 08:49:37 1994')->epoch;

  # RFC 3339
  say Mojo::Date->new('1994-11-06T08:49:37Z')->epoch;
  say Mojo::Date->new('1994-11-06T08:49:37')->epoch;
  say Mojo::Date->new('1994-11-06T08:49:37.21Z')->epoch;
  say Mojo::Date->new('1994-11-06T08:49:37+01:00')->epoch;
  say Mojo::Date->new('1994-11-06T08:49:37-01:00')->epoch;

=head2 to_datetime

  my $str = $date->to_datetime;

Render L<RFC 3339|http://tools.ietf.org/html/rfc3339> date and time.

  # "1994-11-06T08:49:37Z"
  Mojo::Date->new(784111777)->to_datetime;

  # "1994-11-06T08:49:37.21Z"
  Mojo::Date->new(784111777.21)->to_datetime;

=head2 to_string

  my $str = $date->to_string;

Render date suitable for HTTP messages.

  # "Sun, 06 Nov 1994 08:49:37 GMT"
  Mojo::Date->new(784111777)->to_string;

=head2 to_words

  my $str = $date->to_words;
  my $str = $date->to_words(784111777);

Report the approximate distance of time from now or a specific point in time.

  # "less than a minute ago"
  Mojo::Date->new(time - 1)->to_words;

  # "in about a minute"
  Mojo::Date->new(time + 50)->to_words;

  # "5 minutes ago"
  Mojo::Date->new(time - 300)->to_words;

  # "about an hour ago"
  Mojo::Date->new(time - 3600)->to_words;

  # "in 3 hours"
  Mojo::Date->new(time + 10800)->to_words;

  # "a day ago"
  Mojo::Date->new(time - 86400)->to_words;

  # "4 days ago"
  Mojo::Date->new(time - 345600)->to_words;

  # "about a month ago"
  Mojo::Date->new(time - 2592000)->to_words;

  # "5 months ago"
  Mojo::Date->new(time - 12960000)->to_words;

  # "about a year ago"
  Mojo::Date->new(time - 33696000)->to_words;

  # "in 3 years"
  Mojo::Date->new(time + 101088000)->to_words;

=head1 OPERATORS

L<Mojo::Date> overloads the following operators.

=head2 bool

  my $bool = !!$date;

Always true.

=head2 stringify

  my $str = "$date";

Alias for L</to_string>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
