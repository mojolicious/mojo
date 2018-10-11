use Mojo::Base -strict;

use Test::More;
use Mojolicious;
use Mojolicious::Types;

# Basic functionality
my $t = Mojolicious::Types->new;
is $t->type('json'), 'application/json;charset=UTF-8', 'right type';
is $t->type('foo'), undef, 'no type';
$t->type(foo => 'foo/bar');
is $t->type('foo'), 'foo/bar', 'right type';
$t->type(BAR => 'bar/baz');
is $t->type('Bar'), 'bar/baz', 'right type';

# Detect common MIME types
is_deeply $t->detect('text/cache-manifest'),      ['appcache'], 'right formats';
is_deeply $t->detect('application/atom+xml'),     ['atom'],     'right formats';
is_deeply $t->detect('application/octet-stream'), ['bin'],      'right formats';
is_deeply $t->detect('text/css'),                 ['css'],      'right formats';
is_deeply $t->detect('image/gif'),                ['gif'],      'right formats';
is_deeply $t->detect('application/x-gzip'),       ['gz'],       'right formats';
is_deeply $t->detect('text/html'), ['htm', 'html'], 'right formats';
is_deeply $t->detect('image/x-icon'), ['ico'], 'right formats';
is_deeply $t->detect('image/jpeg'), ['jpeg', 'jpg'], 'right formats';
is_deeply $t->detect('application/javascript'), ['js'],    'right formats';
is_deeply $t->detect('application/json'),       ['json'],  'right formats';
is_deeply $t->detect('audio/mpeg'),             ['mp3'],   'right formats';
is_deeply $t->detect('video/mp4'),              ['mp4'],   'right formats';
is_deeply $t->detect('audio/ogg'),              ['ogg'],   'right formats';
is_deeply $t->detect('video/ogg'),              ['ogv'],   'right formats';
is_deeply $t->detect('application/pdf'),        ['pdf'],   'right formats';
is_deeply $t->detect('image/png'),              ['png'],   'right formats';
is_deeply $t->detect('application/rss+xml'),    ['rss'],   'right formats';
is_deeply $t->detect('image/svg+xml'),          ['svg'],   'right formats';
is_deeply $t->detect('text/plain'),             ['txt'],   'right formats';
is_deeply $t->detect('video/webm'),             ['webm'],  'right formats';
is_deeply $t->detect('application/font-woff2'), ['woff2'], 'right formats';
is_deeply $t->detect('font/woff2'),             ['woff2'], 'right formats';
is_deeply $t->detect('application/font-woff'),  ['woff'],  'right formats';
is_deeply $t->detect('font/woff'),              ['woff'],  'right formats';
is_deeply $t->detect('application/xml'),        ['xml'],   'right formats';
is_deeply $t->detect('text/xml'),               ['xml'],   'right formats';
is_deeply $t->detect('application/zip'),        ['zip'],   'right format';

# Detect special cases
is_deeply $t->detect('Application/Xml'), ['xml'], 'right formats';
is_deeply $t->detect(' Text/Xml '),      ['xml'], 'right formats';
is_deeply $t->detect('APPLICATION/XML'), ['xml'], 'right formats';
is_deeply $t->detect('TEXT/XML'),        ['xml'], 'right formats';
is_deeply $t->detect('text/html;q=0.9'), ['htm', 'html'], 'right formats';
is_deeply $t->detect('TEXT/HTML;Q=0.9'), ['htm', 'html'], 'right formats';

# Alternatives
$t->type(json => ['application/json', 'text/x-json']);
is $t->mapping->{json}[0], 'application/json', 'right type';
is $t->mapping->{json}[1], 'text/x-json',      'right type';
ok !$t->mapping->{json}[2], 'no type';
is_deeply $t->mapping->{htm}, ['text/html'], 'right type';
is_deeply $t->mapping->{html}, ['text/html;charset=UTF-8'], 'right type';
is_deeply $t->detect('application/json'),  ['json'], 'right formats';
is_deeply $t->detect('text/x-json'),       ['json'], 'right formats';
is_deeply $t->detect('TEXT/X-JSON;q=0.1'), ['json'], 'right formats';
is_deeply $t->detect('APPLICATION/JsoN'),  ['json'], 'right formats';
is_deeply $t->detect('text/html'), ['htm', 'html'], 'right formats';
is $t->type('json'), 'application/json',        'right type';
is $t->type('htm'),  'text/html',               'right type';
is $t->type('html'), 'text/html;charset=UTF-8', 'right type';

# Prioritize
is_deeply $t->detect('text/plain'), ['txt'], 'right formats';
is_deeply $t->detect('text/plain,text/html'), ['htm', 'html', 'txt'],
  'right formats';
is_deeply $t->detect('TEXT/HTML; q=0.8 '), ['htm', 'html'], 'right formats';
is_deeply $t->detect('TEXT/HTML  ;  q  =  0.8 '), ['htm', 'html'],
  'right formats';
is_deeply $t->detect('TEXT/HTML;Q=0.8,text/plain;Q=0.9'),
  ['txt', 'htm', 'html'], 'right formats';
is_deeply $t->detect(' TEXT/HTML , text/plain;Q=0.9'), ['htm', 'html', 'txt'],
  'right formats';
is_deeply $t->detect('text/plain;q=0.5, text/xml, application/xml;q=0.1'),
  ['xml', 'txt', 'xml'], 'right formats';
is_deeply $t->detect('application/json, text/javascript, */*; q=0.01'),
  ['json'], 'right formats';

# File types
is $t->file_type('foo/bar.png'), 'image/png',              'right type';
is $t->file_type('foo/bar.js'),  'application/javascript', 'right type';
is $t->file_type('foo/bar'),     undef,                    'no type';

# Content types
my $c = Mojolicious->new->build_controller;
$t->content_type($c, {ext => 'json'});
is $c->res->headers->content_type, 'application/json', 'right type';
$t->content_type($c, {ext => 'txt'});
is $c->res->headers->content_type, 'application/json', 'type not changed';
$c->res->headers->remove('Content-Type');
$t->content_type($c, {ext => 'html'});
is $c->res->headers->content_type, 'text/html;charset=UTF-8', 'right type';
$c->res->headers->remove('Content-Type');
$t->content_type($c, {ext => 'unknown'});
is $c->res->headers->content_type, 'text/plain;charset=UTF-8', 'right type';
$c->res->headers->remove('Content-Type');
$t->content_type($c, {file => 'foo/bar.png'});
is $c->res->headers->content_type, 'image/png', 'right type';

done_testing();
