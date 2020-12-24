use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

# No real templates
app->renderer->paths->[0] = app->home->child('does_not_exist');

# Logger
app->log->handle(undef);
app->log->level($ENV{MOJO_LOG_LEVEL} = 'debug');
my $log = '';
app->log->on(message => sub { shift; $log .= join ':', @_ });

helper dead_helper => sub { die "dead helper!\n" };

app->renderer->add_handler(dead => sub { die "dead handler!\n" });

# Custom rendering for missing "txt" template
hook before_render => sub {
  my ($c, $args) = @_;
  return unless ($args->{template} // '') eq 'not_found';
  my $stash     = $c->stash;
  my $exception = $stash->{snapshot}{exception};
  $args->{text} = "Missing template, $exception." if $args->{format} eq 'txt';
};

# Custom exception rendering for "txt"
hook before_render => sub {
  my ($c, $args) = @_;
  return unless ($args->{template} // '') eq 'exception';
  return unless $c->accepts('', 'txt');
  @$args{qw(text format)} = ($c->stash->{exception}, 'txt');
};

get '/logger' => sub {
  my $c     = shift;
  my $level = $c->param('level');
  my $msg   = $c->param('message');
  $c->app->log->$level($msg);
  $c->render(text => "$level: $msg");
};

get '/custom_exception' => sub { die Mojo::Base->new };

get '/dead_template';

get '/dead_template_too';

get '/dead_handler' => {handler => 'dead'};

get '/dead_action_epl' => {handler => 'epl'} => sub {
  die "dead action epl!\n";
};

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
    die $@ unless $@ =~ /^CUSTOM\n/;
    $c->render(text => 'Custom handling works!');
  }
};

get '/reuse/exception' => {foo => 'bar'} => sub { die "Reusable exception.\n" };

get '/custom' => sub { die "CUSTOM\n" };

get '/dead_helper';

my $t = Test::Mojo->new;

subtest 'Missing error' => sub {
  my $c = $t->app->build_controller;
  $c->reply->exception(undef);
  like $c->res->body, qr/Exception!/, 'right result';

  $c = $t->app->build_controller;
  $c->reply->exception;
  like $c->res->body, qr/Exception!/, 'right result';

  $c = $t->app->build_controller;
  $c->reply->exception(Mojo::Exception->new);
  like $c->res->body, qr/Exception!/, 'right result';
};

subtest Debug => sub {
  $t->get_ok('/logger?level=debug&message=one')->status_is(200)->content_is('debug: one');
  like $log, qr/debug:one/, 'right result';
};

subtest Info => sub {
  $t->get_ok('/logger?level=info&message=two')->status_is(200)->content_is('info: two');
  like $log, qr/info:two/, 'right result';
};

subtest Warn => sub {
  $t->get_ok('/logger?level=warn&message=three')->status_is(200)->content_is('warn: three');
  like $log, qr/warn:three/, 'right result';
};

subtest Error => sub {
  $t->get_ok('/logger?level=error&message=four')->status_is(200)->content_is('error: four');
  like $log, qr/error:four/, 'right result';
};

subtest Fatal => sub {
  $t->get_ok('/logger?level=fatal&message=five')->status_is(200)->content_is('fatal: five');
  like $log, qr/fatal:five/, 'right result';
};

subtest '"debug.html.ep" route suggestion' => sub {
  $t->get_ok('/does_not_exist')->status_is(404)->element_exists('nav')->content_like(qr!/does_not_exist!);
};

subtest '"debug.html.ep" route suggestion' => sub {
  $t->post_ok('/does_not_exist')->status_is(404)->content_like(qr!/does_not_exist!);
};

subtest 'Custom exception' => sub {
  $t->get_ok('/custom_exception')->status_is(500)->content_like(qr/Mojo::Base/);
};

subtest 'Dead template' => sub {
  $t->get_ok('/dead_template')->status_is(500)->content_like(qr/dead template!/)->content_like(qr/line 1/);
  like $log, qr/dead template!/, 'right result';
};

subtest 'Dead template with a different handler' => sub {
  $t->get_ok('/dead_template_too.xml')->status_is(500)->content_is("<very>bad</very>\n");
  like $log, qr/dead template too!/, 'right result';
};

subtest 'Dead handler' => sub {
  $t->get_ok('/dead_handler.xml')->status_is(500)->content_is("<very>bad</very>\n");
  like $log, qr/dead handler!/, 'right result';
};

subtest 'Dead action (with a different handler)' => sub {
  $t->get_ok('/dead_action_epl.xml')->status_is(500)->content_is("<very>bad</very>\n");
  like $log, qr/dead action epl!/, 'right result';
};

subtest 'Dead included template' => sub {
  $t->get_ok('/dead_included_template')->status_is(500)->content_like(qr/dead template!/)->content_like(qr/line 1/);
};

subtest 'Dead template with layout' => sub {
  $t->get_ok('/dead_template_with_layout')->status_is(500)->content_like(qr/dead template with layout!/)
    ->content_like(qr/line 2/)->content_unlike(qr/Green/);
  like $log, qr/dead template with layout!/, 'right result';
};

