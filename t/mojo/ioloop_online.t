#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More;
plan skip_all => 'Perl 5.12 required for this test!'
  unless eval 'use 5.012000; 1';
plan skip_all => 'set TEST_ONLINE to enable this test (developer only!)'
  unless $ENV{TEST_ONLINE};
plan tests => 10;

use_ok 'Mojo::IOLoop';

use List::Util 'first';
use Mojo::URL;

# "Your guilty consciences may make you vote Democratic, but secretly you all
#  yearn for a Republican president to lower taxes, brutalize criminals, and
#  rule you like a king!"
my $loop = Mojo::IOLoop->new;

# Resolve all record
my %types;
$loop->resolve(
    'www.google.com',
    '*',
    sub {
        my ($self, $records) = @_;
        $types{$_->[0]}++ for @$records;
        $self->stop;
    }
)->start;
ok keys %types > 1, 'multiple record types';

# Resolve TXT record
my $result;
$loop->resolve(
    'google.com',
    'TXT',
    sub {
        my ($self, $records) = @_;
        $result = (first { $_->[0] eq 'TXT' } @$records)->[1];
        $self->stop;
    }
)->start;
like $result, qr/spf/, 'right record';

# Resolve NS records
my $found = 0;
$loop->resolve(
    'gmail.com',
    'NS',
    sub {
        my ($self, $records) = @_;
        $found++ if first { $_->[1] =~ /ns\d*.google\.com/ } @$records;
        $self->stop;
    }
)->start;
ok $found, 'found NS records';

# Resolve AAAA record
$result = undef;
$loop->resolve(
    'ipv6.google.com',
    'AAAA',
    sub {
        my ($self, $records) = @_;
        $result = (first { $_->[0] eq 'AAAA' } @$records)->[1];
        $self->stop;
    }
)->start;
like $result, $Mojo::URL::IPV6_RE, 'valid IPv6 record';

# Resolve CNAME record
$result = undef;
$loop->resolve(
    'ipv6.google.com',
    'CNAME',
    sub {
        my ($self, $records) = @_;
        $result = (first { $_->[0] eq 'CNAME' } @$records)->[1];
        $self->stop;
    }
)->start;
is $result, 'ipv6.l.google.com', 'right CNAME record';

# Resolve MX records
$found = 0;
$loop->resolve(
    'gmail.com',
    'MX',
    sub {
        my ($self, $records) = @_;
        $found++
          if first { $_->[1] =~ /gmail-smtp-in\.l\.google\.com/ } @$records;
        $self->stop;
    }
)->start;
ok $found, 'found MX records';

# Resolve A record and perform PTR roundtrip
my ($a1, $ptr, $a2);
$loop->resolve(
    'perl.org',
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
                        $self->stop;
                    }
                );
            }
        );
    }
)->start;
like $a1, $Mojo::URL::IPV4_RE, 'valid IPv4 record';
is $a1, $a2, 'PTR roundtrip succeeded';

# Resolve PTR record (IPv6)
$found = 0;
$loop->resolve(
    '2001:4f8:0:2:0:0:0:e',
    'PTR',
    sub {
        my ($self, $records) = @_;
        $found++ if first { $_->[1] eq 'freebsd.isc.org' } @$records;
        $self->stop;
    }
)->start;
ok $found, 'found IPv6 PTR record';
