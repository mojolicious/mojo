package Mojo::Message::Response;
use Mojo::Base 'Mojo::Message';

use Mojo::Cookie::Response;
use Mojo::Date;
use Mojo::Util 'get_line';

has [qw(code message)];

# Umarked codes are from RFC 2616
my %MESSAGES = (
  100 => 'Continue',
  101 => 'Switching Protocols',
  102 => 'Processing',                         # RFC 2518 (WebDAV)
  200 => 'OK',
  201 => 'Created',
  202 => 'Accepted',
  203 => 'Non-Authoritative Information',
  204 => 'No Content',
  205 => 'Reset Content',
  206 => 'Partial Content',
  207 => 'Multi-Status',                       # RFC 2518 (WebDAV)
  208 => 'Already Reported',                   # RFC 5842
  226 => 'IM Used',                            # RFC 3229
  300 => 'Multiple Choices',
  301 => 'Moved Permanently',
  302 => 'Found',
  303 => 'See Other',
  304 => 'Not Modified',
  305 => 'Use Proxy',
  307 => 'Temporary Redirect',
  308 => 'Permanent Redirect',                 # Draft
  400 => 'Bad Request',
  401 => 'Unauthorized',
  402 => 'Payment Required',
  403 => 'Forbidden',
  404 => 'Not Found',
  405 => 'Method Not Allowed',
  406 => 'Not Acceptable',
  407 => 'Proxy Authentication Required',
  408 => 'Request Timeout',
  409 => 'Conflict',
  410 => 'Gone',
  411 => 'Length Required',
  412 => 'Precondition Failed',
  413 => 'Request Entity Too Large',
  414 => 'Request-URI Too Long',
  415 => 'Unsupported Media Type',
  416 => 'Request Range Not Satisfiable',
  417 => 'Expectation Failed',
  418 => "I'm a teapot",                       # :)
  422 => 'Unprocessable Entity',               # RFC 2518 (WebDAV)
  423 => 'Locked',                             # RFC 2518 (WebDAV)
  424 => 'Failed Dependency',                  # RFC 2518 (WebDAV)
  425 => 'Unordered Colection',                # RFC 3648 (WebDAV)
  426 => 'Upgrade Required',                   # RFC 2817
  428 => 'Precondition Required',              # RFC 6585
  429 => 'Too Many Requests',                  # RFC 6585
  431 => 'Request Header Fields Too Large',    # RFC 6585
  451 => 'Unavailable For Legal Reasons',      # Draft
  500 => 'Internal Server Error',
  501 => 'Not Implemented',
  502 => 'Bad Gateway',
  503 => 'Service Unavailable',
  504 => 'Gateway Timeout',
  505 => 'HTTP Version Not Supported',
  506 => 'Variant Also Negotiates',            # RFC 2295
  507 => 'Insufficient Storage',               # RFC 2518 (WebDAV)
  508 => 'Loop Detected',                      # RFC 5842
  509 => 'Bandwidth Limit Exceeded',           # Unofficial
  510 => 'Not Extended',                       # RFC 2774
  511 => 'Network Authentication Required'     # RFC 6585
);

sub cookies {
  my $self = shift;

  # Parse cookies
  my $headers = $self->headers;
  return [map { @{Mojo::Cookie::Response->parse($_)} } $headers->set_cookie]
    unless @_;

  # Add cookies
  for my $cookie (@_) {
    $cookie = Mojo::Cookie::Response->new($cookie) if ref $cookie eq 'HASH';
    $headers->add('Set-Cookie' => "$cookie");
  }

  return $self;
}

sub default_message { $MESSAGES{$_[1] || $_[0]->code || 404} || '' }

sub extract_start_line {
  my ($self, $bufref) = @_;

  # We have a full response line
  return undef unless defined(my $line = get_line $bufref);
  $self->error('Bad response start line') and return undef
    unless $line =~ m!^\s*HTTP/(\d\.\d)\s+(\d\d\d)\s*(.+)?$!;
  $self->content->skip_body(1) if $self->code($2)->is_empty;
  return !!$self->version($1)->message($3)->content->auto_relax(1);
}

sub fix_headers {
  my $self = shift;
  $self->{fix} ? return $self : $self->SUPER::fix_headers(@_);

  # Date
  my $headers = $self->headers;
  $headers->date(Mojo::Date->new->to_string) unless $headers->date;

  return $self;
}

sub get_start_line_chunk {
  my ($self, $offset) = @_;

  unless (defined $self->{start_buffer}) {
    my $code = $self->code    || 404;
    my $msg  = $self->message || $self->default_message;
    $self->{start_buffer} = "HTTP/@{[$self->version]} $code $msg\x0d\x0a";
  }

  $self->emit(progress => 'start_line', $offset);
  return substr $self->{start_buffer}, $offset, 131072;
}

sub is_empty {
  my $self = shift;
  return undef unless my $code = $self->code;
  return $self->is_status_class(100) || $code eq 204 || $code eq 304;
}

sub is_status_class {
  my ($self, $class) = @_;
  return undef unless my $code = $self->code;
  return $code >= $class && $code < ($class + 100);
}

1;

=head1 NAME

Mojo::Message::Response - HTTP response

=head1 SYNOPSIS

  use Mojo::Message::Response;

  # Parse
  my $res = Mojo::Message::Reponse->new;
  $res->parse("HTTP/1.0 200 OK\x0a\x0d");
  $res->parse("Content-Length: 12\x0a\x0d\x0a\x0d");
  $res->parse("Content-Type: text/plain\x0a\x0d\x0a\x0d");
  $res->parse('Hello World!');
  say $res->code;
  say $res->headers->content_type;
  say $res->body;

  # Build
  my $res = Mojo::Message::Response->new;
  $res->code(200);
  $res->headers->content_type('text/plain');
  $res->body('Hello World!');
  say $res->to_string;

=head1 DESCRIPTION

L<Mojo::Message::Response> is a container for HTTP responses as described in
RFC 2616.

=head1 EVENTS

L<Mojo::Message::Response> inherits all events from L<Mojo::Message>.

=head1 ATTRIBUTES

L<Mojo::Message::Response> inherits all attributes from L<Mojo::Message> and
implements the following new ones.

=head2 code

  my $code = $res->code;
  $res     = $res->code(200);

HTTP response code.

=head2 message

  my $msg = $res->message;
  $res    = $res->message('OK');

HTTP response message.

=head1 METHODS

L<Mojo::Message::Response> inherits all methods from L<Mojo::Message> and
implements the following new ones.

=head2 cookies

  my $cookies = $res->cookies;
  $res        = $res->cookies(Mojo::Cookie::Response->new);
  $res        = $res->cookies({name => 'foo', value => 'bar'});

Access response cookies, usually L<Mojo::Cookie::Response> objects.

=head2 default_message

  my $msg = $res->default_message;

Generate default response message for code.

=head2 extract_start_line

  my $success = $res->extract_start_line(\$str);

Extract status line from string.

=head2 fix_headers

  $res = $res->fix_headers;

Make sure response has all required headers.

=head2 get_start_line_chunk

  my $bytes = $res->get_start_line_chunk($offset);

Get a chunk of status line data starting from a specific position.

=head2 is_empty

  my $success = $res->is_empty;

Check if this is a C<1xx>, C<204> or C<304> response.

=head2 is_status_class

  my $success = $res->is_status_class(200);

Check response status class.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
