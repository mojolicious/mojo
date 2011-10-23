#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 29;

# "Oh, I'm in no condition to drive. Wait a minute.
#  I don't have to listen to myself. I'm drunk."
use Mojo::IOLoop;

use_ok 'Mojo::IOLoop::Resolver';

# Check IPv4 and IPv6 addresses
my $r = Mojo::IOLoop->singleton->resolver;
ok !$r->is_ipv4('mojolicio.us'), 'not an IPv4 address';
ok !$r->is_ipv6('mojolicio.us'), 'not an IPv6 address';
ok !$r->is_ipv4('[::1]'),        'not an IPv4 address';
ok $r->is_ipv6('[::1]'),     'is an IPv6 address';
ok $r->is_ipv4('127.0.0.1'), 'is an IPv4 address';
ok !$r->is_ipv6('127.0.0.1'),    'not an IPv6 address';
ok !$r->is_ipv4('0::127.0.0.1'), 'not an IPv4 address';
ok $r->is_ipv6('0::127.0.0.1'), 'is an IPv6 address';
ok !$r->is_ipv4('[0::127.0.0.1]'), 'not an IPv4 address';
ok $r->is_ipv6('[0::127.0.0.1]'), 'is an IPv6 address';
ok !$r->is_ipv4('foo.1.1.1.1.de'), 'not an IPv4 address';
ok !$r->is_ipv6('foo.1.1.1.1.de'), 'not an IPv4 address';
ok !$r->is_ipv4('1.1.1.1.1.1'),    'not an IPv4 address';
ok !$r->is_ipv6('1.1.1.1.1.1'),    'not an IPv4 address';

# Shared ioloop
my $r2 = Mojo::IOLoop::Resolver->new;
is $r->ioloop, $r2->ioloop, 'same ioloop';

# Shared server pool
$r->servers('8.8.8.8', '1.2.3.4');
is_deeply [$r->servers], ['8.8.8.8', '1.2.3.4'], 'right servers';
is scalar $r->servers, '8.8.8.8', 'right server';
$r2->servers('8.8.8.8', '1.2.3.4');
is_deeply [$r2->servers], ['8.8.8.8', '1.2.3.4'], 'right servers';
is scalar $r2->servers, '8.8.8.8', 'right server';
$r->servers('1.2.3.4');
is_deeply [$r->servers], ['1.2.3.4'], 'right servers';
is scalar $r->servers, '1.2.3.4', 'right server';
is_deeply [$r2->servers], ['1.2.3.4'], 'right servers';
is scalar $r2->servers, '1.2.3.4', 'right server';
$r->servers('1.2.3.4', '4.3.2.1');
is_deeply [$r->servers], ['1.2.3.4', '4.3.2.1'], 'right servers';
is scalar $r->servers, '1.2.3.4', 'right server';
is_deeply [$r2->servers], ['1.2.3.4', '4.3.2.1'], 'right servers';
is scalar $r2->servers, '1.2.3.4', 'right server';

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
