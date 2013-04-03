package Mojolicious::Command::version;
use Mojo::Base 'Mojolicious::Command';

use Mojo::IOLoop::Server;
use Mojo::UserAgent;
use Mojolicious;

has description => "Show versions of installed modules.\n";
has usage       => "usage: $0 version\n";

sub run {
  my $self = shift;

  my $ev = eval 'use Mojo::Reactor::EV; 1' ? $EV::VERSION : 'not installed';
  my $ipv6
    = Mojo::IOLoop::Server::IPV6 ? $IO::Socket::IP::VERSION : 'not installed';
  my $tls
    = Mojo::IOLoop::Server::TLS ? $IO::Socket::SSL::VERSION : 'not installed';

  print <<"EOF";
CORE
  Perl        ($^V, $^O)
  Mojolicious ($Mojolicious::VERSION, $Mojolicious::CODENAME)

OPTIONAL
  EV 4.0+               ($ev)
  IO::Socket::IP 0.16+  ($ipv6)
  IO::Socket::SSL 1.75+ ($tls)

EOF

  # Check latest version on CPAN
  my $latest = eval {
    my $ua = Mojo::UserAgent->new(max_redirects => 10)->detect_proxy;
    $ua->get('api.metacpan.org/v0/release/Mojolicious')->res->json->{version};
  };

  return unless $latest;
  my $msg = 'This version is up to date, have fun!';
  $msg = 'Thanks for testing a development release, you are awesome!'
    if $latest < $Mojolicious::VERSION;
  $msg = "You might want to update your Mojolicious to $latest."
    if $latest > $Mojolicious::VERSION;
  say $msg;
}

1;

=head1 NAME

Mojolicious::Command::version - Version command

=head1 SYNOPSIS

  use Mojolicious::Command::version;

  my $v = Mojolicious::Command::version->new;
  $v->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::version> shows version information for installed core
and optional modules.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::version> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $v->description;
  $v              = $v->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $v->usage;
  $v        = $v->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::version> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $v->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
