#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More;
plan skip_all => 'set TEST_ONLINE to enable this test (developer only!)'
  unless $ENV{TEST_ONLINE};
plan tests => 3;

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
