#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';
use Test::More;
use Encode;
use Mojolicious::Lite;
use Test::Mojo;
use utf8;

my $yatta = 'やった';
my $yatta_sjis = encode(shift_jis => $yatta);

plugin('i18n', { charset => 'Shift_JIS' });

# Silence
app->log->level('error');

get  '/' => 'index';

post '/' => sub {
    my $self = shift;
    $self->render_text("foo: ".$self->param('foo'));
};

my $t = Test::Mojo->new;

# It's always ok to post ascii
$t->post_form_ok('/', { foo => 'yatta' })
  ->status_is(200)
  ->content_is('foo: yatta');

# Send raw Shift_JIS octets (as browsers do)
$t->post_form_ok('/', { foo => $yatta_sjis })
  ->status_is(200)
  ->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

# You can send it as a string, too
$t->post_form_ok('/', 'shift_jis', { foo => $yatta })
  ->status_is(200)
  ->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

# Templates in DATA section should be written in utf-8,
# and the ones in files, in Shift_JIS.
# (Mojo will decode them for you)
$t->get_ok('/')
  ->status_is(200)
  ->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

done_testing;

__DATA__
@@ index.html.ep
<p>やった</p>
