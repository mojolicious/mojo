package Mojolicious::Command::psgi;
use Mojo::Base 'Mojo::Command';

use Mojo::Server::PSGI;

has description => <<'EOF';
Start application with PSGI.
EOF
has usage => <<"EOF";
usage: $0 psgi
EOF

# "In the end it was not guns or bombs that defeated the aliens,
#  but that humblest of all God's creatures... the Tyrannosaurus Rex."
sub run {
  my $self = shift;
  my $psgi = Mojo::Server::PSGI->new;

  # Preload
  $psgi->app;

  # Return app callback
  return sub { $psgi->run(@_) };
}

1;
__END__

=head1 NAME

Mojolicious::Command::psgi - PSGI Command

=head1 SYNOPSIS

  use Mojolicious::Command::psgi;

  my $psgi = Mojolicious::Command::psgi->new;
  my $app = $psgi->run;

=head1 DESCRIPTION

L<Mojolicious::Command::psgi> is a command interface to
L<Mojo::Server::PSGI>.

=head1 ATTRIBUTES

L<Mojolicious::Command::psgi> inherits all attributes from L<Mojo::Command>
and implements the following new ones.

=head2 C<description>

  my $description = $psgi->description;
  $psgi           = $psgi->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $psgi->usage;
  $psgi     = $psgi->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::psgi> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

  my $app = $psgi->run;

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
