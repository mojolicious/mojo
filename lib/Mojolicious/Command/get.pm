package Mojolicious::Command::get;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::DOM;
use Mojo::IOLoop;
use Mojo::JSON;
use Mojo::JSON::Pointer;
use Mojo::UserAgent;
use Mojo::Util qw(decode encode);
use Scalar::Util 'weaken';

has description => "Perform HTTP request.\n";
has usage       => <<"EOF";
usage: $0 get [OPTIONS] URL [SELECTOR|JSON-POINTER] [COMMANDS]

  mojo get /
  mojo get mojolicio.us
  mojo get -v -r google.com
  mojo get -M POST -c 'trololo' mojolicio.us
  mojo get -H 'X-Bender: Bite my shiny metal ass!' mojolicio.us
  mojo get mojolicio.us 'head > title' text
  mojo get mojolicio.us .footer all
  mojo get mojolicio.us a attr href
  mojo get mojolicio.us '*' attr id
  mojo get mojolicio.us 'h1, h2, h3' 3 text
  mojo get http://search.twitter.com/search.json /error

These options are available:
  -C, --charset <charset>     Charset of HTML/XML content, defaults to auto
                              detection.
  -c, --content <content>     Content to send with request.
  -H, --header <name:value>   Additional HTTP header.
  -M, --method <method>       HTTP method to use, defaults to "GET".
  -r, --redirect              Follow up to 10 redirects.
  -v, --verbose               Print request and response headers to STDERR.
EOF

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
  my %headers;
  /^\s*([^:]+)\s*:\s*(.+)$/ and $headers{$1} = $2 for @headers;

  # Detect proxy for absolute URLs
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
  $url !~ m!^/! ? $ua->detect_proxy : $ua->app($self->app);
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
  my ($err, $code) = $tx->error;
  $url = encode 'UTF-8', $url;
  warn qq{Problem loading URL "$url". ($err)\n} if $err && !$code;

  # JSON Pointer
  return unless defined $selector;
  my $type = $tx->res->headers->content_type // '';
  return _json($buffer, $selector) if $type =~ /json/i;

  # Selector
  _select($buffer, $selector, $charset // $tx->res->content->charset, @args);
}

sub _json {
  my $json = Mojo::JSON->new;
  return unless my $data = $json->decode(shift);
  return unless defined($data = Mojo::JSON::Pointer->new->get($data, shift));
  return _say($data) unless ref $data eq 'HASH' || ref $data eq 'ARRAY';
  say $json->encode($data);
}

sub _say {
  return unless length(my $value = shift);
  say encode('UTF-8', $value);
}

sub _select {
  my ($buffer, $selector, $charset, @args) = @_;

  $buffer = decode($charset, $buffer) // $buffer if $charset;
  my $results = Mojo::DOM->new($buffer)->find($selector);

  my $finished;
  while (defined(my $command = shift @args)) {

    # Number
    if ($command =~ /^\d+$/) {
      return unless ($results = [$results->[$command]])->[0];
      next;
    }

    # Text
    elsif ($command eq 'text') { _say($_->text) for @$results }

    # All text
    elsif ($command eq 'all') { _say($_->all_text) for @$results }

    # Attribute
    elsif ($command eq 'attr') {
      next unless my $name = shift @args;
      _say($_->attrs->{$name}) for @$results;
    }

    # Unknown
    else { die qq{Unknown command "$command".\n} }
    $finished++;
  }

  unless ($finished) { _say($_) for @$results }
}

1;

=head1 NAME

Mojolicious::Command::get - Get command

=head1 SYNOPSIS

  use Mojolicious::Command::get;

  my $get = Mojolicious::Command::get->new;
  $get->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::get> is a command interface to L<Mojo::UserAgent>.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::get> performs requests to remote hosts or local
applications.

=head2 description

  my $description = $get->description;
  $get            = $get->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $get->usage;
  $get      = $get->usage('Foo!');

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
