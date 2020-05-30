package Mojo::Message::Response;
use Mojo::Base 'Mojo::Message';

use Mojo::Cookie::Response;
use Mojo::Date;

has [qw(code message)];
has max_message_size => sub { $ENV{MOJO_MAX_MESSAGE_SIZE} // 2147483648 };

# Unmarked codes are from RFC 7231
my %MESSAGES = (
  100 => 'Continue',
  101 => 'Switching Protocols',
  102 => 'Processing',                         # RFC 2518 (WebDAV)
  103 => 'Early Hints',                        # RFC 8297
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
  308 => 'Permanent Redirect',                 # RFC 7538
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
  418 => "I'm a teapot",                       # RFC 2324 :)
  421 => 'Misdirected Request',                # RFC 7540
  422 => 'Unprocessable Entity',               # RFC 2518 (WebDAV)
  423 => 'Locked',                             # RFC 2518 (WebDAV)
  424 => 'Failed Dependency',                  # RFC 2518 (WebDAV)
  425 => 'Too Early',                          # RFC 8470
  426 => 'Upgrade Required',                   # RFC 2817
  428 => 'Precondition Required',              # RFC 6585
  429 => 'Too Many Requests',                  # RFC 6585
  431 => 'Request Header Fields Too Large',    # RFC 6585
  451 => 'Unavailable For Legal Reasons',      # RFC 7725
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
  return [@{Mojo::Cookie::Response->parse($headers->set_cookie)}] unless @_;

  # Add cookies
  $headers->add('Set-Cookie' => "$_") for map { ref $_ eq 'HASH' ? Mojo::Cookie::Response->new($_) : $_ } @_;

  return $self;
}

sub default_message { $MESSAGES{$_[1] || $_[0]->code // 404} || '' }

sub extract_start_line {
  my ($self, $bufref) = @_;

  # We have a full response line
  return undef unless $$bufref =~ s/^(.*?)\x0d?\x0a//;
  return !$self->error({message => 'Bad response start-line'}) unless $1 =~ m!^\s*HTTP/(\d\.\d)\s+(\d\d\d)\s*(.+)?$!;

  my $content = $self->content;
  $content->skip_body(1) if $self->code($2)->is_empty;
  defined $content->$_ or $content->$_(1) for qw(auto_decompress auto_relax);
  return !!$self->version($1)->message($3);
}

sub fix_headers {
  my $self = shift;
  $self->{fix} ? return $self : $self->SUPER::fix_headers(@_);

  # Date
  my $headers = $self->headers;
  $headers->date(Mojo::Date->new->to_string) unless $headers->date;

  # RFC 7230 3.3.2
  $headers->remove('Content-Length') if $self->is_empty;

  return $self;
}

sub get_start_line_chunk {
  my ($self, $offset) = @_;
  $self->_start_line->emit(progress => 'start_line', $offset);
  return substr $self->{start_buffer}, $offset, 131072;
}

sub is_client_error { shift->_status_class(400) }

sub is_empty {
  my $self = shift;
  return undef unless my $code = $self->code;
  return $self->is_info || $code == 204 || $code == 304;
}

sub is_error        { shift->_status_class(400, 500) }
sub is_info         { shift->_status_class(100) }
sub is_redirect     { shift->_status_class(300) }
sub is_server_error { shift->_status_class(500) }

sub is_success { shift->_status_class(200) }

sub start_line_size { length shift->_start_line->{start_buffer} }

sub _start_line {
  my $self = shift;

  return $self if defined $self->{start_buffer};
  my $code = $self->code    || 404;
  my $msg  = $self->message || $self->default_message;
  $self->{start_buffer} = "HTTP/@{[$self->version]} $code $msg\x0d\x0a";

  return $self;
}

sub _status_class {
  my ($self, @classes) = @_;
  return undef unless my $code = $self->code;
  return !!grep { $code >= $_ && $code < ($_ + 100) } @classes;
}

1;

=encoding utf8

=head1 NAME

Mojo::Message::Response - HTTP response

=head1 SYNOPSIS

  use Mojo::Message::Response;

  # Parse
  my $res = Mojo::Message::Response->new;
  $res->parse("HTTP/1.0 200 OK\x0d\x0a");
  $res->parse("Content-Length: 12\x0d\x0a");
  $res->parse("Content-Type: text/plain\x0d\x0a\x0d\x0a");
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

L<Mojo::Message::Response> is a container for HTTP responses, based on L<RFC 7230|http://tools.ietf.org/html/rfc7230>
and L<RFC 7231|http://tools.ietf.org/html/rfc7231>.

=head1 EVENTS

L<Mojo::Message::Response> inherits all events from L<Mojo::Message>.

=head1 ATTRIBUTES

L<Mojo::Message::Response> inherits all attributes from L<Mojo::Message> and implements the following new ones.

=head2 code

  my $code = $res->code;
  $res     = $res->code(200);

HTTP response status code.

=head2 max_message_size

  my $size = $res->max_message_size;
  $res     = $res->max_message_size(1024);

Maximum message size in bytes, defaults to the value of the C<MOJO_MAX_MESSAGE_SIZE> environment variable or
C<2147483648> (2GiB). Setting the value to C<0> will allow messages of indefinite size.

=head2 message

  my $msg = $res->message;
  $res    = $res->message('OK');

HTTP response status message.

=head1 METHODS

L<Mojo::Message::Response> inherits all methods from L<Mojo::Message> and implements the following new ones.

=head2 cookies

  my $cookies = $res->cookies;
  $res        = $res->cookies(Mojo::Cookie::Response->new);
  $res        = $res->cookies({name => 'foo', value => 'bar'});

Access response cookies, usually L<Mojo::Cookie::Response> objects.

  # Names of all cookies
  say $_->name for @{$res->cookies};

=head2 default_message

  my $msg = $res->default_message;
  my $msg = $res->default_message(418);

Generate default response message for status code, defaults to using L</"code">.

=head2 extract_start_line

  my $bool = $res->extract_start_line(\$str);

Extract status-line from string.

=head2 fix_headers

  $res = $res->fix_headers;

Make sure response has all required headers.

=head2 get_start_line_chunk

  my $bytes = $res->get_start_line_chunk($offset);

Get a chunk of status-line data starting from a specific position. Note that this method finalizes the response.

=head2 is_client_error

  my $bool = $res->is_client_error;

Check if this response has a C<4xx> status L</"code">.

=head2 is_empty

  my $bool = $res->is_empty;

Check if this response has a C<1xx>, C<204> or C<304> status L</"code">.

=head2 is_error

  my $bool = $res->is_error;

Check if this response has a C<4xx> or C<5xx> status L</"code">.

=head2 is_info

  my $bool = $res->is_info;

Check if this response has a C<1xx> status L</"code">.

=head2 is_redirect

  my $bool = $res->is_redirect;

Check if this response has a C<3xx> status L</"code">.

=head2 is_server_error

  my $bool = $res->is_server_error;

Check if this response has a C<5xx> status L</"code">.

=head2 is_success

  my $bool = $res->is_success;

Check if this response has a C<2xx> status L</"code">.

=head2 start_line_size

  my $size = $req->start_line_size;

Size of the status-line in bytes. Note that this method finalizes the response.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
