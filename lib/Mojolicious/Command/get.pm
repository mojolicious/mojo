package Mojolicious::Command::get;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::DOM;
use Mojo::IOLoop;
use Mojo::JSON qw(encode_json j);
use Mojo::JSON::Pointer;
use Mojo::Util qw(decode encode);
use Scalar::Util 'weaken';

has description => 'Perform HTTP request';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  GetOptionsFromArray \@args,
    'C|charset=s' => \my $charset,
    'c|content=s' => \(my $content = ''),
    'H|header=s'  => \my @headers,
    'M|method=s'  => \(my $method = 'GET'),
    'r|redirect'  => \my $redirect,
    'v|verbose'   => \my $verbose;

  @args = map { decode 'UTF-8', $_ } @args;
  die $self->usage unless my $url = shift @args;
  my $selector = shift @args;

  # Parse header pairs
  my %headers = map { /^\s*([^:]+)\s*:\s*(.+)$/ ? ($1, $2) : () } @headers;

  # Detect proxy for absolute URLs
  my $ua = $self->app->ua->ioloop(Mojo::IOLoop->singleton);
  $ua->server->ioloop(Mojo::IOLoop->singleton);
  $ua->proxy->detect unless $url =~ m!^/!;
  $ua->max_redirects(10) if $redirect;

  my $buffer = '';
  $ua->on(
    start => sub {
      my ($ua, $tx) = @_;

      # Verbose
      weaken $tx;
      $tx->res->content->on(
        body => sub {
          warn $tx->req->$_ for qw(build_start_line build_headers);
          warn $tx->res->$_ for qw(build_start_line build_headers);
        }
      ) if $verbose;

      # Stream content (ignore redirects)
      $tx->res->content->unsubscribe('read')->on(
        read => sub {
          return if $redirect && $tx->res->is_status_class(300);
          defined $selector ? ($buffer .= pop) : print pop;
        }
      );
    }
  );

  # Switch to verbose for HEAD requests
  $verbose = 1 if $method eq 'HEAD';
  STDOUT->autoflush(1);
  my $tx = $ua->start($ua->build_tx($method, $url, \%headers, $content));
  my $err = $tx->error;
  warn qq{Problem loading URL "@{[$tx->req->url]}": $err->{message}\n}
    if $err && !$err->{code};

  # JSON Pointer
  return unless defined $selector;
  return _json($buffer, $selector) if $selector eq '' || $selector =~ m!^/!;

  # Selector
  _select($buffer, $selector, $charset // $tx->res->content->charset, @args);
}

sub _json {
  return unless my $data = j(shift);
  return unless defined($data = Mojo::JSON::Pointer->new($data)->get(shift));
  return _say($data) unless ref $data eq 'HASH' || ref $data eq 'ARRAY';
  say encode_json($data);
}

sub _say { length && say encode('UTF-8', $_) for @_ }

sub _select {
  my ($buffer, $selector, $charset, @args) = @_;

  # Keep a strong reference to the root
  $buffer = decode($charset, $buffer) // $buffer if $charset;
  my $dom     = Mojo::DOM->new($buffer);
  my $results = $dom->find($selector);

  while (defined(my $command = shift @args)) {

    # Number
    ($results = $results->slice($command)) and next if $command =~ /^\d+$/;

    # Text
    return _say($results->map('text')->each) if $command eq 'text';

    # All text
    return _say($results->map('all_text')->each) if $command eq 'all';

    # Attribute
    return _say($results->map(attr => $args[0] // '')->each)
      if $command eq 'attr';

    # Unknown
    die qq{Unknown command "$command".\n};
  }

  _say($results->each);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::get - Get command

=head1 SYNOPSIS

  Usage: APPLICATION get [OPTIONS] URL [SELECTOR|JSON-POINTER] [COMMANDS]

    ./myapp.pl get /
    ./myapp.pl get -H 'Accept: text/html' /hello.html 'head > title' text
    ./myapp.pl get //sri:secr3t@/secrets.json /1/content
    mojo get mojolicio.us
    mojo get -v -r google.com
    mojo get -v -H 'Host: mojolicious.org' -H 'Accept: */*' mojolicio.us
    mojo get -M POST -H 'Content-Type: text/trololo' -c 'trololo' mojolicio.us
    mojo get mojolicio.us 'head > title' text
    mojo get mojolicio.us .footer all
    mojo get mojolicio.us a attr href
    mojo get mojolicio.us '*' attr id
    mojo get mojolicio.us 'h1, h2, h3' 3 text
    mojo get https://api.metacpan.org/v0/author/SRI /name

  Options:
    -C, --charset <charset>     Charset of HTML/XML content, defaults to auto
                                detection
    -c, --content <content>     Content to send with request
    -H, --header <name:value>   Additional HTTP header
    -M, --method <method>       HTTP method to use, defaults to "GET"
    -r, --redirect              Follow up to 10 redirects
    -v, --verbose               Print request and response headers to STDERR

=head1 DESCRIPTION

L<Mojolicious::Command::get> is a command line interface for
L<Mojo::UserAgent>.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::get> performs requests to remote hosts or local
applications.

=head2 description

  my $description = $get->description;
  $get            = $get->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $get->usage;
  $get      = $get->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::get> inherits all methods from L<Mojolicious::Command>
and implements the following new ones.

=head2 run

  $get->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
