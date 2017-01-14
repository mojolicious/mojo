package Mojo::IOLoop::TLS;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::File 'path';
use Mojo::IOLoop;
use Scalar::Util 'weaken';

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS}
  ? 0
  : eval 'use IO::Socket::SSL 1.94 (); 1';
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

has reactor => sub { Mojo::IOLoop->singleton->reactor };

# To regenerate the certificate run this command (18.04.2012)
# openssl req -new -x509 -keyout server.key -out server.crt -nodes -days 7300
my $CERT = path(__FILE__)->dirname->child('resources', 'server.crt')->to_string;
my $KEY  = path(__FILE__)->dirname->child('resources', 'server.key')->to_string;

sub DESTROY {
  my $self = shift;
  return unless my $reactor = $self->reactor;
  $reactor->remove($self->{handle}) if $self->{handle};
}

sub has_tls {TLS}

sub negotiate {
  my ($self, $args) = (shift, ref $_[0] ? $_[0] : {@_});

  return $self->emit(error => 'IO::Socket::SSL 1.94+ required for TLS support')
    unless TLS;

  weaken $self;
  my $tls = {
    SSL_cert_file => $args->{tls_cert} || $CERT,
    SSL_error_trap         => sub { $self->emit(error => $_[1]) },
    SSL_honor_cipher_order => 1,
    SSL_key_file => $args->{tls_key} || $KEY,
    SSL_startHandshake => 0,
    SSL_verify_mode    => $args->{tls_verify} // ($args->{tls_ca} ? 0x03 : 0x00)
  };
  $tls->{SSL_ca_file} = $args->{tls_ca}
    if $args->{tls_ca} && -T $args->{tls_ca};
  $tls->{SSL_cipher_list} = $args->{tls_ciphers} if $args->{tls_ciphers};
  $tls->{SSL_version}     = $args->{tls_version} if $args->{tls_version};

  my $handle = $args->{handle};
  return $self->emit(error => "TLS upgrade failed: $IO::Socket::SSL::SSL_ERROR")
    unless IO::Socket::SSL->start_SSL($handle, %$tls,
    SSL_server => $args->{server});
  $self->reactor->io($self->{handle}
      = $handle => sub { $self->_tls($handle, $args->{server}) });
}

sub _tls {
  my ($self, $handle, $server) = @_;

  return $self->emit(finish => delete $self->{handle})
    if $server ? $handle->accept_SSL : $handle->connect_SSL;

  # Switch between reading and writing
  my $err = $IO::Socket::SSL::SSL_ERROR;
  if    ($err == TLS_READ)  { $self->reactor->watch($handle, 1, 0) }
  elsif ($err == TLS_WRITE) { $self->reactor->watch($handle, 1, 1) }
}

1;
