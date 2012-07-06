use Mojo::Base -strict;

use Test::More tests => 7;

# "Actually, she wasn't really my girlfriend,
#  she just lived nextdoor and never closed her curtains."
use Mojolicious;
use Mojolicious::Controller;
use Mojolicious::Renderer;

# Fresh controller
my $c = Mojolicious::Controller->new;
is $c->render(text => 'works', partial => 1), 'works', 'renderer is working';

# Controller with application
$c = Mojolicious::Controller->new(app => Mojolicious->new);
$c->app->log->path(undef);
$c->app->log->level('fatal');
$c->app->types->type(debug => 'text/debug');
my $r = Mojolicious::Renderer->new(default_format => 'debug');
$r->add_handler(
  debug => sub {
    my ($self, $c, $output) = @_;
    $$output .= 'Hello Mojo!';
  }
);

# Normal rendering with custom format
$c->stash->{template} = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!', 'text/debug'], 'normal rendering';

# Normal rendering with custom format
$c->stash->{format}   = 'something';
$c->stash->{template} = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!', 'text/plain'], 'normal rendering';

# Normal rendering with layout
delete $c->stash->{format};
$c->stash->{template} = 'something';
$c->stash->{layout}   = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!Hello Mojo!', 'text/debug'],
  'normal rendering with layout';
is delete $c->stash->{layout}, 'something';

# Rendering a path with dots
$c->stash->{template} = 'some.path.with.dots/template';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!', 'text/debug'],
  'rendering a path with dots';

# Unrecognized handler
$c->stash->{handler} = 'not_defined';
is $r->render($c), undef, 'return undef for unrecognized handler';
