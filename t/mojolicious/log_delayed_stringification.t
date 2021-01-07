use strict;
use warnings;

use Test::Mojo;
use Test::More;

{
    package Mojolicious::Test::Log; # an app that dies
    use Mojolicious::Lite;

    get '/error' => sub { die "Log Me" };
}

local $ENV{MOJO_LOG_LEVEL} = 'info';
my $t   = Test::Mojo->new('Mojolicious::Test::Log');
my $app = $t->app;

my $logged_an_error = 0;
# simpler case of real-world use in Mojolicious::Plugin::Log::Any
$app->log->unsubscribe('message')->on(message => sub {
    my ($log, $level, @lines) = @_;
    if ($level eq 'error') {
        $logged_an_error = 1;
        isa_ok($lines[0], 'Mojo::Exception') or diag explain $lines[0];
    }
});

# this succeeds, but the isa_ok above fails
$t->get_ok('/error')
  ->status_is(500 => 'threw exception');

# sanity check
ok $logged_an_error, "ran error testing above";

done_testing();
