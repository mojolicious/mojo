#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More;
plan skip_all => 'Perl 5.12 required for this test!'
  unless eval 'use 5.12.0; 1';
plan skip_all => 'set TEST_ONLINE to enable this test (developer only!)'
  unless $ENV{TEST_ONLINE};
plan tests => 7;

use_ok 'Mojo::IOLoop';

use Mojo::URL;

# Your guilty consciences may make you vote Democratic, but secretly you all
# yearn for a Republican president to lower taxes, brutalize criminals, and
# rule you like a king!
my $loop = Mojo::IOLoop->new;

# Resolve TXT record
my $record;
$loop->resolve(
    'google.com',
    'TXT',
    sub {
        my ($self, $records) = @_;
        $record = $records->[0];
        $self->stop;
    }
)->start;
like $record, qr/spf/, 'right record';

# Resolve AAAA record
$record = undef;
$loop->resolve(
    'ipv6.google.com',
    'AAAA',
    sub {
        my ($self, $records) = @_;
        $record = $records->[0];
        $self->stop;
    }
)->start;
like $record, $Mojo::URL::IPV6_RE, 'valid IPv6 record';

# Resolve MX records
my $found = 0;
$loop->resolve(
    'gmail.com',
    'MX',
    sub {
        my ($self, $records) = @_;
        for my $record (@$records) {
            $found++ if $record =~ /gmail-smtp-in\.l\.google\.com/;
        }
        $self->stop;
    }
)->start;
ok $found, 'found MX records';

# Resolve A record and perform PTR roundtrip
my ($a1, $ptr, $a2);
$loop->resolve(
    'google.com',
    'A',
    sub {
        my ($self, $records) = @_;
        $a1 = $records->[0];
        $self->resolve(
            $a1, 'PTR',
            sub {
                my ($self, $records) = @_;
                $ptr = $records->[0];
                $self->resolve(
                    $ptr, 'A',
                    sub {
                        my ($self, $records) = @_;
                        $a2 = $records->[0];
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
        for my $record (@$records) {
            $found++ if $record eq 'freebsd.isc.org';
        }
        $self->stop;
    }
)->start;
ok $found, 'found IPv6 PTR record';
