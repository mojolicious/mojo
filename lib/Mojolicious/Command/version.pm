package Mojolicious::Command::version;
use Mojo::Base 'Mojo::Command';

use Mojo::IOLoop::Server;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious;

has description => <<'EOF';
Show versions of installed modules.
EOF
has usage => <<"EOF";
usage: $0 version

EOF

# "It's so cold, my processor is running at peak efficiency!"
sub run {
  my $self = shift;

  # Latest version
  my ($current) = $Mojolicious::VERSION =~ /^([^_]+)/;
  my $latest = $current;
  eval {
    Mojo::UserAgent->new->max_redirects(3)
      ->get('search.cpan.org/dist/Mojolicious')->res->dom('.version')
      ->each(sub { $latest = $_->text if $_->text =~ /^[\d\.]+$/ });
  };

  # Message
  my $message = 'This version is up to date, have fun!';
  $message = 'Thanks for testing a development release, you are awesome!'
    if $latest < $current;
  $message = "You might want to update your Mojolicious to $latest."
    if $latest > $current;

  # EV
  my $ev = eval 'use Mojo::IOWatcher::EV; 1' ? $EV::VERSION : 'not installed';

  # IPv6
  my $ipv6 =
    Mojo::IOLoop::Server::IPV6() ? $IO::Socket::IP::VERSION : 'not installed';

  # TLS
  my $tls =
    Mojo::IOLoop::Server::TLS() ? $IO::Socket::SSL::VERSION : 'not installed';

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
  EV                       ($ev)
  IO::Socket::IP           ($ipv6)
  IO::Socket::SSL          ($tls)
  Net::Rendezvous::Publish ($bonjour)

$message
EOF
}

1;
__END__

=head1 NAME

Mojolicious::Command::version - Version Command

=head1 SYNOPSIS

  use Mojolicious::Command::version;

  my $v = Mojolicious::Command::version->new;
  $v->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::version> shows versions of installed modules.

=head1 ATTRIBUTES

L<Mojolicious::Command::version> inherits all attributes from
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

L<Mojolicious::Command::version> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

  $v->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
