use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

# POD renderer plugin
plugin('PODRenderer')->name('perldoc');
ok app->routes->find('perldoc'), 'route found';

# Default layout
app->defaults(layout => 'gray');

get '/' => sub {
  my $c = shift;
  $c->render('simple', handler => 'pod');
};

post '/' => 'index';

post '/block' => 'block';

get '/empty' => {inline => '', handler => 'pod'};

my $t = Test::Mojo->new;

# Simple POD template
$t->get_ok('/')->status_is(200)
  ->content_like(qr!<h1 id="Test123">Test123</h1>!)
  ->content_like(qr|<p>It <code>works</code>!</p>|);

# POD helper
$t->post_ok('/')->status_is(200)->content_like(qr!test123<h1 id="A">A</h1>!)
  ->content_like(qr!<h1 id="B">B</h1>!)
  ->content_like(qr!\s+<p><code>test</code></p>!)->content_like(qr/Gray/);

# POD filter
$t->post_ok('/block')->status_is(200)
  ->content_like(qr!test321<h2 id="lalala">lalala</h2>!)
  ->content_like(qr!<p><code>test</code></p>!)->content_like(qr/Gray/);

# Empty
$t->get_ok('/empty')->status_is(200)->content_is('');

# Perldoc browser (Welcome)
$t->get_ok('/perldoc')->status_is(200)
  ->text_is('a[id="TUTORIAL"]', 'TUTORIAL')
  ->text_is('a[id="GUIDES"]',   'GUIDES')
  ->content_like(qr/Mojolicious guide to the galaxy/);

# Perldoc browser (Welcome with slash)
$t->get_ok('/perldoc/')->status_is(200)
  ->text_is('a[id="TUTORIAL"]', 'TUTORIAL')
  ->text_is('a[id="GUIDES"]',   'GUIDES')
  ->content_like(qr/Mojolicious guide to the galaxy/)
  ->content_unlike(qr/Pirates/);

# Perldoc browser (Mojo documentation)
$t->get_ok('/perldoc/Mojo')->status_is(200)
  ->text_is('h1 a[id="SYNOPSIS"]', 'SYNOPSIS')
  ->text_is('a[id="handler"]',     'handler')
  ->text_like('p', qr/Duct tape for the HTML5 web!/);

# Perldoc browser (Mojo documentation with format)
$t->get_ok('/perldoc/Mojo.html')->status_is(200)
  ->text_is('h1 a[id="SYNOPSIS"]', 'SYNOPSIS')
  ->text_is('a[id="handler"]',     'handler')
  ->text_like('p', qr/Duct tape for the HTML5 web!/);

# Perldoc browser (negotiated Mojo documentation)
$t->get_ok('/perldoc/Mojo' => {Accept => 'text/html'})->status_is(200)
  ->text_is('h1 a[id="SYNOPSIS"]', 'SYNOPSIS')
  ->text_is('a[id="handler"]',     'handler')
  ->text_like('p', qr/Duct tape for the HTML5 web!/);

# Perldoc browser (Mojo source with format)
$t->get_ok('/perldoc/Mojo.txt')->status_is(200)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_like(qr/package Mojo;/);

# Perldoc browser (negotiated Mojolicious source again)
$t->get_ok('/perldoc/Mojolicious' => {Accept => 'text/plain'})->status_is(200)
  ->content_type_is('text/plain;charset=UTF-8')->content_like(qr/\$VERSION/);

# Perldoc browser (unsupported format)
$t->get_ok('/perldoc/Mojolicious.json')->status_is(204);

done_testing();

__DATA__

@@ layouts/gray.html.ep
Gray <%= content %>

@@ index.html.ep
test123<%= pod_to_html "=head1 A\n\n=head1 B\n\nC<test>"%>

@@ block.html.ep
test321<%= pod_to_html begin %>=head2 lalala

C<test><% end %>
