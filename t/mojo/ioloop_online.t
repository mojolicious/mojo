#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Mojo::URL;
use Test::More;
plan skip_all => 'set TEST_ONLINE to enable this test (developer only!)'
  unless $ENV{TEST_ONLINE};
plan tests => 6;

use_ok 'Mojo::IOLoop';

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

# Resolve A record and than resolve PTR
my ($a_record, $ptr_record, $a2_record);
$loop->resolve(
    'google.com',
    'A',
    sub {
        my ($self, $records) = @_;
        $a_record = $records->[0];
        $self->resolve(
            $a_record,
            'PTR',
            sub {
                my ($self, $records) = @_;
                $ptr_record = $records->[0];
                $self->resolve(
                    $ptr_record,
                    'A',
                    sub {
                        my ($self, $records) = @_;
                        $a2_record = $records->[0];
                        $self->stop;
                    }
                );
            }
        );
    }
)->start;
like $a_record, $Mojo::URL::IPV4_RE, 'A record right';
is $a_record,   $a2_record,          'ipv4 PTR record right';

# IPv6 test (ipv6tools.org)
$found = 0;
$loop->resolve(
    '2001:470:b825:0:0:0:0:1',
    'PTR',
    sub {
        my ($self, $records) = @_;
        for my $record (@$records) {
            $found++ if $record eq 'ipv6tools.org';
        }
        $self->stop;
    }
)->start;
ok $found, 'found ipv6 PTR records';
