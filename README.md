
# Mojolicious [![Build Status](https://travis-ci.org/kraih/mojo.svg?branch=master)](https://travis-ci.org/kraih/mojo)

  Back in the early days of the web, many people learned Perl because of a
  wonderful Perl library called [CGI](https://metacpan.org/module/CGI). It was
  simple enough to get started without knowing much about the language and
  powerful enough to keep you going, learning by doing was much fun. While
  most of the techniques used are outdated now, the idea behind it is not.
  Mojolicious is a new attempt at implementing this idea using state of the
  art technology.

## Features

  * An amazing real-time web framework, allowing you to easily grow single
    file prototypes into well-structured web applications.
    * Powerful out of the box with RESTful routes, plugins, commands, Perl-ish
      templates, content negotiation, session management, form validation,
      testing framework, static file server, first class Unicode support and
      much more for you to discover.
  * Very clean, portable and object-oriented pure-Perl API with no hidden
    magic and no requirements besides Perl 5.20.0 (versions as old as 5.10.1
    can be used too, but may require additional CPAN modules to be installed)
  * Full stack HTTP and WebSocket client/server implementation with IPv6, TLS,
    SNI, IDNA, HTTP/SOCKS5 proxy, Comet (long polling), keep-alive, connection
    pooling, timeout, cookie, multipart, and gzip compression support.
  * Built-in non-blocking I/O web server, supporting multiple event loops as
    well as optional preforking and hot deployment, perfect for embedding.
  * Automatic CGI and [PSGI](http://plackperl.org) detection.
  * JSON and HTML/XML parser with CSS selector support.
  * Fresh code based upon years of experience developing
    [Catalyst](http://www.catalystframework.org).

## Installation

  All you need is a one-liner, it takes less than a minute.

    $ curl -L https://cpanmin.us | perl - -M https://cpan.metacpan.org -n Mojolicious

  We recommend the use of a [Perlbrew](http://perlbrew.pl) environment.

## Getting Started

  These three lines are a whole web application.

```perl
use Mojolicious::Lite;

get '/' => {text => 'I ♥ Mojolicious!'};

app->start;
```

  To run this example with the built-in development web server just put the
  code into a file and start it with `morbo`.

    $ morbo hello.pl
    Server available at http://127.0.0.1:3000

    $ curl http://127.0.0.1:3000/
    I ♥ Mojolicious!

## Duct tape for the HTML5 web

  Use all the latest Perl and HTML features in beautiful single file
  prototypes like this one, and grow them easily into well-structured
  applications.

```perl
use Mojolicious::Lite;
use 5.20.0;
use experimental 'signatures';

# Render template "index.html.ep" from the DATA section
get '/' => {template => 'index'};

# WebSocket service used by the template to extract the title from a web site
websocket '/title' => sub ($c) {
  $c->on(message => sub ($c, $msg) {
    my $title = $c->ua->get($msg)->res->dom->at('title')->text;
    $c->send($title);
  });
};

app->start;
__DATA__

@@ index.html.ep
% my $url = url_for 'title';
<script>
  var ws = new WebSocket('<%= $url->to_abs %>');
  ws.onmessage = function (event) { document.body.innerHTML += event.data };
  ws.onopen    = function (event) { ws.send('http://mojolicio.us') };
</script>
```

## Want to know more?

  Take a look at our excellent [documentation](http://mojolicio.us/perldoc>)!
