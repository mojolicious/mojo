use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

BEGIN { plan skip_all => 'Perl 5.20+ required for this test!' if $] < 5.020 }

use ojo;

my $app = a('/' => sub ($c) { $_->render(data => 'signatures work') });
my $tx = $app->ua->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'signatures work', 'right content';

done_testing();
