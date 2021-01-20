use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

# More paths with higher precedence
unshift @{app->renderer->paths}, app->home->child('templates2');
unshift @{app->static->paths},   app->home->child('public2');

get '/twenty_three' => '23';

get '/fourty_two' => '42';

get '/fourty_two_again' => {template => '42', variant => 'test'};

get '/yada' => {template => 'foo/yada'};

my $t = Test::Mojo->new;

subtest '"templates" directory' => sub {
  $t->get_ok('/twenty_three')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is("23\n");
};

subtest '"templates2" directory' => sub {
  $t->get_ok('/fourty_two')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("The answer is 42.\n");
};

subtest '"templates2" directory (variant)' => sub {
  $t->get_ok('/fourty_two_again')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("The answer is 43!\n");
};

subtest '"public2" directory' => sub {
  $t->get_ok('/hello.txt')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("Also higher precedence!\n");
};

subtest '"public" directory' => sub {
  $t->get_ok('/hello2.txt')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is("X");
};

subtest '"public2" directory' => sub {
  $t->get_ok('/hello3.txt')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("Hello Mojo from... ALL GLORY TO THE HYPNOTOAD!\n");
};

subtest '"templates2" directory' => sub {
  $t->get_ok('/yada')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is("Higher precedence!\n");
};

done_testing();
