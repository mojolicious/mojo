use Mojo::Base -strict;

use Test::More;
use Mojo::TLS qw(TLS TLS_READ TLS_WRITE TLS_NPN TLS_ALPN TLS_C_SNI TLS_S_SNI),
  qw(mojo_protocols selected_protocol);

plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.94+ required for this test!' unless TLS;

is_deeply [mojo_protocols], [qw(http/1.1)],
  'expected list of supported protocols';

done_testing();
