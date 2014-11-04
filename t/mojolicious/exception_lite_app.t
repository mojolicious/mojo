use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

# No real templates
app->renderer->paths->[0] = app->home->rel_dir('does_not_exist');

# Logger
app->log->handle(undef);
app->log->level($ENV{MOJO_LOG_LEVEL} = 'debug');
my $log = '';
app->log->on(message => sub { shift; $log .= join ':', @_ });

helper dead_helper => sub { die "dead helper!\n" };

# Custom rendering for missing "txt" template
hook before_render => sub {
  my ($c, $args) = @_;
  return unless ($args->{template} // '') eq 'not_found';
  my $exception = $c->stash('snapshot')->{exception};
  $args->{text} = "Missing template, $exception." if $args->{format} eq 'txt';
};

# Custom exception rendering for "txt"
hook before_render => sub {
  my ($c, $args) = @_;
  @$args{qw(text format)} = ($c->stash('exception'), 'txt')
    if ($args->{template} // '') eq 'exception' && $c->accepts('txt');
};

get '/logger' => sub {
  my $c     = shift;
  my $level = $c->param('level');
  my $msg   = $c->param('message');
  $c->app->log->log($level => $msg);
  $c->render(text => "$level: $msg");
};

get '/dead_template';

get '/dead_included_template';

get '/dead_template_with_layout';

get '/dead_action' => sub { die "dead action!\n" };

get '/double_dead_action_☃' => sub {
  eval { die 'double dead action!' };
  die $@;
};

get '/trapped' => sub {
  my $c = shift;
  eval { die {foo => 'bar'} };
  $c->render(text => $@->{foo} || 'failed');
};

get '/missing_template' => {exception => 'whatever'};

get '/missing_template/too' => sub {
  my $c = shift;
  $c->render('does_not_exist') or $c->res->headers->header('X-Not-Found' => 1);
};

get '/missing_helper' => sub { shift->missing_helper };

# Dummy exception object
package MyException;
use Mojo::Base -base;
use overload '""' => sub { shift->error }, fallback => 1;

has 'error';

package main;

get '/trapped/too' => sub {
  my $c = shift;
  eval { die MyException->new(error => 'works') };
  $c->render(text => "$@" || 'failed');
};

# Reuse exception and snapshot
my ($exception, $snapshot);
hook after_dispatch => sub {
  my $c = shift;
  return unless $c->req->url->path->contains('/reuse/exception');
  $exception = $c->stash('exception');
  $snapshot  = $c->stash('snapshot');
};

# Custom exception handling
hook around_dispatch => sub {
  my ($next, $c) = @_;
  unless (eval { $next->(); 1 }) {
    die $@ unless $@ eq "CUSTOM\n";
    $c->render(text => 'Custom handling works!');
  }
};

get '/reuse/exception' => {foo => 'bar'} =>
  sub { die "Reusable exception.\n" };

get '/custom' => sub { die "CUSTOM\n" };

get '/dead_helper';

my $t = Test::Mojo->new;

# Debug
$t->get_ok('/logger?level=debug&message=one')->status_is(200)
  ->content_is('debug: one');
like $log, qr/debug:one/, 'right result';

# Info
$t->get_ok('/logger?level=info&message=two')->status_is(200)
  ->content_is('info: two');
like $log, qr/info:two/, 'right result';

# Warn
$t->get_ok('/logger?level=warn&message=three')->status_is(200)
  ->content_is('warn: three');
like $log, qr/warn:three/, 'right result';

# Error
$t->get_ok('/logger?level=error&message=four')->status_is(200)
  ->content_is('error: four');
like $log, qr/error:four/, 'right result';

# Fatal
$t->get_ok('/logger?level=fatal&message=five')->status_is(200)
  ->content_is('fatal: five');
like $log, qr/fatal:five/, 'right result';

# "not_found.development.html.ep" route suggestion
$t->get_ok('/does_not_exist')->status_is(404)
  ->content_like(qr!/does_not_exist!);

# "not_found.development.html.ep" route suggestion
$t->post_ok('/does_not_exist')->status_is(404)
  ->content_like(qr!/does_not_exist!);

# Dead template
$t->get_ok('/dead_template')->status_is(500)->content_like(qr/dead template!/)
  ->content_like(qr/line 1/);
like $log, qr/dead template!/, 'right result';

# Dead included template
$t->get_ok('/dead_included_template')->status_is(500)
  ->content_like(qr/dead template!/)->content_like(qr/line 1/);

# Dead template with layout
$t->get_ok('/dead_template_with_layout')->status_is(500)
  ->content_like(qr/dead template with layout!/)->content_like(qr/line 2/);
like $log, qr/dead template with layout!/, 'right result';

# Dead action
$t->get_ok('/dead_action')->status_is(500)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_like(qr!get &#39;/dead_action&#39;!)
  ->content_like(qr/dead action!/)->text_is('#error' => "dead action!\n");
like $log, qr/dead action!/, 'right result';

# Dead action with different format
$t->get_ok('/dead_action.xml')->status_is(500)
  ->content_type_is('application/xml')->content_is("<very>bad</very>\n");

# Dead action with unsupported format
$t->get_ok('/dead_action.json')->status_is(500)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_like(qr!get &#39;/dead_action&#39;!)
  ->content_like(qr/dead action!/);

# Dead action with custom exception rendering
$t->get_ok('/dead_action' => {Accept => 'text/plain'})->status_is(500)
  ->content_type_is('text/plain;charset=UTF-8')->content_is("dead action!\n");

# Action dies twice
$t->get_ok('/double_dead_action_☃')->status_is(500)
  ->content_like(qr!get &#39;/double_dead_action_☃&#39;.*lite_app\.t:\d!s)
  ->content_like(qr/double dead action!/);

# Trapped exception
$t->get_ok('/trapped')->status_is(200)->content_is('bar');

# Another trapped exception
$t->get_ok('/trapped/too')->status_is(200)->content_is('works');

# Custom exception handling
$t->get_ok('/custom')->status_is(200)->content_is('Custom handling works!');

# Exception in helper
$t->get_ok('/dead_helper')->status_is(500)->content_like(qr/dead helper!/);

# Missing template
$t->get_ok('/missing_template')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_like(qr/Page not found/);

# Missing template with different format
$t->get_ok('/missing_template.xml')->status_is(404)
  ->content_type_is('application/xml')
  ->content_is("<somewhat>bad</somewhat>\n");

# Missing template with unsupported format
$t->get_ok('/missing_template.json')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_like(qr/Page not found/);

# Missing template with custom rendering
$t->get_ok('/missing_template.txt')->status_is(404)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_is('Missing template, whatever.');

# Missing template (failed rendering)
$t->get_ok('/missing_template/too')->status_is(404)
  ->header_is('X-Not-Found' => 1)->content_type_is('text/html;charset=UTF-8')
  ->content_like(qr/Page not found/);

# Missing helper (correct context)
$t->get_ok('/missing_helper')->status_is(500)
  ->content_type_is('text/html;charset=UTF-8')->content_like(qr/Server error/)
  ->content_like(qr/shift-&gt;missing_helper/);

# Reuse exception
ok !$exception, 'no exception';
ok !$snapshot,  'no snapshot';
$t->get_ok('/reuse/exception')->status_is(500)
  ->content_like(qr/Reusable exception/);
isa_ok $exception, 'Mojo::Exception',      'right exception class';
like $exception,   qr/Reusable exception/, 'right exception';
is $snapshot->{foo}, 'bar', 'right snapshot value';
ok !$snapshot->{exception}, 'no exception in snapshot';

# Bundled static files
$t->get_ok('/mojo/jquery/jquery.js')->status_is(200)
  ->content_type_is('application/javascript');
$t->get_ok('/mojo/prettify/prettify.js')->status_is(200)
  ->content_type_is('application/javascript');
$t->get_ok('/mojo/prettify/prettify-mojo-dark.css')->status_is(200)
  ->content_type_is('text/css');
$t->get_ok('/mojo/prettify/prettify-mojo-light.css')->status_is(200)
  ->content_type_is('text/css');
$t->get_ok('/mojo/failraptor.png')->status_is(200)
  ->content_type_is('image/png');
$t->get_ok('/mojo/logo-black.png')->status_is(200)
  ->content_type_is('image/png');
$t->get_ok('/mojo/logo-white.png')->status_is(200)
  ->content_type_is('image/png');
$t->get_ok('/mojo/noraptor.png')->status_is(200)->content_type_is('image/png');
$t->get_ok('/mojo/notfound.png')->status_is(200)->content_type_is('image/png');
$t->get_ok('/mojo/pinstripe-dark.png')->status_is(200)
  ->content_type_is('image/png');
$t->get_ok('/mojo/pinstripe-light.png')->status_is(200)
  ->content_type_is('image/png');
$t->get_ok('/mojo/stripes.png')->status_is(200)->content_type_is('image/png');

done_testing();

__DATA__
@@ layouts/green.html.ep
%= content

@@ dead_template.html.ep
% die 'dead template!';

@@ dead_included_template.html.ep
this
%= include 'dead_template'
works!

@@ dead_template_with_layout.html.ep
% layout 'green';
% die 'dead template with layout!';

@@ exception.xml.ep
<very>bad</very>

@@ not_found.development.xml.ep
<somewhat>bad</somewhat>

@@ dead_helper.html.ep
% dead_helper;
