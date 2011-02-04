package Mojolicious::Command::Cgi;
use Mojo::Base 'Mojo::Command';

use Mojo::Server::CGI;

use Getopt::Long 'GetOptions';

has description => <<'EOF';
Start application with CGI.
EOF
has usage => <<"EOF";
usage: $0 cgi [OPTIONS]

These options are available:
  --nph   Enable non-parsed-header mode.
EOF

# "Hi, Super Nintendo Chalmers!"
sub run {
  my $self = shift;
  my $cgi  = Mojo::Server::CGI->new;

  # Options
  local @ARGV = @_ if @_;
  GetOptions(nph => sub { $cgi->nph(1) });

  # Run
  $cgi->run;

  return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Command::Cgi - CGI Command

=head1 SYNOPSIS

  use Mojolicious::Command::CGI;

  my $cgi = Mojolicious::Command::CGI->new;
  $cgi->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Cgi> is a command interface to L<Mojo::Server::CGI>.

=head1 ATTRIBUTES

L<Mojolicious::Command::Cgi> inherits all attributes from L<Mojo::Command>
and implements the following new ones.

=head2 C<description>

  my $description = $cgi->description;
  $cgi            = $cgi->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $cgi->usage;
  $cgi      = $cgi->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Cgi> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

  $cgi = $cgi->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
