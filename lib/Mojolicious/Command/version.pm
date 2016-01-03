package Mojolicious::Command::version;
use Mojo::Base 'Mojolicious::Command';

use Mojo::IOLoop::Client;
use Mojolicious;

has description => 'Show versions of available modules';
has usage => sub { shift->extract_usage };

sub run {
  my $self = shift;

  my $ev    = eval 'use Mojo::Reactor::EV; 1' ? $EV::VERSION : 'n/a';
  my $class = 'Mojo::IOLoop::Client';
  my $socks = $class->SOCKS ? $IO::Socket::Socks::VERSION : 'n/a';
  my $tls   = $class->TLS ? $IO::Socket::SSL::VERSION : 'n/a';
  my $ndn   = $class->NDN ? $Net::DNS::Native::VERSION : 'n/a';

  print <<EOF;
CORE
  Perl        ($^V, $^O)
  Mojolicious ($Mojolicious::VERSION, $Mojolicious::CODENAME)

OPTIONAL
  EV 4.0+                 ($ev)
  IO::Socket::Socks 0.64+ ($socks)
  IO::Socket::SSL 1.94+   ($tls)
  Net::DNS::Native 0.15+  ($ndn)

EOF

  # Check latest version on CPAN
  my $latest = eval {
    $self->app->ua->max_redirects(10)->tap(sub { $_->proxy->detect })
      ->get('api.metacpan.org/v0/release/Mojolicious')->res->json->{version};
  } or return;

  my $msg = 'This version is up to date, have fun!';
  $msg = 'Thanks for testing a development release, you are awesome!'
    if $latest < $Mojolicious::VERSION;
  $msg = "You might want to update your Mojolicious to $latest!"
    if $latest > $Mojolicious::VERSION;
  say $msg;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::version - Version command

=head1 SYNOPSIS

  Usage: APPLICATION version [OPTIONS]

    mojo version

  Options:
    -h, --help   Show this summary of available options

=head1 DESCRIPTION

L<Mojolicious::Command::version> shows version information for available core
and optional modules.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::version> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $v->description;
  $v              = $v->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $v->usage;
  $v        = $v->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::version> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $v->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
