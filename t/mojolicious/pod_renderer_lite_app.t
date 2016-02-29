use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

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

post '/block';

get '/art';

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
  ->content_like(qr!<pre><code>\{\n  foo\(\);\n\}</code></pre>!)
  ->content_like(qr!<p><code>test</code></p>!)->content_like(qr/Gray/);

# Mixed indentation
$t->get_ok('/art')->status_is(200)->text_like('h2[id="art"]' => qr/art/)
  ->text_like('pre code' => qr/\s{2}#\n#\s{3}#\n\s{2}#/);

# Empty
$t->get_ok('/empty')->status_is(200)->content_is('');

# Headings
$t->get_ok('/perldoc/MojoliciousTest/PODTest')->status_is(200)
  ->element_exists('h1#One')->element_exists('h2#Two')
  ->element_exists('h3#Three')->element_exists('h4#Four')
  ->element_exists('a[href=#One]')->element_exists('a[href=#Two]')
  ->element_exists('a[href=#Three]')->element_exists('a[href=#Four]')
  ->text_like('pre code', qr/\$foo/);

# Trailing slash
$t->get_ok('/perldoc/MojoliciousTest/PODTest/')->element_exists('#mojobar')
  ->text_like('title', qr/PODTest/);

# Format
$t->get_ok('/perldoc/MojoliciousTest/PODTest.html')->element_exists('#mojobar')
  ->text_like('title', qr/PODTest/);

# Format (source)
$t->get_ok('/perldoc/MojoliciousTest/PODTest' => {Accept => 'text/plain'})
  ->status_is(200)->content_type_is('text/plain;charset=UTF-8')
  ->content_like(qr/package MojoliciousTest::PODTest/);

# Negotiated source
$t->get_ok('/perldoc/MojoliciousTest/PODTest' => {Accept => 'text/plain'})
  ->status_is(200)->content_type_is('text/plain;charset=UTF-8')
  ->content_like(qr/package MojoliciousTest::PODTest/);

# Perldoc browser (unsupported format)
$t->get_ok('/perldoc/MojoliciousTest/PODTest.json')->status_is(204);

# Welcome
$t->get_ok('/perldoc')->status_is(200)->element_exists('#mojobar')
  ->text_like('title', qr/The Mojolicious Guide to the Galaxy/);

done_testing();

__DATA__

@@ layouts/gray.html.ep
Gray <%= content %>

@@ index.html.ep
test123<%= pod_to_html "=head1 A\n\n=head1 B\n\nC<test>"%>

@@ block.html.ep
test321<%= pod_to_html begin %>=head2 lalala

  {
    foo();
  }

C<test><% end %>

@@ art.html.ep
<%= pod_to_html begin %>=head2 art

    #
  #   #
    #

<% end %>
