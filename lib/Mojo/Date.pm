# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Date;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

require Time::Local;

__PACKAGE__->attr('epoch');

# Days and months
my @DAYS   = qw/Sun Mon Tue Wed Thu Fri Sat/;
my @MONTHS = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;

# Reverse months
my %MONTHS;
{
    my $i = 0;
    for my $month (@MONTHS) {
        $MONTHS{$month} = $i;
        $i++;
    }
}

sub new {
    my $self = shift->SUPER::new();
    $self->parse(@_);
    return $self;
}

# I suggest you leave immediately.
# Or what? You'll release the dogs or the bees?
# Or the dogs with bees in their mouths and when they bark they shoot bees at
# you?
sub parse {
    my ($self, $date) = @_;

    # Shortcut
    return $self unless defined $date;

    # epoch - 784111777
    if ($date =~ /^\d+$/) {
        $self->epoch($date);
        return $self;
    }

    # Remove spaces, weekdays and timezone
    $date =~ s/^\s+//;
    my $re = join '|', @DAYS;
    $date =~ s/^(?:$re)[a-z]*,?\s*//i;
    $date =~ s/GMT\s*$//i;
    $date =~ s/\s+$//;

    my ($day, $month, $year, $hour, $minute, $second);

    # RFC822/1123 - Sun, 06 Nov 1994 08:49:37 GMT
    if ($date =~ /^(\d+)\s+(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)$/) {
        $day    = $1;
        $month  = $MONTHS{$2};
        $year   = $3;
        $hour   = $4;
        $minute = $5;
        $second = $6;
    }

    # RFC850/1036 - Sunday, 06-Nov-94 08:49:37 GMT
    elsif ($date =~ /^(\d+)-(\w+)-(\d+)\s+(\d+):(\d+):(\d+)$/) {
        $day    = $1;
        $month  = $MONTHS{$2};
        $year   = $3;
        $hour   = $4;
        $minute = $5;
        $second = $6;
    }

    # ANSI C asctime() - Sun Nov  6 08:49:37 1994
    elsif ($date =~ /^(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)$/) {
        $month  = $MONTHS{$1};
        $day    = $2;
        $hour   = $3;
        $minute = $4;
        $second = $5;
        $year   = $6;
    }

    # Invalid format
    else { return $self }

    my $epoch;

    # Prevent crash
    eval {
        $epoch =
          Time::Local::timegm($second, $minute, $hour, $day, $month, $year);
    };

    return $self if $@ || $epoch < 0;

    $self->epoch($epoch);

    return $self;
}

sub to_string {
    my $self  = shift;
    my $epoch = $self->epoch;

    $epoch = time unless defined $epoch;

    my ($second, $minute, $hour, $mday, $month, $year, $wday) = gmtime $epoch;

    # Format
    return sprintf(
        "%s, %02d %s %04d %02d:%02d:%02d GMT",
        $DAYS[$wday], $mday, $MONTHS[$month], $year + 1900,
        $hour, $minute, $second
    );
}

1;
__END__

=head1 NAME

Mojo::Date - Date

=head1 SYNOPSIS

    use Mojo::Date;

    my $date = Mojo::Date->new(784111777);
    my $http_date = $date->to_string;
    $date->parse('Sun, 06 Nov 1994 08:49:37 GMT');
    my $epoch = $date->epoch;

=head1 DESCRIPTION

L<Mojo::Date> implements HTTP date and time functions according to RFC2616.

    Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
    Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
    Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format

=head1 ATTRIBUTES

L<Mojo::Date> implements the following attributes.

=head2 C<epoch>

    my $epoch = $date->epoch;
    $date     = $date->epoch(784111777);

=head1 METHODS

L<Mojo::Date> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $date = Mojo::Date->new;
    my $date = Mojo::Date->new($string);

=head2 C<parse>

    $date = $date->parse('Sun Nov  6 08:49:37 1994');

Parsable formats include:

    - Epoch format (784111777)
    - RFC 822/1123 (Sun, 06 Nov 1994 08:49:37 GMT)
    - RFC 850/1036 (Sunday, 06-Nov-94 08:49:37 GMT)
    - ANSI C asctime() (Sun Nov  6 08:49:37 1994)

=head2 C<to_string>

    my $string = $date->to_string;

=cut
