use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::Mojo;
use Test::More;

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

my $t = Test::Mojo->new('MojoliciousTest');

subtest 'Success callbacks' => sub {
  my $success = '';
  $t->or(sub { $success .= 'one' })
    ->success(1)
    ->or(sub { $success .= 'two' })
    ->success(!1)
    ->or(sub { $success .= shift->app->mode });
  is $success, 'onetesting', 'two callbacks have been executed';
  ok $t->get_ok('/')->success, 'test was successful';
};

subtest 'SyntaxError::foo in testing mode (syntax error in controller)' => sub {
  $t->get_ok('/syntax_error/foo')
    ->status_is(500)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_like(qr/Testing Missing/);
};

subtest 'Foo::syntaxerror in testing mode (syntax error in template)' => sub {
  $t->get_ok('/foo/syntaxerror')
    ->status_is(500)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_like(qr/Testing Missing/);
};

subtest 'Static file /hello.txt in testing mode' => sub {
  $t->get_ok('/hello.txt')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_like(qr/Hello Mojo from a static file!/);
};

subtest 'Foo::bar in testing mode (missing action)' => sub {
  $t->get_ok('/foo/baz')->status_is(500)->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/Testing/);
};

subtest 'Path traversal in testing mode' => sub {
  $t->get_ok('/../../mojolicious/secret.txt')
    ->status_is(404)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_like(qr/Testing not found/);
};

subtest 'Path traversal in testing mode (goes back and forth one directory)' => sub {
  $t->get_ok('/another/../../../mojolicious/secret.txt')
    ->status_is(404)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_like(qr/Testing not found/);
};

subtest 'Path traversal in testing mode (triple dot)' => sub {
  $t->get_ok('/.../mojolicious/secret.txt')
    ->status_is(404)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_like(qr/Testing not found/);
};

subtest 'Path traversal in testing mode (backslashes)' => sub {
  $t->get_ok('/..\\..\\mojolicious\\secret.txt')
    ->status_is(404)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_like(qr/Testing not found/);
};

subtest 'Path traversal in testing mode (escaped backslashes)' => sub {
  $t->get_ok('/..%5C..%5Cmojolicious%5Csecret.txt')
    ->status_is(404)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_like(qr/Testing not found/);
};

subtest 'Backslashes in query or fragment parts in testing mode' => sub {
  $t->get_ok('/hello.txt?one=\\1#two=\\2')->status_is(200)->content_like(qr/Hello Mojo from a static file!/);
};

done_testing();
