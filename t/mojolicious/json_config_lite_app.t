use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Cwd 'abs_path';
use File::Basename 'dirname';
use File::Spec::Functions 'catfile';
use Mojolicious::Lite;
use Test::Mojo;

# Default
app->config(it => 'works');
is_deeply app->config, {it => 'works'}, 'right value';

# Invalid config file
my $path = abs_path catfile(dirname(__FILE__), 'public', 'hello.txt');
eval { plugin JSONConfig => {file => $path}; };
like $@, qr/Malformed JSON/, 'right error';

# Load plugins
my $config
  = plugin j_s_o_n_config => {default => {foo => 'baz', hello => 'there'}};
my $log = '';
my $cb = app->log->on(message => sub { $log .= pop });
$path = abs_path catfile(dirname(__FILE__), 'json_config_lite_app_abs.json');
plugin JSONConfig => {file => $path};
like $log, qr/Reading configuration file "\Q$path\E"/, 'right message';
app->log->unsubscribe(message => $cb);
is $config->{foo},          'bar',            'right value';
is $config->{hello},        'there',          'right value';
is $config->{utf},          'утф',         'right value';
is $config->{absolute},     'works too!',     'right value';
is $config->{absolute_dev}, 'dev works too!', 'right value';
is app->config->{foo},          'bar',            'right value';
is app->config->{hello},        'there',          'right value';
is app->config->{utf},          'утф',         'right value';
is app->config->{absolute},     'works too!',     'right value';
is app->config->{absolute_dev}, 'dev works too!', 'right value';
is app->config('foo'),          'bar',            'right value';
is app->config('hello'),        'there',          'right value';
is app->config('utf'),          'утф',         'right value';
is app->config('absolute'),     'works too!',     'right value';
is app->config('absolute_dev'), 'dev works too!', 'right value';
is app->config('it'),           'works',          'right value';

get '/' => 'index';

my $t = Test::Mojo->new;

$t->get_ok('/')->status_is(200)->content_is("barbarbar\n");

# No config file, default only
$config
  = plugin JSONConfig => {file => 'nonexistent', default => {foo => 'qux'}};
is $config->{foo}, 'qux', 'right value';
is app->config->{foo}, 'qux', 'right value';
is app->config('foo'), 'qux',   'right value';
is app->config('it'),  'works', 'right value';

# No config file, no default
{
  ok !(eval { plugin JSONConfig => {file => 'nonexistent'} }),
    'no config file';
  local $ENV{MOJO_CONFIG} = 'nonexistent';
  ok !(eval { plugin 'JSONConfig' }), 'no config file';
}

done_testing();

__DATA__
@@ index.html.ep
<%= $config->{foo} %><%= config->{foo} %><%= config 'foo' %>
