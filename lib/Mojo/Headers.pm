package Mojo::Headers;
use Mojo::Base -base;

use Mojo::Util qw(get_line monkey_patch);

has max_line_size => sub { $ENV{MOJO_MAX_LINE_SIZE} || 10240 };

# Common headers
my @HEADERS = (
  qw(Accept Accept-Charset Accept-Encoding Accept-Language Accept-Ranges),
  qw(Authorization Cache-Control Connection Content-Disposition),
  qw(Content-Encoding Content-Length Content-Range Content-Type Cookie DNT),
  qw(Date ETag Expect Expires Host If-Modified-Since Last-Modified Location),
  qw(Origin Proxy-Authenticate Proxy-Authorization Range),
  qw(Sec-WebSocket-Accept Sec-WebSocket-Extensions Sec-WebSocket-Key),
  qw(Sec-WebSocket-Protocol Sec-WebSocket-Version Server Set-Cookie Status),
  qw(TE Trailer Transfer-Encoding Upgrade User-Agent WWW-Authenticate)
);
for my $header (@HEADERS) {
  my $name = lc $header;
  $name =~ s/-/_/g;
  monkey_patch __PACKAGE__, $name, sub { scalar shift->header($header => @_) };
}

# Lower case headers
my %NORMALCASE = map { lc($_) => $_ } @HEADERS;

sub add {
  my ($self, $name) = (shift, shift);

  # Make sure we have a normal case entry for name
  my $key = lc $name;
  $self->{normalcase}{$key} //= $name unless $NORMALCASE{$key};

  # Add lines
  push @{$self->{headers}{$key}}, map { ref $_ eq 'ARRAY' ? $_ : [$_] } @_;

  return $self;
}

sub clone {
  my $self = shift;
  return $self->new->from_hash($self->to_hash(1));
}

sub from_hash {
  my ($self, $hash) = @_;

  # Empty hash deletes all headers
  delete $self->{headers} if keys %{$hash} == 0;

  # Merge
  while (my ($header, $value) = each %$hash) {
    $self->add($header => ref $value eq 'ARRAY' ? @$value : $value);
  }

  return $self;
}

sub header {
  my ($self, $name) = (shift, shift);

  # Replace
  return $self->remove($name)->add($name, @_) if @_;

  # String
  return unless my $headers = $self->{headers}{lc $name};
  return join ', ', map { join ', ', @$_ } @$headers unless wantarray;

  # Array
  return @$headers;
}

