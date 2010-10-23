package Mojo::Headers;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::ByteStream 'b';

__PACKAGE__->attr(buffer => sub { b() });

# Headers
my @GENERAL_HEADERS = qw/
  Connection
  Cache-Control
  Date
  Pragma
  Trailer
  Transfer-Encoding
  Upgrade
  Via
  Warning
  /;
my @REQUEST_HEADERS = qw/
  Accept
  Accept-Charset
  Accept-Encoding
  Accept-Language
  Authorization
  Expect
  From
  Host
  If-Match
  If-Modified-Since
  If-None-Match
  If-Range
  If-Unmodified-Since
  Max-Forwards
  Proxy-Authorization
  Range
  Referer
  TE
  User-Agent
  /;
my @RESPONSE_HEADERS = qw/
  Accept-Ranges
  Age
  ETag
  Location
  Proxy-Authenticate
  Retry-After
  Server
  Vary
  WWW-Authenticate
  /;
my @ENTITY_HEADERS = qw/
  Allow
  Content-Encoding
  Content-Language
  Content-Length
  Content-Location
  Content-MD5
  Content-Range
  Content-Type
  Expires
  Last-Modified
  /;
my @WEBSOCKET_HEADERS = qw/
  Origin
  Sec-WebSocket-Key1
  Sec-WebSocket-Key2
  Sec-WebSocket-Origin
  Sec-WebSocket-Location
  Sec-WebSocket-Protocol
  /;
my @HEADERS = (
    @GENERAL_HEADERS, @REQUEST_HEADERS, @RESPONSE_HEADERS,
    @ENTITY_HEADERS,  @WEBSOCKET_HEADERS
);

# Lower case headers
my %NORMALCASE_HEADERS;
for my $name (@HEADERS) {
    my $lowercase = lc $name;
    $NORMALCASE_HEADERS{$lowercase} = $name;
}

sub accept_language { scalar shift->header('Accept-Language' => @_) }
sub accept_ranges   { scalar shift->header('Accept-Ranges'   => @_) }
sub authorization   { scalar shift->header('Authorization'   => @_) }

sub add {
    my $self = shift;
    my $name = shift;

    # Make sure we have a normal case entry for name
    my $lcname = lc $name;
    $NORMALCASE_HEADERS{$lcname} = $name
      unless exists $NORMALCASE_HEADERS{$lcname};
    $name = $lcname;

    # Add lines
    push @{$self->{_headers}->{$name}}, (ref $_ || '') eq 'ARRAY' ? $_ : [$_]
      for @_;

    return $self;
}

sub build {
    my $self = shift;

    # Prepare headers
    my @headers;
    for my $name (@{$self->names}) {

        # Multiline value
        for my $values ($self->header($name)) {
            my $value = join "\x0d\x0a ", @$values;
            push @headers, "$name: $value";
        }
    }

    # Format headers
    my $headers = join "\x0d\x0a", @headers;
    return length $headers ? $headers : undef;
}

sub connection          { scalar shift->header(Connection            => @_) }
sub content_disposition { scalar shift->header('Content-Disposition' => @_) }
sub content_length      { scalar shift->header('Content-Length'      => @_) }
sub content_range       { scalar shift->header('Content-Range'       => @_) }

sub content_transfer_encoding {
    scalar shift->header('Content-Transfer-Encoding' => @_);
}

sub content_type { scalar shift->header('Content-Type' => @_) }
sub cookie       { scalar shift->header(Cookie         => @_) }
sub date         { scalar shift->header(Date           => @_) }
sub expect       { scalar shift->header(Expect         => @_) }

sub from_hash {
    my $self = shift;
    my $hash = shift;

    # Empty hash deletes all headers
    if (keys %{$hash} == 0) {
        $self->{_headers} = {};
        return $self;
    }

    # Merge
    foreach my $header (keys %{$hash}) {
        my $value = $hash->{$header};
        $self->add($header => ref $value eq 'ARRAY' ? @$value : $value);
    }

    return $self;
}

# Will you be my mommy? You smell like dead bunnies...
sub header {
    my $self = shift;
    my $name = shift;

    # Set
    if (@_) {
        $self->remove($name);
        return $self->add($name, @_);
    }

    # Get
    my $headers;
    return unless $headers = $self->{_headers}->{lc $name};

    # String
    unless (wantarray) {

        # Format
        my $string = '';
        for my $header (@$headers) {
            $string .= ', ' if $string;
            $string .= join ', ', @$header;
        }

        return $string;
    }

    # Array
    return @$headers;
}

