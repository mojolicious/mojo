
use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}
use Mojolicious::Lite;

get('/' => sub { shift->render(text => '<b>wrong</b>') });

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new();
isa_ok($t, 'Test::Mojo', 'right class');
can_ok($t, qw/tx ua dom/);
$t->dom(Mojo::DOM->new('<b>right</b>'));
$t->text_is('b', 'right', 'dom can be set');
$t->get_ok('/')->text_is('b', 'wrong', 'dom reset on request');

done_testing;