sub is_finished { (shift->{state} // '') eq 'finished' }

sub is_limit_exceeded { !!shift->{limit} }

sub leftovers { delete shift->{buffer} }

sub names {
  my $self = shift;
  return [map { $NORMALCASE{$_} || $self->{normalcase}{$_} || $_ }
      keys %{$self->{headers}}];
}

sub parse {
  my $self = shift;

  $self->{state} = 'headers';
  $self->{buffer} .= shift // '';
  my $headers = $self->{cache} ||= [];
  my $max = $self->max_line_size;
  while (defined(my $line = get_line \$self->{buffer})) {

    # Check line size limit
    if (length $line > $max) {
      $self->{limit} = $self->{state} = 'finished';
      return $self;
    }

    # New header
    if ($line =~ /^(\S+)\s*:\s*(.*)$/) { push @$headers, $1, [$2] }

    # Multiline
    elsif (@$headers && $line =~ s/^\s+//) { push @{$headers->[-1]}, $line }

    # Empty line
    else {
      $self->add(splice @$headers, 0, 2) while @$headers;
      $self->{state} = 'finished';
      return $self;
    }
  }

  # Check line size limit
  $self->{limit} = $self->{state} = 'finished'
    if length $self->{buffer} > $max;

  return $self;
}

sub referrer { scalar shift->header(Referer => @_) }

sub remove {
  my ($self, $name) = @_;
  delete $self->{headers}{lc $name};
  return $self;
}

sub to_hash {
  my ($self, $multi) = @_;
  my %hash;
  $hash{$_} = $multi ? [$self->header($_)] : scalar $self->header($_)
    for @{$self->names};
  return \%hash;
}

sub to_string {
  my $self = shift;

  # Make sure multiline values are formatted correctly
  my @headers;
  for my $name (@{$self->names}) {
    push @headers, "$name: " . join("\x0d\x0a ", @$_) for $self->header($name);
  }

  return join "\x0d\x0a", @headers;
}

1;

=head1 NAME

Mojo::Headers - Headers

=head1 SYNOPSIS

  use Mojo::Headers;

  # Parse
  my $headers = Mojo::Headers->new;
  $headers->parse("Content-Length: 42\x0d\x0a");
  $headers->parse("Content-Type: text/html\x0d\x0a\x0d\x0a");
  say $headers->content_length;
  say $headers->content_type;

  # Build
  my $headers = Mojo::Headers->new;
  $headers->content_length(42);
  $headers->content_type('text/plain');
  say $headers->to_string;

=head1 DESCRIPTION

L<Mojo::Headers> is a container for HTTP headers as described in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Headers> implements the following attributes.

=head2 max_line_size

  my $size = $headers->max_line_size;
  $headers = $headers->max_line_size(1024);

Maximum header line size in bytes, defaults to the value of the
MOJO_MAX_LINE_SIZE environment variable or C<10240>.

=head1 METHODS

L<Mojo::Headers> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 accept

  my $accept = $headers->accept;
  $headers   = $headers->accept('application/json');

Shortcut for the C<Accept> header.

=head2 accept_charset

  my $charset = $headers->accept_charset;
  $headers    = $headers->accept_charset('UTF-8');

Shortcut for the C<Accept-Charset> header.

=head2 accept_encoding

  my $encoding = $headers->accept_encoding;
  $headers     = $headers->accept_encoding('gzip');

Shortcut for the C<Accept-Encoding> header.

=head2 accept_language

  my $language = $headers->accept_language;
  $headers     = $headers->accept_language('de, en');

Shortcut for the C<Accept-Language> header.

=head2 accept_ranges

  my $ranges = $headers->accept_ranges;
  $headers   = $headers->accept_ranges('bytes');

Shortcut for the C<Accept-Ranges> header.

=head2 add

  $headers = $headers->add(Foo => 'one value');
  $headers = $headers->add(Foo => 'first value', 'second value');
  $headers = $headers->add(Foo => ['first line', 'second line']);

Add one or more header values with one or more lines.

=head2 authorization

  my $authorization = $headers->authorization;
  $headers          = $headers->authorization('Basic Zm9vOmJhcg==');

Shortcut for the C<Authorization> header.

=head2 cache_control

  my $cache_control = $headers->cache_control;
  $headers          = $headers->cache_control('max-age=1, no-cache');

Shortcut for the C<Cache-Control> header.

=head2 clone

  my $clone = $headers->clone;

Clone headers.

=head2 connection

  my $connection = $headers->connection;
  $headers       = $headers->connection('close');

Shortcut for the C<Connection> header.

=head2 content_disposition

  my $disposition = $headers->content_disposition;
  $headers        = $headers->content_disposition('foo');

Shortcut for the C<Content-Disposition> header.

=head2 content_encoding

  my $encoding = $headers->content_encoding;
  $headers     = $headers->content_encoding('gzip');

Shortcut for the C<Content-Encoding> header.

=head2 content_length

  my $len  = $headers->content_length;
  $headers = $headers->content_length(4000);

Shortcut for the C<Content-Length> header.

=head2 content_range

  my $range = $headers->content_range;
  $headers  = $headers->content_range('bytes 2-8/100');

Shortcut for the C<Content-Range> header.

=head2 content_type

  my $type = $headers->content_type;
  $headers = $headers->content_type('text/plain');

Shortcut for the C<Content-Type> header.

=head2 cookie

  my $cookie = $headers->cookie;
  $headers   = $headers->cookie('f=b');

Shortcut for the C<Cookie> header from RFC 6265.

=head2 date

  my $date = $headers->date;
  $headers = $headers->date('Sun, 17 Aug 2008 16:27:35 GMT');

Shortcut for the C<Date> header.

=head2 dnt

  my $dnt  = $headers->dnt;
  $headers = $headers->dnt(1);

Shortcut for the C<DNT> (Do Not Track) header, which has no specification yet,
but is very commonly used.

=head2 etag

  my $etag = $headers->etag;
  $headers = $headers->etag('abc321');

Shortcut for the C<ETag> header.

=head2 expect

  my $expect = $headers->expect;
  $headers   = $headers->expect('100-continue');

Shortcut for the C<Expect> header.

=head2 expires

  my $expires = $headers->expires;
  $headers    = $headers->expires('Thu, 01 Dec 1994 16:00:00 GMT');

Shortcut for the C<Expires> header.

=head2 from_hash

  $headers = $headers->from_hash({'Content-Type' => 'text/html'});
  $headers = $headers->from_hash({});

Parse headers from a hash reference, an empty hash removes all headers.

=head2 header

  my $value  = $headers->header('Foo');
  my @values = $headers->header('Foo');
  $headers   = $headers->header(Foo => 'one value');
  $headers   = $headers->header(Foo => 'first value', 'second value');
  $headers   = $headers->header(Foo => ['first line', 'second line']);

Get or replace the current header values.

  # Multiple headers with the same name
  for my $header ($headers->header('Set-Cookie')) {
    say 'Set-Cookie:';

    # Multiple lines per header
    say for @$header;
  }

=head2 host

  my $host = $headers->host;
  $headers = $headers->host('127.0.0.1');

Shortcut for the C<Host> header.

=head2 if_modified_since

  my $date = $headers->if_modified_since;
  $headers = $headers->if_modified_since('Sun, 17 Aug 2008 16:27:35 GMT');

Shortcut for the C<If-Modified-Since> header.

=head2 is_finished

  my $success = $headers->is_finished;

Check if header parser is finished.

=head2 is_limit_exceeded

  my $success = $headers->is_limit_exceeded;

Check if a header has exceeded C<max_line_size>.

=head2 last_modified

  my $date = $headers->last_modified;
  $headers = $headers->last_modified('Sun, 17 Aug 2008 16:27:35 GMT');

Shortcut for the C<Last-Modified> header.

=head2 leftovers

  my $bytes = $headers->leftovers;

Get leftover data from header parser.

=head2 location

  my $location = $headers->location;
  $headers     = $headers->location('http://127.0.0.1/foo');

Shortcut for the C<Location> header.

=head2 names

  my $names = $headers->names;

Generate a list of all currently defined headers.

=head2 origin

  my $origin = $headers->origin;
  $headers   = $headers->origin('http://example.com');

Shortcut for the C<Origin> header from RFC 6454.

=head2 parse

  $headers = $headers->parse("Content-Type: text/plain\x0d\x0a\x0d\x0a");

Parse formatted headers.

=head2 proxy_authenticate

  my $authenticate = $headers->proxy_authenticate;
  $headers         = $headers->proxy_authenticate('Basic "realm"');

Shortcut for the C<Proxy-Authenticate> header.

=head2 proxy_authorization

  my $authorization = $headers->proxy_authorization;
  $headers          = $headers->proxy_authorization('Basic Zm9vOmJhcg==');

Shortcut for the C<Proxy-Authorization> header.

=head2 range

  my $range = $headers->range;
  $headers  = $headers->range('bytes=2-8');

Shortcut for the C<Range> header.

=head2 referrer

  my $referrer = $headers->referrer;
  $headers     = $headers->referrer('http://example.com');

Shortcut for the C<Referer> header, there was a typo in RFC 2068 which
resulted in C<Referer> becoming an official header.

=head2 remove

  $headers = $headers->remove('Foo');

Remove a header.

=head2 sec_websocket_accept

  my $accept = $headers->sec_websocket_accept;
  $headers   = $headers->sec_websocket_accept('s3pPLMBiTxaQ9kYGzzhZRbK+xOo=');

Shortcut for the C<Sec-WebSocket-Accept> header from RFC 6455.

=head2 sec_websocket_extensions

  my $extensions = $headers->sec_websocket_extensions;
  $headers       = $headers->sec_websocket_extensions('foo');

Shortcut for the C<Sec-WebSocket-Extensions> header from RFC 6455.

=head2 sec_websocket_key

  my $key  = $headers->sec_websocket_key;
  $headers = $headers->sec_websocket_key('dGhlIHNhbXBsZSBub25jZQ==');

Shortcut for the C<Sec-WebSocket-Key> header from RFC 6455.

=head2 sec_websocket_protocol

  my $proto = $headers->sec_websocket_protocol;
  $headers  = $headers->sec_websocket_protocol('sample');

Shortcut for the C<Sec-WebSocket-Protocol> header from RFC 6455.

=head2 sec_websocket_version

  my $version = $headers->sec_websocket_version;
  $headers    = $headers->sec_websocket_version(13);

Shortcut for the C<Sec-WebSocket-Version> header from RFC 6455.

=head2 server

  my $server = $headers->server;
  $headers   = $headers->server('Mojo');

Shortcut for the C<Server> header.

=head2 set_cookie

  my $cookie = $headers->set_cookie;
  $headers   = $headers->set_cookie('f=b; path=/');

Shortcut for the C<Set-Cookie> header from RFC 6265.

=head2 status

  my $status = $headers->status;
  $headers   = $headers->status('200 OK');

Shortcut for the C<Status> header from RFC 3875.

=head2 te

  my $te   = $headers->te;
  $headers = $headers->te('chunked');

Shortcut for the C<TE> header.

=head2 to_hash

  my $single = $headers->to_hash;
  my $multi  = $headers->to_hash(1);

Turn headers into hash reference, nested array references to represent
multiline values are disabled by default.

  say $headers->to_hash->{DNT};

=head2 to_string

  my $str = $headers->to_string;

Turn headers into a string, suitable for HTTP messages.

=head2 trailer

  my $trailer = $headers->trailer;
  $headers    = $headers->trailer('X-Foo');

Shortcut for the C<Trailer> header.

=head2 transfer_encoding

  my $encoding = $headers->transfer_encoding;
  $headers     = $headers->transfer_encoding('chunked');

Shortcut for the C<Transfer-Encoding> header.

=head2 upgrade

  my $upgrade = $headers->upgrade;
  $headers    = $headers->upgrade('websocket');

Shortcut for the C<Upgrade> header.

=head2 user_agent

  my $agent = $headers->user_agent;
  $headers  = $headers->user_agent('Mojo/1.0');

Shortcut for the C<User-Agent> header.

=head2 www_authenticate

  my $authenticate = $headers->www_authenticate;
  $headers         = $headers->www_authenticate('Basic realm="realm"');

Shortcut for the C<WWW-Authenticate> header.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
