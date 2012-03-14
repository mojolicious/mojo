use Mojo::Base -strict;

use utf8;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER}  = 'Mojo::IOWatcher';
  $ENV{MOJO_MODE}       = 'development';
}

use Test::More tests => 83;

# "This calls for a party, baby.
#  I'm ordering 100 kegs, 100 hookers and 100 Elvis impersonators that aren't
#  above a little hooking should the occasion arise."
use Mojolicious::Lite;
use Test::Mojo;

app->renderer->paths->[0] = app->home->rel_dir('does_not_exist');

# Logger
app->log->handle(undef);
app->log->level($ENV{MOJO_LOG_LEVEL} = 'debug');
my $log = '';
app->log->on(message => sub { shift; $log .= join ':', @_ });

# GET /logger
get '/logger' => sub {
  my $self    = shift;
  my $level   = $self->param('level');
  my $message = $self->param('message');
  $self->app->log->log($level => $message);
  $self->render(text => "$level: $message");
};

# GET /dead_template
get '/dead_template';

# GET /dead_included_template
get '/dead_included_template';

# GET /dead_template_with_layout
get '/dead_template_with_layout';

# GET /dead_action
get '/dead_action' => sub { die 'dead action!' };

# GET /double_dead_action_☃
get '/double_dead_action_☃' => sub {
  eval { die 'double dead action!' };
  die $@;
};

# GET /trapped
get '/trapped' => sub {
  my $self = shift;
  eval { die {foo => 'bar'} };
  $self->render_text($@->{foo} || 'failed');
};

# GET /missing_template
get '/missing_template';

# Dummy exception object
package MyException;
use Mojo::Base -base;
use overload '""' => sub { shift->error }, fallback => 1;

has 'error';

package main;

# GET /trapped/too
get '/trapped/too' => sub {
  my $self = shift;
  eval { die MyException->new(error => 'works') };
  $self->render_text("$@" || 'failed');
};

# Reuse exception
my $exception;
hook after_dispatch => sub {
  my $self = shift;
  return unless $self->req->url->path->contains('/reuse/exception');
  $exception = $self->stash('exception');
};

# Custom exception handling
hook around_dispatch => sub {
  my ($next, $self) = @_;
  unless (eval { $next->(); 1 }) {
    die $@ unless $@ eq "CUSTOM\n";
    $self->render(text => 'Custom handling works!');
  }
};

# GET /reuse/exception
get '/reuse/exception' => sub { die "Reusable exception.\n" };

# GET /custom
get '/custom' => sub { die "CUSTOM\n" };

my $t = Test::Mojo->new;

# GET /logger (debug)
$t->get_ok('/logger?level=debug&message=one')->status_is(200)
  ->content_is('debug: one');
like $log, qr/debug:one/, 'right result';

# GET /logger (info)
$t->get_ok('/logger?level=info&message=two')->status_is(200)
  ->content_is('info: two');
like $log, qr/info:two/, 'right result';

# GET /logger (warn)
$t->get_ok('/logger?level=warn&message=three')->status_is(200)
  ->content_is('warn: three');
like $log, qr/warn:three/, 'right result';

# GET /logger (error)
$t->get_ok('/logger?level=error&message=four')->status_is(200)
  ->content_is('error: four');
like $log, qr/error:four/, 'right result';

# GET /logger (fatal)
$t->get_ok('/logger?level=fatal&message=five')->status_is(200)
  ->content_is('fatal: five');
like $log, qr/fatal:five/, 'right result';

# GET /does_not_exist ("not_found.development.html.ep" route suggestion)
$t->get_ok('/does_not_exist')->status_is(404)
  ->content_like(qr#/does_not_exist#);

# POST /does_not_exist ("not_found.development.html.ep" route suggestion)
$t->post_ok('/does_not_exist')->status_is(404)
  ->content_like(qr#/does_not_exist#);

# GET /dead_template
$t->get_ok('/dead_template')->status_is(500)->content_like(qr/1\./)
  ->content_like(qr/dead template!/);

# GET /dead_included_template
$t->get_ok('/dead_included_template')->status_is(500)->content_like(qr/1\./)
  ->content_like(qr/dead template!/);

# GET /dead_template_with_layout
$t->get_ok('/dead_template_with_layout')->status_is(500)
  ->content_like(qr/2\./)->content_like(qr/dead template with layout!/);

# GET /dead_action
$t->get_ok('/dead_action')->status_is(500)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_like(qr|get &#39;/dead_action&#39;|)
  ->content_like(qr/dead action!/);

# GET /dead_action.xml (different format)
$t->get_ok('/dead_action.xml')->status_is(500)->content_type_is('text/xml')
  ->content_is("<very>bad</very>\n");

# GET /dead_action.json (unsupported format)
$t->get_ok('/dead_action.json')->status_is(500)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_like(qr|get &#39;/dead_action&#39;|)
  ->content_like(qr/dead action!/);

# GET /double_dead_action_☃
$t->get_ok('/double_dead_action_☃')->status_is(500)
  ->content_like(qr|get &#39;/double_dead_action_☃&#39;.*lite_app\.t\:\d|s)
  ->content_like(qr/double dead action!/);

# GET /trapped
$t->get_ok('/trapped')->status_is(200)->content_is('bar');

# GET /trapped/too
$t->get_ok('/trapped/too')->status_is(200)->content_is('works');

# GET /custom
$t->get_ok('/custom')->status_is(200)->content_is('Custom handling works!');

# GET /missing_template
$t->get_ok('/missing_template')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_like(qr/Page not found/);

# GET /missing_template.xml (different format)
$t->get_ok('/missing_template.xml')->status_is(404)
  ->content_type_is('text/xml')->content_is("<somewhat>bad</somewhat>\n");

# GET /missing_template.json (unsupported format)
$t->get_ok('/missing_template.json')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_like(qr/Page not found/);

# GET /reuse/exception
ok !$exception, 'no exception';
$t->get_ok('/reuse/exception')->status_is(500)
  ->content_like(qr/Reusable exception/);
isa_ok $exception, 'Mojo::Exception',      'right exception class';
like $exception,   qr/Reusable exception/, 'right exception';

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
