#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 16;

# "Oh, I'm in no condition to drive. Wait a minute.
#  I don't have to listen to myself. I'm drunk."
use_ok 'Mojo::IOLoop';

my $r = Mojo::IOLoop->singleton->resolver;

# Check IPv4 and IPv6 addresses
is $r->is_ipv4('mojolicio.us'),   undef, 'not an IPv4 address';
is $r->is_ipv6('mojolicio.us'),   undef, 'not an IPv6 address';
is $r->is_ipv4('[::1]'),          undef, 'not an IPv4 address';
is $r->is_ipv6('[::1]'),          1,     'is an IPv6 address';
is $r->is_ipv4('127.0.0.1'),      1,     'is an IPv4 address';
is $r->is_ipv6('127.0.0.1'),      undef, 'not an IPv6 address';
is $r->is_ipv4('0::127.0.0.1'),   undef, 'not an IPv4 address';
is $r->is_ipv6('0::127.0.0.1'),   1,     'is an IPv6 address';
is $r->is_ipv4('[0::127.0.0.1]'), undef, 'not an IPv4 address';
is $r->is_ipv6('[0::127.0.0.1]'), 1,     'is an IPv6 address';
is $r->is_ipv4('foo.1.1.1.1.de'), undef, 'not an IPv4 address';
is $r->is_ipv6('foo.1.1.1.1.de'), undef, 'not an IPv4 address';
is $r->is_ipv4('1.1.1.1.1.1'),    undef, 'not an IPv4 address';
is $r->is_ipv6('1.1.1.1.1.1'),    undef, 'not an IPv4 address';

# Lookup "localhost" (pass through)
my $result;
$r->lookup(
  'localhost',
  sub {
    my ($self, $address) = @_;
    $result = $address;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, '127.0.0.1', 'got an address';
