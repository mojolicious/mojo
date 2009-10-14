# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Headers;

use strict;
use warnings;

use base 'Mojo::Stateful';
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::Buffer;

__PACKAGE__->attr(buffer => sub { Mojo::Buffer->new });

__PACKAGE__->attr(_buffer  => sub { [] });
__PACKAGE__->attr(_headers => sub { {} });

my @GENERAL_HEADERS = qw/
  Cache-Control
  Connection
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

my (%ORDERED_HEADERS, %NORMALCASE_HEADERS);
{
    my $i = 1;
    my @headers = (@GENERAL_HEADERS, @REQUEST_HEADERS, @RESPONSE_HEADERS,
        @ENTITY_HEADERS);
    for my $name (@headers) {
        my $lowercase = lc $name;
        $ORDERED_HEADERS{$lowercase}    = $i;
        $NORMALCASE_HEADERS{$lowercase} = $name;
        $i++;
    }
}

sub add {
    my $self = shift;
    my $name = shift;

    # Filter illegal characters from header name
    # (1*<any CHAR except CTLs or separators>)
    $name =~ s/[[:cntrl:]\(\|\)\<\>\@\,\;\:\\\"\/\[\]\?\=\{\}\s]//g;

    # Make sure we have a normal case entry for name
    my $lcname = lc $name;
    unless ($NORMALCASE_HEADERS{$lcname}) {
        $NORMALCASE_HEADERS{$lcname} = $name;
    }
    $name = $lcname;

    # Filter values
    my @values;
    for my $v (@_) {
        push @values, [];

        for my $value (@{ref $v eq 'ARRAY' ? $v : [$v]}) {

            # Filter control characters
            $value = '' unless defined $value;
            $value =~ s/[[:cntrl:]]//g;

            push @{$values[-1]}, $value;
        }
    }

    # Add line
    push @{$self->_headers->{$name}}, @values;

    return $self;
}

sub build {
    my $self = shift;

    # Prepare headers
    my @headers;
    for my $name (@{$self->names}) {

        # Multiline value?
        for my $values ($self->header($name)) {
            my $value = join "\x0d\x0a ", @$values;
            push @headers, "$name: $value";
        }
    }

    # Format headers
    my $headers = join "\x0d\x0a", @headers;
    return length $headers ? $headers : undef;
}

sub connection          { shift->header('Connection',          @_) }
sub content_disposition { shift->header('Content-Disposition', @_) }
sub content_length      { shift->header('Content-Length',      @_) }

sub content_transfer_encoding {
    shift->header('Content-Transfer-Encoding', @_);
}

sub content_type { shift->header('Content-Type', @_) }
sub cookie       { shift->header('Cookie',       @_) }
sub date         { shift->header('Date',         @_) }
sub expect       { shift->header('Expect',       @_) }

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
    return unless $headers = $self->_headers->{lc $name};

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

sub host     { shift->header('Host',     @_) }
sub location { shift->header('Location', @_) }

sub names {
    my $self = shift;

    # Names
    my @names = keys %{$self->_headers};

    # Sort
    @names = sort {
        ($ORDERED_HEADERS{$a} || 999) <=> ($ORDERED_HEADERS{$b} || 999)
          || $a cmp $b
    } @names;

    # Normal case
    my @headers;
    for my $name (@names) {
        push @headers, $NORMALCASE_HEADERS{$name} || $name;
    }

    return \@headers;
}

sub parse {
    my ($self, $chunk) = @_;

    # Buffer
    $self->buffer->add_chunk($chunk);

    # Parse headers
    $self->state('headers') if $self->is_state('start');
    while (1) {

        # Line
        my $line = $self->buffer->get_line;
        last unless defined $line;

        # New header
        if ($line =~ /^(\S+)\s*:\s*(.*)/) {
            push @{$self->_buffer}, $1, $2;
        }

        # Multiline
        elsif (@{$self->_buffer} && $line =~ s/^\s+//) {
            $self->_buffer->[-1] .= " " . $line;
        }

        # Empty line
        else {

            # Store headers
            for (my $i = 0; $i < @{$self->_buffer}; $i += 2) {
                $self->add($self->_buffer->[$i], $self->_buffer->[$i + 1]);
            }

            # Done
            $self->done;
            $self->_buffer([]);
            return $self->buffer;
        }
    }
    return;
}

sub proxy_authorization { shift->header('Proxy-Authorization', @_) }

sub remove {
    my ($self, $name) = @_;
    delete $self->_headers->{lc $name};
    return $self;
}

sub server      { shift->header('Server',      @_) }
sub set_cookie  { shift->header('Set-Cookie',  @_) }
sub set_cookie2 { shift->header('Set-Cookie2', @_) }
sub status      { shift->header('Status',      @_) }

sub to_string { shift->build(@_) }

sub trailer           { shift->header('Trailer',           @_) }
sub transfer_encoding { shift->header('Transfer-Encoding', @_) }
sub user_agent        { shift->header('User-Agent',        @_) }

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

L<Mojo::Headers> inherits all attributes from L<Mojo::Stateful> and
implements the following new ones.

=head2 C<buffer>

    my $buffer = $headers->buffer;
    $headers   = $headers->buffer(Mojo::Buffer->new);

=head2 C<connection>

    my $connection = $headers->connection;
    $headers       = $headers->connection('close');

=head2 C<content_disposition>

    my $content_disposition = $headers->content_disposition;
    $headers                = $headers->content_disposition('foo');

=head2 C<content_length>

    my $content_length = $headers->content_length;
    $headers           = $headers->content_length(4000);

=head2 C<content_transfer_encoding>

    my $encoding = $headers->content_transfer_encoding;
    $headers     = $headers->content_transfer_encoding('foo');

=head2 C<content_type>

    my $content_type = $headers->content_type;
    $headers         = $headers->content_type('text/plain');

=head2 C<cookie>

    my $cookie = $headers->cookie;
    $headers   = $headers->cookie('$Version=1; f=b; $Path=/');

=head2 C<date>

    my $date = $headers->date;
    $headers = $headers->date('Sun, 17 Aug 2008 16:27:35 GMT');

=head2 C<expect>

    my $expect = $headers->expect;
    $headers   = $headers->expect('100-continue');

=head2 C<host>

    my $host = $headers->host;
    $headers = $headers->host('127.0.0.1');

=head2 C<location>

    my $location = $headers->location;
    $headers     = $headers->location('http://127.0.0.1/foo');

=head2 C<proxy_authorization>

    my $proxy_authorization = $headers->proxy_authorization;
    $headers = $headers->proxy_authorization('Basic Zm9vOmJhcg==');

=head2 C<server>

    my $server = $headers->server;
    $headers   = $headers->server('Mojo');

=head2 C<set_cookie>

    my $set_cookie = $headers->set_cookie;
    $headers       = $headers->set_cookie('f=b; Version=1; Path=/');

=head2 C<set_cookie2>

    my $set_cookie2 = $headers->set_cookie2;
    $headers        = $headers->set_cookie2('f=b; Version=1; Path=/');

=head2 C<status>

    my $status = $headers->status;
    $headers   = $headers->status('200 OK');

=head2 C<trailer>

    my $trailer = $headers->trailer;
    $headers    = $headers->trailer('X-Foo');

=head2 C<transfer_encoding>

    my $transfer_encoding = $headers->transfer_encoding;
    $headers              = $headers->transfer_encoding('chunked');

=head2 C<user_agent>

    my $user_agent = $headers->user_agent;
    $headers       = $headers->user_agent('Mojo/1.0');

=head1 METHODS

L<Mojo::Headers> inherits all methods from L<Mojo::Stateful> and implements
the following new ones.

=head2 C<add>

    $headers = $headers->add('Content-Type', 'text/plain');

=head2 C<to_string>

=head2 C<build>

    my $string = $headers->build;
    my $string = $headers->to_string;
    my $string = "$headers";

=head2 C<header>

    my $string = $headers->header('Content-Type');
    my @lines  = $headers->header('Content-Type');
    $headers   = $headers->header('Content-Type', 'text/plain');

=head2 C<names>

    my $names = $headers->names;

=head2 C<parse>

    my $success = $headers->parse("Content-Type: text/foo\n\n");

=head2 C<remove>

    $headers = $headers->remove('Content-Type');

=cut
