use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojo::File qw(curfile);
use Mojolicious::Lite;

plugin 'Config';
is_deeply app->config,
  {
  foo  => "bar",
  utf  => "утф",
  file => curfile->sibling('perl_config_lite_app.conf')->to_abs->to_string,
  line => 7,
  },
  'right value';

done_testing();
