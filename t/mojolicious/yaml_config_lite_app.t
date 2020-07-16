use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::Mojo;
use Test::More;
use Mojo::File qw(curfile);
use Mojolicious::Lite;

subtest 'Default' => sub {
  app->config(it => 'works');
  is_deeply app->config, {it => 'works'}, 'right value';
};

subtest 'Invalid config file' => sub {
  eval { plugin NotYAMLConfig => {file => 'public/hello.txt'} };
  like $@, qr/Can't parse config/, 'right error';
};

subtest 'Load plugins' => sub {
  my $config = plugin NotYAMLConfig => {default => {foo => 'baz', hello => 'there'}};
  my $path   = curfile->sibling('yaml_config_lite_app_abs.yaml');
  plugin NotYAMLConfig => {file => $path};
  is $config->{foo},          'barbaz',                                'right value';
  is $config->{hello},        'there',                                 'right value';
  is $config->{utf},          'утф',                                   'right value';
  is $config->{absolute},     'works too!!!',                          'right value';
  is $config->{absolute_dev}, 'dev works too yaml_config_lite_app!!!', 'right value';
  is app->config->{foo},          'barbaz',                                'right value';
  is app->config->{hello},        'there',                                 'right value';
  is app->config->{utf},          'утф',                                   'right value';
  is app->config->{absolute},     'works too!!!',                          'right value';
  is app->config->{absolute_dev}, 'dev works too yaml_config_lite_app!!!', 'right value';
  is app->config('foo'),          'barbaz',                                'right value';
  is app->config('hello'),        'there',                                 'right value';
  is app->config('utf'),          'утф',                                   'right value';
  is app->config('absolute'),     'works too!!!',                          'right value';
  is app->config('absolute_dev'), 'dev works too yaml_config_lite_app!!!', 'right value';
  is app->config('it'),           'works',                                 'right value';
};

get '/' => 'index';

my $t = Test::Mojo->new;

$t->get_ok('/')->status_is(200)->content_is("barbazbarbaz\n");

subtest 'No config file, default only' => sub {
  my $config = plugin NotYAMLConfig => {file => 'nonexistent', default => {foo => 'qux'}};
  is $config->{foo}, 'qux', 'right value';
  is app->config->{foo}, 'qux', 'right value';
  is app->config('foo'), 'qux',   'right value';
  is app->config('it'),  'works', 'right value';
};

subtest 'No config file, no default' => sub {
  ok !(eval { plugin NotYAMLConfig => {file => 'nonexistent'} }), 'no config file';
  local $ENV{MOJO_CONFIG} = 'nonexistent';
  ok !(eval { plugin 'NotYAMLConfig' }), 'no config file';
};

subtest 'YAML::XS' => sub {
  plan skip_all => 'YAML::XS required!' unless eval "use YAML::XS; 1";
  my $config
    = plugin NotYAMLConfig => {module => 'YAML::XS', ext => 'yml', default => {foo => 'baz', hello => 'there'}};
  is $config->{foo},   'yada',  'right value';
  is $config->{hello}, 'there', 'right value';
  is $config->{utf8},  'утф',   'right value';
  is app->config->{foo},   'yada',  'right value';
  is app->config->{hello}, 'there', 'right value';
  is app->config->{utf8},  'утф',   'right value';
};

done_testing();

__DATA__
@@ index.html.ep
<%= config->{foo} %><%= config 'foo' %>
