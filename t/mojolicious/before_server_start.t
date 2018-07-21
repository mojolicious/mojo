use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;

my $starts;
sub reset_starts { $starts = 0; }

hook before_server_start => sub { ++$starts; };

# ho hum
get '/' => {text => "works"};

my $t = Test::Mojo->new;

reset_starts();
$t->get_ok('/')->status_is(200)->content_is('works');
is($starts, 1, 'get_ok bss count');

{
  open my $stdout, '>', \my $out;
  local *STDOUT = $stdout;

  reset_starts();
  app->commands->run(qw(get /));
  is($out,    'works', 'correct output');
  is($starts, 1,       'get command bss count');
}

reset_starts();
is(app->commands->run(qw(eval 1)), 1, 'eval output');
is($starts,                        0, 'eval command bss count');

done_testing();
