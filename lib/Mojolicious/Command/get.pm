package Mojolicious::Command::get;
use Mojo::Base 'Mojo::Command';

use Getopt::Long qw(GetOptions :config no_auto_abbrev no_ignore_case);
use Mojo::DOM;
use Mojo::IOLoop;
use Mojo::JSON;
use Mojo::JSON::Pointer;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;
use Mojo::Util qw(decode encode);

has description => "Perform HTTP 1.1 request.\n";
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
  -C, --charset <charset>     Charset of HTML5/XML content, defaults to auto
                              detection or "UTF-8".
  -c, --content <content>     Content to send with request.
  -H, --header <name:value>   Additional HTTP header.
  -M, --method <method>       HTTP method to use, defaults to "GET".
  -r, --redirect              Follow up to 10 redirects.
  -v, --verbose               Print request and response headers to STDERR.
EOF

# "Objection.
#  In the absence of pants, defense's suspenders serve no purpose.
#  I'm going to allow them... for now."
sub run {
  my $self = shift;

  # Options
  local @ARGV = @_;
  my ($method, $content, @headers) = ('GET', '');
  my ($charset, $redirect, $verbose) = 0;
  GetOptions(
    'C|charset=s' => sub { $charset  = $_[1] },
    'c|content=s' => sub { $content  = $_[1] },
    'H|header=s'  => \@headers,
    'M|method=s'  => sub { $method   = $_[1] },
    'r|redirect'  => sub { $redirect = 1 },
    'v|verbose'   => sub { $verbose  = 1 }
  );
  $verbose = 1 if $method eq 'HEAD';

  # Headers
  my %headers;
  for my $header (@headers) {
    next unless $header =~ /^\s*([^:]+)\s*:\s*([^:]+)\s*$/;
    $headers{$1} = $2;
  }

  # URL and selector
  my $url = shift @ARGV;
  die $self->usage unless $url;
  $url = decode 'UTF-8', $url;
  my $selector = shift @ARGV;

  # Fresh user agent
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
  $ua->max_redirects(10) if $redirect;

  # Absolute URL
  if ($url !~ m!/!) { $ua->detect_proxy }

  # Application
  else { $ua->app($ENV{MOJO_APP} || 'Mojo::HelloWorld') }

  # Start
  my $v;
  my $buffer = '';
  $ua->on(
    start => sub {
      my $tx = pop;

      # Prepare request information
      my $req         = $tx->req;
      my $startline   = $req->build_start_line;
      my $req_headers = $req->build_headers;

      # Verbose callback
      my $v  = $verbose;
      my $cb = sub {
        my $res = shift;

        # Wait for headers
        return unless $v && $res->headers->is_finished;

        # Request
        warn "$startline$req_headers";

        # Response
        my $version     = $res->version;
        my $code        = $res->code;
        my $message     = $res->message;
        my $res_headers = $res->headers->to_string;
        warn "HTTP/$version $code $message\n$res_headers\n\n";

        # Finished
        $v = 0;
      };

      # Progress
      $tx->res->on(progress => sub { $cb->(shift) });

      # Stream content
      $tx->res->body(
        sub {
          my $res = shift;
          $cb->($res);

          # Ignore intermediate content
          return if $redirect && $res->is_status_class(300);

          # Chunk
          $selector ? ($buffer .= pop) : print(pop);
        }
      );
    }
  );

  # Get
  my $tx = $ua->build_tx($method, $url, \%headers, $content);
  STDOUT->autoflush(1);
  $tx = $ua->start($tx);

  # Error
  my ($message, $code) = $tx->error;
  $url = encode 'UTF-8', $url;
  warn qq{Problem loading URL "$url". ($message)\n} if $message && !$code;

  # JSON Pointer
  return unless $selector;
  return $self->_json($buffer, $selector)
    if ($tx->res->headers->content_type || '') =~ /JSON/i;

  # Selector
  $self->_select($buffer, $charset // $tx->res->content->charset, $selector);
}

sub _json {
  my ($self, $buffer, $pointer) = @_;
  my $json = Mojo::JSON->new;
  return unless my $data = $json->decode($buffer);
  return unless defined($data = Mojo::JSON::Pointer->get($data, $pointer));
  ref $data ~~ ['HASH', 'ARRAY'] ? say($json->encode($data)) : _say($data);
}

sub _say {
  return unless length(my $value = shift);
  say encode('UTF-8', $value);
}

sub _select {
  my ($self, $buffer, $charset, $selector) = @_;

  # Find
  my $dom     = Mojo::DOM->new->charset($charset)->parse($buffer);
  my $results = $dom->find($selector);

  # Commands
  my $finished = 0;
  while (defined(my $command = shift @ARGV)) {

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
      next unless my $name = shift @ARGV;
      _say($_->attrs->{$name}) for @$results;
    }

    # Unknown
    else { die qq{Unknown command "$command".\n} }
    $finished++;
  }

  # Render
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

=head1 ATTRIBUTES

L<Mojolicious::Command::get> performs requests to remote hosts or local
applications.

=head2 C<description>

  my $description = $get->description;
  $get            = $get->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $get->usage;
  $get      = $get->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::get> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

  $get->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
