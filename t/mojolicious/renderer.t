use Mojo::Base -strict;

use Test::More;
use Mojo::Util qw(decode gunzip);
use Mojolicious;

# Partial rendering
my $app = Mojolicious->new(secrets => ['works']);
my $c   = $app->build_controller;
$c->app->log->level('trace')->unsubscribe('message');
is $c->render_to_string(text => 'works'), 'works', 'renderer is working';

# Normal rendering with default format
my $renderer = $c->app->renderer->default_format('test');
$renderer->add_handler(
  debug => sub {
    my ($renderer, $c, $output) = @_;
    my $content = $c->content // '';
    $$output = "Hello Mojo!$content";
  }
);
$c->stash->{template} = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$renderer->render($c)], ['Hello Mojo!', 'test'], 'normal rendering';

# Normal rendering with custom format
$c->stash->{format}   = 'something';
$c->stash->{template} = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$renderer->render($c)], ['Hello Mojo!', 'something'], 'normal rendering';

# Normal rendering with layout
delete $c->stash->{format};
$c->stash->{template} = 'something';
$c->stash->{layout}   = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$renderer->render($c)], ['Hello Mojo!Hello Mojo!', 'test'], 'normal rendering with layout';

# Rendering a path with dots
$c->stash->{template} = 'some.path.with.dots/template';
$c->stash->{handler}  = 'debug';
is_deeply [$renderer->render($c)], ['Hello Mojo!', 'test'], 'rendering a path with dots';

# Unrecognized handler
my $logs = $c->app->log->capture('trace');
$c->stash->{handler} = 'not_defined';
is $renderer->render($c), undef, 'return undef for unrecognized handler';
like $logs, qr/No handler for "not_defined" found/, 'right message';
undef $logs;

# Default template name
$c->stash(controller => 'foo', action => 'bar');
is $c->app->renderer->template_for($c), 'foo/bar', 'right template name';

# Big cookie
$logs = $c->app->log->capture('trace');
$c->cookie(foo => 'x' x 4097);
like $logs, qr/Cookie "foo" is bigger than 4KiB/, 'right message';
undef $logs;

# Nested helpers
my $first = $app->build_controller;
$first->helpers->app->log->level('fatal');
$first->app->helper('myapp.multi_level.test' => sub {'works!'});
ok $first->app->renderer->get_helper('myapp'),                  'found helper';
ok $first->app->renderer->get_helper('myapp.multi_level'),      'found helper';
ok $first->app->renderer->get_helper('myapp.multi_level.test'), 'found helper';
is $first->myapp->multi_level->test,          'works!', 'right result';
is $first->helpers->myapp->multi_level->test, 'works!', 'right result';
$first->app->helper('myapp.defaults' => sub { shift->app->defaults(@_) });
ok $first->app->renderer->get_helper('myapp.defaults'), 'found helper';
is $first->app->renderer->get_helper('myap.'), undef, 'no helper';
is $first->app->renderer->get_helper('yapp'),  undef, 'no helper';
$first->myapp->defaults(foo => 'bar');
is $first->myapp->defaults('foo'),          'bar', 'right result';
is $first->helpers->myapp->defaults('foo'), 'bar', 'right result';
is $first->app->myapp->defaults('foo'),     'bar', 'right result';
my $app2   = Mojolicious->new(secrets => ['works']);
my $second = $app2->build_controller;
$second->app->log->level('fatal');
is $second->app->renderer->get_helper('myapp'),          undef, 'no helper';
is $second->app->renderer->get_helper('myapp.defaults'), undef, 'no helper';
$second->app->helper('myapp.defaults' => sub {'nothing'});
my $myapp = $first->myapp;
is $first->myapp->defaults('foo'),           'bar',     'right result';
is $second->myapp->defaults('foo'),          'nothing', 'right result';
is $second->helpers->myapp->defaults('foo'), 'nothing', 'right result';
is $first->myapp->defaults('foo'),           'bar',     'right result';
is $first->helpers->myapp->defaults('foo'),  'bar',     'right result';

