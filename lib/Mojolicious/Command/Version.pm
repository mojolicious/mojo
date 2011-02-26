package Mojolicious::Command::Version;
use Mojo::Base 'Mojo::Command';

use Mojo::Client;
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojolicious;

has description => <<'EOF';
Show versions of installed modules.
EOF
has usage => <<"EOF";
usage: $0 version

EOF

# "If at first you don't succeed, give up."
sub run {
  my $self = shift;

  # Latest version
  my ($current) = $Mojolicious::VERSION =~ /^([^_]+)/;
  my $latest = $current;
  eval {
    Mojo::Client->new->max_redirects(3)
      ->get('search.cpan.org/dist/Mojolicious')->res->dom('.version')
      ->each(sub { $latest = $_->text if $_->text =~ /^[\d\.]+$/ });
  };

  # Message
  my $message = 'This version is up to date, have fun!';
  $message = 'Thanks for testing a development release, you are awesome!'
    if $latest < $current;
  $message = "You might want to update your Mojolicious to $latest."
    if $latest > $current;

  # Epoll
  my $epoll = Mojo::IOLoop::EPOLL() ? $IO::Epoll::VERSION : 'not installed';

  # KQueue
  my $kqueue =
    Mojo::IOLoop::KQUEUE() ? $IO::KQueue::VERSION : 'not installed';

  # IPv6
  my $ipv6 =
    Mojo::IOLoop::IPV6() ? $IO::Socket::IP::VERSION : 'not installed';

  # TLS
  my $tls = Mojo::IOLoop::TLS() ? $IO::Socket::SSL::VERSION : 'not installed';

  # Bonjour
  my $bonjour =
    eval 'Mojo::Server::Daemon::BONJOUR()'
    ? $Net::Rendezvous::Publish::VERSION
    : 'not installed';

  print <<"EOF";
CORE
  Perl        ($], $^O)
  Mojolicious ($Mojolicious::VERSION, $Mojolicious::CODENAME)

OPTIONAL
  IO::Epoll                ($epoll)
  IO::KQueue               ($kqueue)
  IO::Socket::IP           ($ipv6)
  IO::Socket::SSL          ($tls)
  Net::Rendezvous::Publish ($bonjour)

$message
EOF

  return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Command::Version - Version Command

=head1 SYNOPSIS

  use Mojolicious::Command::Version;

  my $v = Mojolicious::Command::Version->new;
  $v->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Version> shows versions of installed modules.

=head1 ATTRIBUTES

L<Mojolicious::Command::Version> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

  my $description = $v->description;
  $v              = $v->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $v->usage;
  $v        = $v->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Version> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

  $get = $v->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
