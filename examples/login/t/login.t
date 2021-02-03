use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('LoginApp');
$t->ua->max_redirects(1);

$t->get_ok('/')->status_is(200)->element_exists('form input[name="user"]')->element_exists('form input[name="pass"]')
  ->element_exists('form input[type="submit"]');

$t->post_ok('/' => form => {user => 'sebastian', pass => 'secr3t'})->status_is(200)
  ->text_like('html body' => qr/Welcome sebastian/);

$t->get_ok('/protected')->status_is(200)->text_like('a' => qr/Logout/);

$t->get_ok('/logout')->status_is(200)->element_exists('form input[name="user"]')
  ->element_exists('form input[name="pass"]')->element_exists('form input[type="submit"]');

done_testing();
