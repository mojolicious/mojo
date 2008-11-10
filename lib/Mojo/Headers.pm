# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Headers;

use strict;
use warnings;

use base 'Mojo::Stateful';
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::Buffer;

__PACKAGE__->attr('buffer',
    chained => 1,
    default => sub { Mojo::Buffer->new }
);

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
    my @headers = (
        @GENERAL_HEADERS,
        @REQUEST_HEADERS,
        @RESPONSE_HEADERS,
        @ENTITY_HEADERS
    );
    for my $name (@headers) {
        my $lowercase = lc $name;
        $ORDERED_HEADERS{$lowercase} = $i;
        $NORMALCASE_HEADERS{$lowercase} = $name;
        $i++;
    }
}

sub add_line {
    my $self = shift;
    my $name = shift;
    $name    = lc $name;

    # Initialize header
    $self->{_headers}          ||= {};
    $self->{_headers}->{$name} ||= [];

    # Add line
    push @{$self->{_headers}->{$name}}, @_;

    return $self;
}

sub build {
    my $self = shift;

    # Prepare headers
    my @headers;
    for my $name ($self->names) {
        for my $value ($self->header($name)) {
            push @headers, "$name: $value";
        }
    }

    # Format headers
    my $headers = join "\x0d\x0a", @headers;
    return length $headers ? $headers : undef;
}

sub connection { return shift->header('Connection', @_) }
sub content_disposition { return shift->header('Content-Disposition', @_) }
sub content_length { return shift->header('Content-Length', @_) }
sub content_type { return shift->header('Content-Type', @_) }
sub cookie { return shift->header('Cookie', @_) }
sub date { return shift->header('Date', @_) }
sub expect { return shift->header('Expect', @_) }

# Will you be my mommy? You smell like dead bunnies...
sub header {
    my $self = shift;
    my $name = shift;

    # Initialize
    $self->{_headers} ||= {};

    # Make sure we have a normal case entry for name
    my $lcname = lc $name;
    unless($NORMALCASE_HEADERS{$lcname}) {
        $NORMALCASE_HEADERS{$lcname} = $name;
    }
    $name = $lcname;

    # Get on undefined header
    unless ($self->{_headers}->{$name}) {
        return undef unless @_;
    }

    # Set
    if (@_) {
        $self->{_headers}->{$name} = [@_];
        return $self;
    }

    # Filter
    my @header;
    for my $value (@{$self->{_headers}->{$name}}) {
        $value =~ s/\s+$//;
        $value =~ s/\n\n+/\n/g;
        $value =~ s/\n([^\040\t])/\n $1/g;
        push @header, $value;
    }

    # String
    return join(', ', @header) unless wantarray;

    # Array
    return @header;
}

sub host { return shift->header('Host', @_) }

sub names {
    my $self = shift;

    # Initialize
    $self->{_headers} ||= {};

    # Names
    my @names = keys %{$self->{_headers}};

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

    return @headers;
}

sub parse {
    my $self = shift;
    $self->buffer->add_chunk(join '', @_) if @_;

    # Parse headers
    $self->state('headers') if $self->is_state('started');
    $self->{__headers} ||= [];
    while (1) {

        # Line
        my $line = $self->buffer->get_line;
        last unless defined $line;

        # New header
        if ($line =~ /^(\S+)\s*:\s*(.*)/) {
            push @{$self->{__headers}}, $1, $2;
        }

        # Multiline
        elsif (@{$self->{__headers}} && $line =~ s/^\s+//) {
            $self->{__headers}->[-1] .= " " . $line;
        }

        # Empty line
        else {

            # Store headers
            for (my $i = 0; $i < @{$self->{__headers}}; $i += 2) {
                $self->header(
                  $self->{__headers}->[$i],
                  $self->{__headers}->[$i + 1]
                );
            }

            # Done
            $self->done;
            delete $self->{__headers};
            return $self->buffer;
        }
    }
    return undef;
}

sub proxy_authorization { return shift->header('Proxy-Authorization', @_) }

sub remove {
    my ($self, $name) = @_;
    $name = lc $name;

    # Initialize
    $self->{_headers} ||= {};

    # Delete
    delete $self->{_headers}->{$name};

    return $self;
}

sub set_cookie { return shift->header('Set-Cookie', @_) }
sub set_cookie2 { return shift->header('Set-Cookie2', @_) }
sub status { return shift->header('Status', @_) }

sub to_string { shift->build(@_) }

sub trailer { return shift->header('Trailer', @_) }
sub transfer_encoding { return shift->header('Transfer-Encoding', @_) }
sub user_agent { return shift->header('User-Agent', @_) }

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

=head2 C<connection>

    my $connection = $headers->connection;
    $headers       = $headers->connection('close');

=head2 C<content_disposition>

    my $content_disposition = $headers->content_disposition;
    $headers                = $headers->content_disposition('foo');

=head2 C<content_length>

    my $content_length = $headers->content_length;
    $headers           = $headers->content_length(4000);

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

=head2 C<proxy_authorization>

    my $proxy_authorization = $headers->proxy_authorization;
    $headers = $headers->proxy_authorization('Basic Zm9vOmJhcg==');

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

=head2 C<add_line>

    $headers = $headers->add_line('Content-Type', 'text/plain');

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

    my @names = $headers->names;

=head2 C<parse>

    my $success = $headers->parse("Content-Type: text/foo\n\n");

=head2 C<remove>

    $headers = $headers->remove('Content-Type');

=cut