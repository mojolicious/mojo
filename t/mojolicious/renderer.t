use Mojo::Base -strict;

use Test::More tests => 8;

# "Actually, she wasn't really my girlfriend,
#  she just lived nextdoor and never closed her curtains."
use Mojolicious;
use Mojolicious::Controller;
use Mojolicious::Renderer;
use Mojolicious::Static;

# Template class
my $backup = $ENV{MOJO_TEMPLATE_CLASS} || '';
$ENV{MOJO_TEMPLATE_CLASS} = 'Foo';
is(Mojolicious::Renderer->new->default_template_class, 'Foo', 'right value');
$ENV{MOJO_TEMPLATE_CLASS} = $backup;

# Static class
$backup = $ENV{MOJO_STATIC_CLASS} || '';
$ENV{MOJO_STATIC_CLASS} = 'Bar';
is(Mojolicious::Static->new->default_static_class, 'Bar', 'right value');
$ENV{MOJO_STATIC_CLASS} = $backup;

# Fresh controller
my $c = Mojolicious::Controller->new;
is $c->render(text => 'works', partial => 1), 'works', 'renderer is working';

# Controller with application
$c = Mojolicious::Controller->new(app => Mojolicious->new);
$c->app->log->path(undef);
$c->app->log->level('fatal');
my $r = Mojolicious::Renderer->new(default_format => 'debug');
$r->add_handler(
  debug => sub {
    my ($self, $c, $output) = @_;
    $$output .= 'Hello Mojo!';
  }
);
$c->stash->{format} = 'something';

# Normal rendering
$c->stash->{template} = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!', 'text/plain'], 'normal rendering';

# Normal rendering with layout
$c->stash->{template} = 'something';
$c->stash->{layout}   = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!Hello Mojo!', 'text/plain'],
  'normal rendering with layout';
is delete $c->stash->{layout}, 'something';

# Rendering a path with dots
$c->stash->{template} = 'some.path.with.dots/template';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!', 'text/plain'],
  'rendering a path with dots';

# Unrecognized handler
$c->stash->{handler} = 'not_defined';
is $r->render($c), undef, 'return undef for unrecognized handler';
