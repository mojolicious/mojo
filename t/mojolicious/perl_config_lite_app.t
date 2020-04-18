use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::Mojo;
use Test::More;
use Mojo::File qw(curfile);
use Mojolicious::Lite;

plugin 'Config';
is_deeply app->config, {
		foo => "bar",
		utf => "утф",
		file => curfile->sibling('perl_config_lite_app.conf')->to_string,
		line => 7,
	}, 'right value';

done_testing();
