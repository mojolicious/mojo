#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = 1;
  $ENV{MOJO_IOWATCHER}  = 'Mojo::IOWatcher';
}

use Test::More;
plan skip_all => 'set TEST_ONLINE to enable this test (developer only!)'
  unless $ENV{TEST_ONLINE};
plan skip_all => 'Perl 5.12 required for this test!' unless $] >= 5.012;
plan tests => 20;

use_ok 'Mojo::IOLoop';

use List::Util 'first';

# "Your guilty consciences may make you vote Democratic, but secretly you all
#  yearn for a Republican president to lower taxes, brutalize criminals, and
#  rule you like a king!"
my $r = Mojo::IOLoop->singleton->resolver;

# Resolve all record
my %types;
$r->resolve(
  'www.google.com',
  '*',
  sub {
    my ($self, $records) = @_;
    $types{$_->[0]}++ for @$records;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok keys %types > 1, 'multiple record types';

# Lookup
my $result;
$r->lookup(
  'google.com',
  sub {
    my ($self, $address) = @_;
    $result = $address;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $result, 'got an address';

# Lookup with disabled resolver
$result = undef;
my $backup = $ENV{MOJO_NO_RESOLVER};
$ENV{MOJO_NO_RESOLVER} = 1;
$r->lookup(
  'google.com',
  sub {
    my ($self, $address) = @_;
    $result = $address;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$result, 'got no address';
$ENV{MOJO_NO_RESOLVER} = $backup;

# Lookup again
$result = undef;
$r->lookup(
  'google.com',
  sub {
    my ($self, $address) = @_;
    $result = $address;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $result, 'got an address';

# Resolve TXT record
$result = undef;
$r->resolve(
  'google.com',
  'TXT',
  sub {
    my ($self, $records) = @_;
    $result = (first { $_->[0] eq 'TXT' } @$records)->[1];
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
like $result, qr/spf/, 'right record';

# Resolve NS records
my $found = 0;
$r->resolve(
  'gmail.com',
  'NS',
  sub {
    my ($self, $records) = @_;
    $found++ if first { $_->[1] =~ /ns\d*.google\.com/ } @$records;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $found, 'found NS records';

# Resolve AAAA record
$result = undef;
my $ttl;
$r->resolve(
  'ipv6.google.com',
  'AAAA',
  sub {
    my ($self, $records) = @_;
    $result = (first { $_->[0] eq 'AAAA' } @$records)->[1];
    $ttl    = (first { $_->[0] eq 'AAAA' } @$records)->[2];
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $r->is_ipv6($result), 1, 'valid IPv6 record';
ok $ttl, 'got a TTL value';

# Resolve CNAME record
$result = undef;
$r->resolve(
  'ipv6.google.com',
  'CNAME',
  sub {
    my ($self, $records) = @_;
    $result = (first { $_->[0] eq 'CNAME' } @$records)->[1];
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, 'ipv6.l.google.com', 'right CNAME record';

# Resolve MX records
$found = 0;
$r->resolve(
  'gmail.com',
  'MX',
  sub {
    my ($self, $records) = @_;
    $found++
      if first { $_->[1] =~ /gmail-smtp-in\.l\.google\.com/ } @$records;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $found, 'found MX records';

# Resolve A record and perform PTR roundtrip
my ($a1, $ptr, $a2);
$r->resolve(
  'mojolicio.us',
  'A',
  sub {
    my ($self, $records) = @_;
    $a1 = (first { $_->[0] eq 'A' } @$records)->[1];
    $self->resolve(
      $a1, 'PTR',
      sub {
        my ($self, $records) = @_;
        $ptr = $records->[0]->[1];
        $self->resolve(
          $ptr, 'A',
          sub {
            my ($self, $records) = @_;
            $a2 = (first { $_->[0] eq 'A' } @$records)->[1];
            Mojo::IOLoop->stop;
          }
        );
      }
    );
  }
);
Mojo::IOLoop->start;
is $r->is_ipv4($a1), 1, 'valid IPv4 record';
is $a1, $a2, 'PTR roundtrip succeeded';

# Resolve PTR record (IPv6)
$found = 0;
$r->resolve(
  '2001:4f8:0:2:0:0:0:e',
  'PTR',
  sub {
    my ($self, $records) = @_;
    $found++ if first { $_->[1] eq 'freebsd.isc.org' } @$records;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $found, 'found IPv6 PTR record';

# Invalid DNS server
$r = Mojo::IOLoop::Resolver->new;
ok scalar $r->servers, 'got a DNS server';
$r->servers('192.0.2.1', $r->servers);
is $r->servers, '192.0.2.1', 'new invalid DNS server';
$r->lookup('google.com', sub { Mojo::IOLoop->stop });
Mojo::IOLoop->start;
my $fallback = $r->servers;
isnt $fallback, '192.0.2.1', 'valid DNS server';
$result = undef;
$r->lookup(
  'google.com',
  sub {
    my ($self, $address) = @_;
    $result = $address;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $result, 'got an address';
is scalar $r->servers, $fallback, 'still the same DNS server';
isnt $fallback, '192.0.2.1', 'still valid DNS server';