sub host { scalar shift->header(Host => @_) }
sub if_modified_since { scalar shift->header('If-Modified-Since' => @_) }

sub is_done {
    return 1 if (shift->{_state} || '') eq 'done';
    return;
}

sub last_modified { scalar shift->header('Last-Modified' => @_) }
sub location      { scalar shift->header(Location        => @_) }

sub names {
    my $self = shift;

    # Normal case
    my @headers;
    for my $name (keys %{$self->{_headers}}) {
        push @headers, $NORMALCASE_HEADERS{$name} || $name;
    }

    return \@headers;
}

sub origin { scalar shift->header(Origin => @_) }

sub parse {
    my ($self, $chunk) = @_;

    # Buffer
    $self->buffer->add_chunk($chunk);

    # Parse headers
    my $buffer = $self->buffer;
    my $headers = $self->{_buffer} || [];
    $self->{_state} = 'headers';
    while (defined(my $line = $buffer->get_line)) {

        # New header
        if ($line =~ /^(\S+)\s*:\s*(.*)/) { push @$headers, $1, $2 }

        # Multiline
        elsif (@$headers && $line =~ s/^\s+//) { $headers->[-1] .= " $line" }

        # Empty line
        else {

            # Store headers
            for (my $i = 0; $i < @$headers; $i += 2) {
                $self->add($headers->[$i], $headers->[$i + 1]);
            }

            # Done
            $self->{_state}  = 'done';
            $self->{_buffer} = [];
            return $buffer;
        }
    }
    $self->{_buffer} = $headers;

    return;
}

sub proxy_authenticate  { scalar shift->header('Proxy-Authenticate'  => @_) }
sub proxy_authorization { scalar shift->header('Proxy-Authorization' => @_) }
sub range               { scalar shift->header(Range                 => @_) }
sub referrer            { scalar shift->header(Referer               => @_) }

sub remove {
    my ($self, $name) = @_;
    delete $self->{_headers}->{lc $name};
    return $self;
}

sub server      { scalar shift->header(Server        => @_) }
sub set_cookie  { scalar shift->header('Set-Cookie'  => @_) }
sub set_cookie2 { scalar shift->header('Set-Cookie2' => @_) }
sub status      { scalar shift->header(Status        => @_) }

sub to_hash {
    my $self   = shift;
    my %params = @_;

    # Build
    my $hash = {};
    foreach my $header (@{$self->names}) {

        # Header
        my @headers = $self->header($header);

        # Nested arrayrefs
        if ($params{arrayref}) { $hash->{$header} = [@headers] }

        # Flat arrayref
        else {

            # Turn single value arrayrefs into strings
            foreach my $h (@headers) { $h = $h->[0] if @$h == 1 }
            $hash->{$header} = @headers > 1 ? [@headers] : $headers[0];
        }
    }

    return $hash;
}

sub to_string { shift->build(@_) }

sub trailer            { scalar shift->header(Trailer              => @_) }
sub transfer_encoding  { scalar shift->header('Transfer-Encoding'  => @_) }
sub upgrade            { scalar shift->header(Upgrade              => @_) }
sub user_agent         { scalar shift->header('User-Agent'         => @_) }
sub sec_websocket_key1 { scalar shift->header('Sec-WebSocket-Key1' => @_) }
sub sec_websocket_key2 { scalar shift->header('Sec-WebSocket-Key2' => @_) }

sub sec_websocket_location {
    scalar shift->header('Sec-WebSocket-Location' => @_);
}

sub sec_websocket_origin {
    scalar shift->header('Sec-WebSocket-Origin' => @_);
}

sub sec_websocket_protocol {
    scalar shift->header('Sec-WebSocket-Protocol' => @_);
}
sub www_authenticate { scalar shift->header('WWW-Authenticate' => @_) }

1;
__END__

=head1 NAME

Mojo::Headers - Headers

=head1 SYNOPSIS

    use Mojo::Headers;

    my $headers = Mojo::Headers->new;
    $headers->content_type('text/plain');
    $headers->parse("Content-Type: text/html\n\n");
    print "$headers";

=head1 DESCRIPTION

L<Mojo::Headers> is a container and parser for HTTP headers.

=head1 ATTRIBUTES

L<Mojo::Headers> implements the following attributes.

=head2 C<buffer>

    my $buffer = $headers->buffer;
    $headers   = $headers->buffer(Mojo::ByteStream->new);

The Buffer to use for header parsing, by default a L<Mojo::ByteStream>
object.

=head1 METHODS

L<Mojo::Headers> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<accept_language>

    my $accept_language = $headers->accept_language;
    $headers            = $headers->accept_language('de, en');

Shortcut for the C<Accept-Language> header.

=head2 C<accept_ranges>

    my $ranges = $headers->accept_ranges;
    $headers   = $headers->accept_ranges('bytes');

Shortcut for the C<Accept-Ranges> header.

=head2 C<add>

    $headers = $headers->add('Content-Type', 'text/plain');

Add one or more header lines.

=head2 C<authorization>

    my $authorization = $headers->authorization;
    $headers          = $headers->authorization('Basic Zm9vOmJhcg==');

Shortcut for the C<Authorization> header.

=head2 C<to_string>

=head2 C<build>

    my $string = $headers->build;
    my $string = $headers->to_string;
    my $string = "$headers";

Format headers suitable for HTTP 1.1 messages.

=head2 C<connection>

    my $connection = $headers->connection;
    $headers       = $headers->connection('close');

Shortcut for the C<Connection> header.

=head2 C<content_disposition>

    my $content_disposition = $headers->content_disposition;
    $headers                = $headers->content_disposition('foo');

Shortcut for the C<Content-Disposition> header.

=head2 C<content_length>

    my $content_length = $headers->content_length;
    $headers           = $headers->content_length(4000);

Shortcut for the C<Content-Length> header.

=head2 C<content_range>

    my $range = $headers->content_range;
    $headers  = $headers->content_range('bytes 2-8/100');

Shortcut for the C<Content-Range> header.

=head2 C<content_transfer_encoding>

    my $encoding = $headers->content_transfer_encoding;
    $headers     = $headers->content_transfer_encoding('foo');

Shortcut for the C<Content-Transfer-Encoding> header.

=head2 C<content_type>

    my $content_type = $headers->content_type;
    $headers         = $headers->content_type('text/plain');

Shortcut for the C<Content-Type> header.

=head2 C<cookie>

    my $cookie = $headers->cookie;
    $headers   = $headers->cookie('$Version=1; f=b; $Path=/');

Shortcut for the C<Cookie> header.

=head2 C<date>

    my $date = $headers->date;
    $headers = $headers->date('Sun, 17 Aug 2008 16:27:35 GMT');

Shortcut for the C<Date> header.

=head2 C<expect>

    my $expect = $headers->expect;
    $headers   = $headers->expect('100-continue');

Shortcut for the C<Expect> header.

=head2 C<from_hash>

    $headers = $headers->from_hash({'Content-Type' => 'text/html'});

Parse headers from a hash.

=head2 C<header>

    my $string = $headers->header('Content-Type');
    my @lines  = $headers->header('Content-Type');
    $headers   = $headers->header('Content-Type' => 'text/plain');

Get or replace the current header values.
Note that this method is context sensitive and will turn all header lines
into a single one in scalar context.

=head2 C<host>

    my $host = $headers->host;
    $headers = $headers->host('127.0.0.1');

Shortcut for the C<Host> header.

=head2 C<if_modified_since>

    my $m    = $headers->if_modified_since;
    $headers = $headers->if_modified_since('Sun, 17 Aug 2008 16:27:35 GMT');

Shortcut for the C<If-Modified-Since> header.

=head2 C<is_done>

    my $done = $headers->is_done;

Check if header parser is done.

=head2 C<last_modified>

    my $m    = $headers->last_modified;
    $headers = $headers->last_modified('Sun, 17 Aug 2008 16:27:35 GMT');

Shortcut for the C<Last-Modified> header.

=head2 C<location>

    my $location = $headers->location;
    $headers     = $headers->location('http://127.0.0.1/foo');

Shortcut for the C<Location> header.

=head2 C<names>

    my $names = $headers->names;

Generate a list of all currently defined headers.

=head2 C<origin>

    my $origin = $headers->origin;
    $headers   = $headers->origin('http://example.com');

Shortcut for the C<Origin> header.

=head2 C<parse>

    my $success = $headers->parse("Content-Type: text/foo\n\n");

Parse formatted headers.

=head2 C<proxy_authenticate>

    my $authenticate = $headers->proxy_authenticate;
    $headers         = $headers->proxy_authenticate('Basic "realm"');

Shortcut for the C<Proxy-Authenticate> header.

=head2 C<proxy_authorization>

    my $proxy_authorization = $headers->proxy_authorization;
    $headers = $headers->proxy_authorization('Basic Zm9vOmJhcg==');

Shortcut for the C<Proxy-Authorization> header.

=head2 C<range>

    my $range = $headers->range;
    $headers  = $headers->range('bytes=2-8');

Shortcut for the C<Range> header.

=head2 C<referrer>

    my $referrer = $headers->referrer;
    $headers     = $headers->referrer('http://mojolicious.org');

Shortcut for the C<Referer> header, there was a typo in RFC 2068 which
resulted in C<Referer> becoming an official header.

=head2 C<remove>

    $headers = $headers->remove('Content-Type');

Remove a header.

=head2 C<sec_websocket_key1>

    my $key1 = $headers->sec_websocket_key1;
    $headers = $headers->sec_websocket_key1('4 @1  46546xW%0l 1 5');

Shortcut for the C<Sec-WebSocket-Key1> header.

=head2 C<sec_websocket_key2>

    my $key2 = $headers->sec_websocket_key2;
    $headers = $headers->sec_websocket_key2('12998 5 Y3 1  .P00');

Shortcut for the C<Sec-WebSocket-Key2> header.

=head2 C<sec_websocket_location>

    my $location = $headers->sec_websocket_location;
    $headers     = $headers->sec_websocket_location('ws://example.com/demo');

Shortcut for the C<Sec-WebSocket-Location> header.

=head2 C<sec_websocket_origin>

    my $origin = $headers->sec_websocket_origin;
    $headers   = $headers->sec_websocket_origin('http://example.com');

Shortcut for the C<Sec-WebSocket-Origin> header.

=head2 C<sec_websocket_protocol>

    my $protocol = $headers->sec_websocket_protocol;
    $headers     = $headers->sec_websocket_protocol('sample');

Shortcut for the C<Sec-WebSocket-Protocol> header.

=head2 C<server>

    my $server = $headers->server;
    $headers   = $headers->server('Mojo');

Shortcut for the C<Server> header.

=head2 C<set_cookie>

    my $set_cookie = $headers->set_cookie;
    $headers       = $headers->set_cookie('f=b; Version=1; Path=/');

Shortcut for the C<Set-Cookie> header.

=head2 C<set_cookie2>

    my $set_cookie2 = $headers->set_cookie2;
    $headers        = $headers->set_cookie2('f=b; Version=1; Path=/');

Shortcut for the C<Set-Cookie2> header.

=head2 C<status>

    my $status = $headers->status;
    $headers   = $headers->status('200 OK');

Shortcut for the C<Status> header.

=head2 C<to_hash>

    my $hash = $headers->to_hash;
    my $hash = $headers->to_hash(arrayref => 1);

Format headers as a hash.
Nested arrayrefs to represent multi line values are optional.

=head2 C<trailer>

    my $trailer = $headers->trailer;
    $headers    = $headers->trailer('X-Foo');

Shortcut for the C<Trailer> header.

=head2 C<transfer_encoding>

    my $transfer_encoding = $headers->transfer_encoding;
    $headers              = $headers->transfer_encoding('chunked');

Shortcut for the C<Transfer-Encoding> header.

=head2 C<upgrade>

    my $upgrade = $headers->upgrade;
    $headers    = $headers->upgrade('WebSocket');

Shortcut for the C<Upgrade> header.

=head2 C<user_agent>

    my $user_agent = $headers->user_agent;
    $headers       = $headers->user_agent('Mojo/1.0');

Shortcut for the C<User-Agent> header.

=head2 C<www_authenticate>

    my $authenticate = $headers->www_authenticate;
    $headers         = $headers->www_authenticate('Basic "realm"');

Shortcut for the C<WWW-Authenticate> header.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
