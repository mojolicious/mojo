#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More tests => 49;

# I was God once.
# Yes, I saw. You were doing well until everyone died.
use Mojolicious::Lite;
use Test::Mojo;

# GET /shortpoll
my $shortpoll;
get '/shortpoll' => sub {
    my $self = shift;
    $self->on_finish(sub { $shortpoll = 'finished!' });
    $self->res->code(200);
    $self->res->headers->content_type('text/plain');
    $self->write_chunk('this was short.');
    $self->write_chunk('');
};

# GET /shortpoll/plain
my $shortpoll_plain;
get '/shortpoll/plain' => sub {
    my $self = shift;
    $self->on_finish(sub { $shortpoll_plain = 'finished!' });
    $self->res->code(200);
    $self->res->headers->content_type('text/plain');
    $self->res->headers->content_length(25);
    $self->write('this was short and plain.');
};

# GET /longpoll
my $longpoll;
get '/longpoll' => sub {
    my $self = shift;
    $self->on_finish(sub { $longpoll = 'finished!' });
    $self->res->code(200);
    $self->res->headers->content_type('text/plain');
    $self->write_chunk('hi ');
    $self->client->ioloop->timer(
        '0.5' => sub {
            $self->write_chunk('there,',
                sub { shift->write_chunk(' whats up?'); });
            shift->timer('0.5' => sub { $self->write_chunk('') });
        }
    );
};

# GET /longpoll/nested
my $longpoll_nested;
get '/longpoll/nested' => sub {
    my $self = shift;
    $self->on_finish(sub { $longpoll_nested = 'finished!' });
    $self->res->code(200);
    $self->res->headers->content_type('text/plain');
    $self->write_chunk(
        sub {
            shift->write_chunk('nested!', sub { shift->write_chunk('') });
        }
    );
};

# GET /longpoll/plain
my $longpoll_plain;
get '/longpoll/plain' => sub {
    my $self = shift;
    $self->on_finish(sub { $longpoll_plain = 'finished!' });
    $self->res->code(200);
    $self->res->headers->content_type('text/plain');
    $self->res->headers->content_length(25);
    $self->write('hi ');
    $self->client->ioloop->timer(
        '0.5' => sub {
            $self->write('there plain,', sub { shift->write(' whats up?') });
        }
    );
};

# GET /longpoll/delayed
my $longpoll_delayed;
get '/longpoll/delayed' => sub {
    my $self = shift;
    $self->on_finish(sub { $longpoll_delayed = 'finished!' });
    $self->res->code(200);
    $self->res->headers->content_type('text/plain');
    $self->write_chunk;
    $self->client->ioloop->timer(
        '0.5' => sub {
            $self->write_chunk(
                sub {
                    my $self = shift;
                    $self->write_chunk('how');
                    $self->write_chunk('dy!');
                    $self->write_chunk('');
                }
            );
        }
    );
};

# GET /longpoll/plain/delayed
my $longpoll_plain_delayed;
get '/longpoll/plain/delayed' => sub {
    my $self = shift;
    $self->on_finish(sub { $longpoll_plain_delayed = 'finished!' });
    $self->res->code(200);
    $self->res->headers->content_type('text/plain');
    $self->res->headers->content_length(12);
    $self->write;
    $self->client->ioloop->timer(
        '0.5' => sub {
            $self->write(
                sub {
                    my $self = shift;
                    $self->write('how');
                    $self->write('dy plain!');
                }
            );
        }
    );
};

my $t = Test::Mojo->new;

# GET /shortpoll
$t->get_ok('/shortpoll')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/plain')->content_is('this was short.');
is $shortpoll, 'finished!', 'finished';

# GET /shortpoll/plain
$t->get_ok('/shortpoll/plain')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/plain')->content_is('this was short and plain.');
is $shortpoll_plain, 'finished!', 'finished';

# GET /longpoll
$t->get_ok('/longpoll')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/plain')->content_is('hi there, whats up?');
is $longpoll, 'finished!', 'finished';

# GET /longpoll/nested
$t->get_ok('/longpoll/nested')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/plain')->content_is('nested!');
is $longpoll_nested, 'finished!', 'finished';

# GET /longpoll/plain
$t->get_ok('/longpoll/plain')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/plain')->content_is('hi there plain, whats up?');
is $longpoll_plain, 'finished!', 'finished';

# GET /longpoll/delayed
$t->get_ok('/longpoll/delayed')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/plain')->content_is('howdy!');
is $longpoll_delayed, 'finished!', 'finished';

# GET /longpoll/plain/delayed
$t->get_ok('/longpoll/plain/delayed')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/plain')->content_is('howdy plain!');
is $longpoll_plain_delayed, 'finished!', 'finished';
