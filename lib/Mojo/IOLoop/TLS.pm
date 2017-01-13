package Mojo::IOLoop::TLS;
use Mojo::Base 'Mojo::EventEmitter';

use Exporter 'import';
use Mojo::File 'path';

# TLS support requires IO::Socket::SSL
use constant HAS_TLS => $ENV{MOJO_NO_TLS}
  ? 0
  : eval 'use IO::Socket::SSL 1.94 (); 1';
use constant READ  => HAS_TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant WRITE => HAS_TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

has reactor => sub { Mojo::IOLoop->singleton->reactor };

our @EXPORT_OK = ('HAS_TLS');

# To regenerate the certificate run this command (18.04.2012)
# openssl req -new -x509 -keyout server.key -out server.crt -nodes -days 7300
my $CERT = path(__FILE__)->dirname->child('resources', 'server.crt')->to_string;
my $KEY  = path(__FILE__)->dirname->child('resources', 'server.key')->to_string;

sub DESTROY {
  my $self = shift;
  return unless my $reactor = $self->reactor;
  $reactor->remove($self->{handle}) if $self->{handle};
}

sub negotiate {
  my ($self, $args) = (shift, ref $_[0] ? $_[0] : {@_});

  return $self->emit(error => 'IO::Socket::SSL 1.94+ required for TLS support')
    unless HAS_TLS;

  my $tls = {
    SSL_ca_file => $args->{tls_ca}
      && -T $args->{tls_ca} ? $args->{tls_ca} : undef,
    SSL_error_trap         => sub { $self->emit(error => $_[1]) },
    SSL_honor_cipher_order => 1,
    SSL_server             => $args->{server},
    SSL_startHandshake     => 0
  };
  $tls->{SSL_cert_file}   = $args->{tls_cert}    if $args->{tls_cert};
  $tls->{SSL_cipher_list} = $args->{tls_ciphers} if $args->{tls_ciphers};
  $tls->{SSL_key_file}    = $args->{tls_key}     if $args->{tls_key};
  $tls->{SSL_verify_mode} = $args->{tls_verify}  if exists $args->{tls_verify};
  $tls->{SSL_version}     = $args->{tls_version} if $args->{tls_version};

  if ($args->{server}) {
    $tls->{SSL_cert_file} ||= $CERT;
    $tls->{SSL_key_file}  ||= $KEY;
    $tls->{SSL_verify_mode} //= $args->{tls_ca} ? 0x03 : 0x00;
  }
  else {
    $tls->{SSL_hostname}
      = IO::Socket::SSL->can_client_sni ? $args->{address} : '';
    $tls->{SSL_verifycn_scheme} = $args->{tls_ca} ? 'http' : undef;
    $tls->{SSL_verify_mode} //= $args->{tls_ca} ? 0x01 : 0x00;
    $tls->{SSL_verifycn_name} = $args->{address};
  }

  my $handle = $args->{handle};
  return $self->emit(error => $IO::Socket::SSL::SSL_ERROR)
    unless IO::Socket::SSL->start_SSL($handle, %$tls);
  $self->reactor->io($self->{handle}
      = $handle => sub { $self->_tls($handle, $args->{server}) });
}

sub _tls {
  my ($self, $handle, $server) = @_;

  return $self->emit(finish => delete $self->{handle})
    if $server ? $handle->accept_SSL : $handle->connect_SSL;

  # Switch between reading and writing
  my $err = $IO::Socket::SSL::SSL_ERROR;
  if    ($err == READ)  { $self->reactor->watch($handle, 1, 0) }
  elsif ($err == WRITE) { $self->reactor->watch($handle, 1, 1) }
}

1;