subtest 'Dead action' => sub {
  $t->get_ok('/dead_action')->status_is(500)->content_type_is('text/html;charset=UTF-8')
    ->content_like(qr!get &#39;/dead_action&#39;!)->content_like(qr/dead action!/)
    ->text_is('#error' => "dead action!\n");
  like $log, qr/dead action!/, 'right result';
};

subtest 'Dead action with different format' => sub {
  $t->get_ok('/dead_action.xml')->status_is(500)->content_type_is('application/xml')->content_is("<very>bad</very>\n");
};

subtest 'Dead action with unsupported format' => sub {
  $t->get_ok('/dead_action.json')->status_is(500)->content_type_is('text/html;charset=UTF-8')
    ->content_like(qr!get &#39;/dead_action&#39;!)->content_like(qr/dead action!/);
};

subtest 'Dead action with custom exception rendering' => sub {
  $t->get_ok('/dead_action' => {Accept => 'text/plain'})->status_is(500)->content_type_is('text/plain;charset=UTF-8')
    ->content_like(qr/^dead action!\n/);
};

subtest 'Action dies twice' => sub {
  $t->get_ok('/double_dead_action_☃')->status_is(500)->content_like(qr!get &#39;/double_dead_action_☃&#39;!)
    ->content_like(qr/File.+lite_app\.t\", line \d/)->content_like(qr/double dead action!/);
};

subtest 'Trapped exception' => sub {
  $t->get_ok('/trapped')->status_is(200)->content_is('bar');
};

subtest 'Another trapped exception' => sub {
  $t->get_ok('/trapped/too')->status_is(200)->content_is('works');
};

subtest 'Custom exception handling' => sub {
  $t->get_ok('/custom')->status_is(200)->content_is('Custom handling works!');
};

subtest 'Exception in helper' => sub {
  $t->get_ok('/dead_helper')->status_is(500)->content_like(qr/dead helper!/);
};

subtest 'Missing template' => sub {
  $t->get_ok('/missing_template')->status_is(404)->content_type_is('text/html;charset=UTF-8')
    ->content_like(qr/Page not found/);
};

subtest 'Missing template with different format' => sub {
  $t->get_ok('/missing_template.xml')->status_is(404)->content_type_is('application/xml')
    ->content_is("<somewhat>bad</somewhat>\n");
};

subtest 'Missing template with unsupported format' => sub {
  $t->get_ok('/missing_template.json')->status_is(404)->content_type_is('text/html;charset=UTF-8')
    ->content_like(qr/Page not found/);
};

subtest 'Missing template with custom rendering' => sub {
  $t->get_ok('/missing_template.txt')->status_is(404)->content_type_is('text/plain;charset=UTF-8')
    ->content_is('Missing template, whatever.');
};

subtest 'Missing template (failed rendering)' => sub {
  $t->get_ok('/missing_template/too')->status_is(404)->header_is('X-Not-Found' => 1)
    ->content_type_is('text/html;charset=UTF-8')->content_like(qr/Page not found/);
};

subtest 'Missing helper (correct context)' => sub {
  $t->get_ok('/missing_helper')->status_is(500)->content_type_is('text/html;charset=UTF-8')
    ->content_like(qr/Server error/)->content_like(qr/shift-&gt;missing_helper/);
};

subtest 'Reuse exception' => sub {
  ok !$exception, 'no exception';
  ok !$snapshot,  'no snapshot';
  $t->get_ok('/reuse/exception')->status_is(500)->content_like(qr/Reusable exception/);
  isa_ok $exception, 'Mojo::Exception',      'right exception';
  like $exception,   qr/Reusable exception/, 'right message';
  is $snapshot->{foo}, 'bar', 'right snapshot value';
  ok !$snapshot->{exception}, 'no exception in snapshot';
};

subtest 'Bundled static files' => sub {
  $t->get_ok('/mojo/jquery/jquery.js')->status_is(200)->content_type_is('application/javascript');

  $t->get_ok('/mojo/highlight.js/highlight.min.js')->status_is(200)->content_type_is('application/javascript');
  $t->get_ok('/mojo/highlight.js/mojolicious.min.js')->status_is(200)->content_type_is('application/javascript');
  $t->get_ok('/mojo/highlight.js/highlight-mojo-dark.css')->status_is(200)->content_type_is('text/css');

  $t->get_ok('/mojo/bootstrap/bootstrap.js')->status_is(200)->content_type_is('application/javascript');
  $t->get_ok('/mojo/bootstrap/bootstrap.css')->status_is(200)->content_type_is('text/css');

  $t->get_ok('/mojo/fontawesome/fontawesome.css')->status_is(200)->content_type_is('text/css');

  $t->get_ok('/mojo/failraptor.png')->status_is(200)->content_type_is('image/png');
  $t->get_ok('/mojo/logo.png')->status_is(200)->content_type_is('image/png');
  $t->get_ok('/mojo/logo-white.png')->status_is(200)->content_type_is('image/png');
  $t->get_ok('/mojo/logo-white-2x.png')->status_is(200)->content_type_is('image/png');
  $t->get_ok('/mojo/noraptor.png')->status_is(200)->content_type_is('image/png');
  $t->get_ok('/mojo/notfound.png')->status_is(200)->content_type_is('image/png');
  $t->get_ok('/mojo/pinstripe-dark.png')->status_is(200)->content_type_is('image/png');
  $t->get_ok('/mojo/pinstripe-light.png')->status_is(200)->content_type_is('image/png');
};

done_testing();

__DATA__
@@ layouts/green.html.ep
Green<%= content %>

@@ dead_template.html.ep
% die 'dead template!';

@@ dead_template_too.xml.epl
% die 'dead template too!';

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
