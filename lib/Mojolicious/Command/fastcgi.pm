package Mojolicious::Command::fastcgi;
use Mojo::Base 'Mojo::Command';

use Mojo::Server::FastCGI;

has description => <<'EOF';
Start application with FastCGI.
EOF
has usage => <<"EOF";
usage: $0 fastcgi
EOF

# "Interesting... Oh no wait, the other thing, tedious."
sub run { Mojo::Server::FastCGI->new->run }

1;
__END__

=head1 NAME

Mojolicious::Command::fastcgi - FastCGI Command

=head1 SYNOPSIS

  use Mojolicious::Command::fastcgi;

  my $fastcgi = Mojolicious::Command::fastcgi->new;
  $fastcgi->run;

=head1 DESCRIPTION

L<Mojolicious::Command::fastcgi> is a command interface to
L<Mojo::Server::FastCGI>.

=head1 ATTRIBUTES

L<Mojolicious::Command::FastCGI> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

  my $description = $fastcgi->description;
  $fastcgi        = $fastcgi->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $fastcgi->usage;
  $fastcgi  = $fastcgi->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::fastcgi> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

  $fastcgi->run;

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
