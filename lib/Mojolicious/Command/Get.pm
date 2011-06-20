package Mojolicious::Command::Get;
use Mojo::Base 'Mojo::Command';

use Getopt::Long 'GetOptions';
use Mojo::DOM;
use Mojo::IOLoop;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;
use Mojo::Util 'decode';

has description => <<'EOF';
Get file from URL.
EOF
has usage => <<"EOF";
usage: $0 get [OPTIONS] URL [SELECTOR] [COMMANDS]

  mojo get /
  mojo get mojolicio.us
  mojo get -v -r google.com
  mojo get --method POST --content 'trololo' mojolicio.us
  mojo get --header 'X-Bender: Bite my shiny metal ass!' mojolicio.us
  mojo get mojolicio.us 'head > title' text
  mojo get mojolicio.us .footer all
  mojo get mojolicio.us a attr href
  mojo get mojolicio.us '*' attr id
  mojo get mojolicio.us 'h1, h2, h3' 3 text

These options are available:
  --charset    Charset of XML/HTML5 content, defaults to auto detection or
               UTF-8.
  --header     Additional HTTP header.
  --method     HTTP method to use.
  --redirect   Follow up to 5 redirects.
  --verbose    Print verbose debug information to STDERR.
EOF

# "Objection.
#  In the absence of pants, defense's suspenders serve no purpose.
#  I'm going to allow them... for now."
sub run {
  my $self = shift;

  # Options
  local @ARGV = @_ if @_;
  my $method = 'GET';
  my @headers;
  my $content = '';
  my ($charset, $redirect, $verbose) = 0;
  GetOptions(
    'charset=s' => sub { $charset  = $_[1] },
    'content=s' => sub { $content  = $_[1] },
    'header=s'  => \@headers,
    'method=s'  => sub { $method   = $_[1] },
    'redirect'  => sub { $redirect = 1 },
    'verbose'   => sub { $verbose  = 1 }
  );

  # Headers
  my $headers = {};
  for my $header (@headers) {
    next unless $header =~ /^\s*([^\:]+)\s*:\s*([^\:]+)\s*$/;
    $headers->{$1} = $2;
  }

  # URL and selector
  my $url = shift @ARGV;
  die $self->usage unless $url;
  decode 'UTF-8', $url;
  my $selector = shift @ARGV;

  # Fresh user agent
  my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);

  # Silence
  $ua->log->level('fatal');

  # Absolute URL
  if ($url =~ /^\w+:\/\//) { $ua->detect_proxy }

  # Application
  else { $ua->app($ENV{MOJO_APP} || 'Mojo::HelloWorld') }

  # Follow redirects
  $ua->max_redirects(5) if $redirect;

  # Start
  my $v;
  my $buffer = '';
  $ua->on_start(
    sub {
      my $tx = pop;

      # Prepare request information
      my $req       = $tx->req;
      my $startline = $req->build_start_line;
      my $headers   = $req->build_headers;

      # Verbose callback
      my $v  = $verbose;
      my $cb = sub {
        my $res = shift;

        # Wait for headers
        return unless $v && $res->headers->is_done;

        # Request
        warn "$startline$headers";

        # Response
        my $version = $res->version;
        my $code    = $res->code;
        my $message = $res->message;
        warn "HTTP/$version $code $message\n",
          $res->headers->to_string, "\n\n";

        # Done
        $v = 0;
      };

      # Progress
      $tx->res->on_progress(sub { $cb->(shift) });

      # Stream content
      $tx->res->body(
        sub {
          $cb->(my $res = shift);

          # Ignore intermediate content
          return if $redirect && $res->is_status_class(300);

          # Chunk
          $selector ? ($buffer .= pop) : print(pop);
        }
      );
    }
  );

  # Get
  my $tx = $ua->build_tx($method, $url, $headers, $content);
  $tx = $ua->start($tx);

  # Error
  my ($message, $code) = $tx->error;
  warn qq/Problem loading URL "$url". ($message)\n/ if $message && !$code;

  # Charset
  ($tx->res->headers->content_type || '') =~ /charset=\"?([^\"\s;]+)\"?/
    and $charset = $1
    unless defined $charset;

  # Select
  $self->_select($buffer, $charset, $selector) if $selector;

  $self;
}

sub _select {
  my ($self, $buffer, $charset, $selector) = @_;

  # DOM
  my $dom     = Mojo::DOM->new->charset($charset)->parse($buffer);
  my $results = $dom->find($selector);

  # Commands
  my $done = 0;
  while (my $command = shift @ARGV) {

    # Number
    if ($command =~ /^\d+$/) {
      $results = [$results->[$command]];
      next;
    }

    # Text
    elsif ($command eq 'text') {
      for my $e (@$results) {
        next unless defined(my $text = $e->text);
        utf8::encode $text;
        print "$text\n";
      }
    }

    # All text
    elsif ($command eq 'all') {
      for my $e (@$results) {
        next unless defined(my $text = $e->all_text);
        utf8::encode $text;
        print "$text\n";
      }
    }

    # Attribute
    elsif ($command eq 'attr') {
      next unless my $name = shift @ARGV;
      for my $e (@$results) {
        next unless defined(my $value = $e->attrs->{$name});
        utf8::encode $value;
        print "$value\n";
      }
    }

    # Unknown
    else { die qq/Unknown command "$command".\n/ }

    # Done
    $done++;
  }

  # Raw
  unless ($done) {
    print "$_\n" for @$results;
    return;
  }
}

1;
__END__

=head1 NAME

Mojolicious::Command::Get - Get Command

=head1 SYNOPSIS

  use Mojolicious::Command::Get;

  my $get = Mojolicious::Command::Get->new;
  $get->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Get> is a command interface to L<Mojo::UserAgent>.

=head1 ATTRIBUTES

L<Mojolicious::Command::Get> inherits all attributes from L<Mojo::Command>
and implements the following new ones.

=head2 C<description>

  my $description = $get->description;
  $get            = $get->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $get->usage;
  $get      = $get->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Get> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

  $get = $get->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
