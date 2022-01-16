
<p align="center">
  <a href="https://mojolicious.org">
    <img src="https://raw.github.com/mojolicious/mojo/main/lib/Mojolicious/resources/public/mojo/logo.png?raw=true" style="margin: 0 auto;">
  </a>
</p>

 [![](https://github.com/mojolicious/mojo/workflows/linux/badge.svg)](https://github.com/mojolicious/mojo/actions) [![](https://github.com/mojolicious/mojo/workflows/macos/badge.svg)](https://github.com/mojolicious/mojo/actions) [![](https://github.com/mojolicious/mojo/workflows/windows/badge.svg)](https://github.com/mojolicious/mojo/actions)

  Mojolicious is a fresh take on Perl web development, based on years of experience developing the Catalyst framework,
  and utilizing the latest web standards and technologies. You can get started with your project quickly, with a
  framework that grows with your needs.

  The Mojo stack provides a consistent set of components that can be used in any project. The guides cover most aspects
  of using the framework and the components have comprehensive reference documentation. Mojolicious is a real-time web
  framework, which allows a new class of web applications using WebSockets and having long-running requests without
  blocking.

  Join us now, and be a part of a friendly and knowledgeable community of developers!

## Features

  * An amazing **real-time web framework**, allowing you to easily grow single file prototypes into well-structured MVC
    web applications.
    * Everything you need to build cloud-native web applications for state of the art container environments.
    * Powerful out of the box with RESTful routes, plugins, commands, Perl-ish templates, content negotiation, session
      management, form validation, testing framework, static file server, CGI/[PSGI](http://plackperl.org) detection,
      first class Unicode support and much more for you to discover.
  * A powerful **web development toolkit**, that you can use for all kinds of applications, independently of the web
    framework.
    * Full stack HTTP and WebSocket client/server implementation with IPv6, TLS, SNI, IDNA, HTTP/SOCKS5 proxy, UNIX
      domain socket, Comet (long polling), Promises/A+, async/await, keep-alive, connection pooling, timeout, cookie,
      multipart, and gzip compression support.
    * Built-in non-blocking I/O web server, supporting multiple event loops as well as optional pre-forking and hot
      deployment, perfect for building highly scalable web services.
    * JSON and HTML/XML parser with CSS selector support.
  * Very clean, portable and object-oriented pure-Perl API with no hidden magic and no requirements besides Perl 5.26.0
    (versions as old as 5.16.0 can be used too, but may require additional CPAN modules to be installed)
  * Fresh code based upon years of experience developing [Catalyst](https://en.wikipedia.org/wiki/Catalyst_(software)),
    free and open source.
  * Hundreds of 3rd party [extensions](https://metacpan.org/requires/distribution/Mojolicious) and high quality spin-off
    projects like the [Minion](https://metacpan.org/pod/Minion) job queue.

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

  To run the example with the built-in development web server, just put the code into a file and start it with `morbo`.

    $ morbo hello.pl
    Web application available at http://127.0.0.1:3000

  Test it with any HTTP client you prefer.

    $ curl http://127.0.0.1:3000/
    I ♥ Mojolicious!

## Duct tape for the HTML5 web

  Use all the latest Perl and HTML features in beautiful single file prototypes like this one, and
  [grow](https://docs.mojolicious.org/Mojolicious/Guides/Growing#Differences) them easily into well-structured
  **Model-View-Controller** web applications.

```perl
use Mojolicious::Lite -signatures;

# Render template "index.html.ep" from the DATA section
get '/' => sub ($c) {
  $c->render(template => 'index');
};

# WebSocket service used by the template to extract the title from a website
websocket '/title' => sub ($c) {
  $c->on(message => sub ($c, $msg) {
    my $title = $c->ua->get($msg)->result->dom->at('title')->text;
    $c->send($title);
  });
};

app->start;
__DATA__

@@ index.html.ep
% my $url = url_for 'title';
<script>
  const ws = new WebSocket('<%= $url->to_abs %>');
  ws.onmessage = function (event) { document.body.innerHTML += event.data };
  ws.onopen    = function (event) { ws.send('https://mojolicious.org') };
</script>
```

## Want to know more?

  Take a look at our excellent [documentation](https://docs.mojolicious.org)!