# Reuse proxy objects
my $helpers = $first->helpers;
is $helpers->myapp->multi_level->test, $helpers->myapp->multi_level->test, 'same result';

# Compression (enabled)
my $output = 'a' x 1000;
$c = $app->build_controller;
$c->req->headers->accept_encoding('gzip');
$renderer->respond($c, $output, 'html');
is $c->res->headers->content_type,     'text/html;charset=UTF-8', 'right "Content-Type" value';
is $c->res->headers->vary,             'Accept-Encoding',         'right "Vary" value';
is $c->res->headers->content_encoding, 'gzip',                    'right "Content-Encoding" value';
isnt $c->res->body,                    $output,                   'different string';
is gunzip($c->res->body),              $output,                   'same string';

# Compression (disabled)
$renderer->compress(0);
$c = $app->build_controller;
$c->req->headers->accept_encoding('gzip');
$renderer->respond($c, $output, 'html');
is $c->res->headers->content_type, 'text/html;charset=UTF-8', 'right "Content-Type" value';
ok !$c->res->headers->vary,             'no "Vary" value';
ok !$c->res->headers->content_encoding, 'no "Content-Encoding" value';
is $c->res->body, $output, 'same string';
$renderer->compress(1);

# Compression (not requested)
$c = $app->build_controller;
$renderer->respond($c, $output, 'html');
is $c->res->code,                  200,                       'right status';
is $c->res->headers->content_type, 'text/html;charset=UTF-8', 'right "Content-Type" value';
is $c->res->headers->vary,         'Accept-Encoding',         'right "Vary" value';
ok !$c->res->headers->content_encoding, 'no "Content-Encoding" value';
is $c->res->body, $output, 'same string';

# Compression (other transfer encoding)
$c = $app->build_controller;
$c->res->headers->content_encoding('whatever');
$renderer->respond($c, $output, 'html', 500);
is $c->res->code,                      500,                       'right status';
is $c->res->headers->content_type,     'text/html;charset=UTF-8', 'right "Content-Type" value';
is $c->res->headers->vary,             'Accept-Encoding',         'right "Vary" value';
is $c->res->headers->content_encoding, 'whatever',                'right "Content-Encoding" value';
is $c->res->body,                      $output,                   'same string';

# Compression (below minimum length)
$output = 'a' x 850;
$c      = $app->build_controller;
$c->req->headers->accept_encoding('gzip');
$renderer->respond($c, $output, 'html');
is $c->res->headers->content_type, 'text/html;charset=UTF-8', 'right "Content-Type" value';
ok !$c->res->headers->vary,             'no "Vary" value';
ok !$c->res->headers->content_encoding, 'no "Content-Encoding" value';
is $c->res->body, $output, 'same string';

subtest 'Response has already been rendered' => sub {
  my $c = $app->build_controller;
  $c->render(text => 'First call');
  is $c->render_to_string(text => 'Unrelated call'), 'Unrelated call', 'right result';
  eval { $c->render(text => 'Second call') };
  like $@, qr/A response has already been rendered/, 'right error';
};

# Missing method (AUTOLOAD)
my $class = ref $first->myapp;
eval { $first->myapp->missing };
like $@, qr/^Can't locate object method "missing" via package "$class"/, 'right error';
eval { $first->app->myapp->missing };
like $@, qr/^Can't locate object method "missing" via package "$class"/, 'right error';

# No leaky namespaces
my $helper_class = ref $second->myapp;
is ref $second->myapp, $helper_class, 'same class';
ok $helper_class->can('defaults'), 'helpers are active';
my $template_class = decode 'UTF-8', $second->render_to_string(inline => "<%= __PACKAGE__ =%>");
is decode('UTF-8', $second->render_to_string(inline => "<%= __PACKAGE__ =%>")), $template_class, 'same class';
ok $template_class->can('stash'), 'helpers are active';
undef $app2;
ok !$helper_class->can('defaults'), 'helpers have been cleaned up';
ok !$template_class->can('stash'),  'helpers have been cleaned up';

done_testing();
