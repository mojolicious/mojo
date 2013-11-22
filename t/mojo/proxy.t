use Mojo::Base -strict;

use Test::More;
use Mojo::UserAgent::Proxy;

# Proxy detection
{
  my $proxy = Mojo::UserAgent::Proxy->new;
  local $ENV{HTTP_PROXY}  = 'http://127.0.0.1';
  local $ENV{HTTPS_PROXY} = 'http://127.0.0.1:8080';
  local $ENV{NO_PROXY}    = 'mojolicio.us';
  $proxy->detect;
  is $proxy->http,  'http://127.0.0.1',      'right proxy';
  is $proxy->https, 'http://127.0.0.1:8080', 'right proxy';
  $proxy->http(undef);
  $proxy->https(undef);
  is $proxy->http,  undef, 'right proxy';
  is $proxy->https, undef, 'right proxy';
  ok !$proxy->is_needed('dummy.mojolicio.us'), 'no proxy needed';
  ok $proxy->is_needed('icio.us'),   'proxy needed';
  ok $proxy->is_needed('localhost'), 'proxy needed';
  ($ENV{HTTP_PROXY}, $ENV{HTTPS_PROXY}, $ENV{NO_PROXY}) = ();
  local $ENV{http_proxy}  = 'proxy.example.com';
  local $ENV{https_proxy} = 'tunnel.example.com';
  local $ENV{no_proxy}    = 'localhost,localdomain,foo.com,example.com';
  $proxy->detect;
  is_deeply $proxy->not,
    ['localhost', 'localdomain', 'foo.com', 'example.com'], 'right list';
  is $proxy->http,  'proxy.example.com',  'right proxy';
  is $proxy->https, 'tunnel.example.com', 'right proxy';
  ok $proxy->is_needed('dummy.mojolicio.us'), 'proxy needed';
  ok $proxy->is_needed('icio.us'),            'proxy needed';
  ok !$proxy->is_needed('localhost'),             'proxy needed';
  ok !$proxy->is_needed('localhost.localdomain'), 'no proxy needed';
  ok !$proxy->is_needed('foo.com'),               'no proxy needed';
  ok !$proxy->is_needed('example.com'),           'no proxy needed';
  ok !$proxy->is_needed('www.example.com'),       'no proxy needed';
  ok $proxy->is_needed('www.example.com.com'), 'proxy needed';
}

done_testing();
