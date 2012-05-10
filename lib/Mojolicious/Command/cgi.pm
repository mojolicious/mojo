package Mojolicious::Command::cgi;
use Mojo::Base 'Mojo::Command';

use Getopt::Long qw(GetOptions :config no_auto_abbrev no_ignore_case);
use Mojo::Server::CGI;

has description => "Start application with CGI.\n";
has usage       => <<"EOF";
usage: $0 cgi [OPTIONS]

These options are available:
  --nph   Enable non-parsed-header mode.
EOF

# "Fire all weapons and open a hailing frequency for my victory yodel."
sub run {
  my $self = shift;
  my $cgi  = Mojo::Server::CGI->new;
  local @ARGV = @_;
  GetOptions(nph => sub { $cgi->nph(1) });
  $cgi->run;
}

1;

=head1 NAME

Mojolicious::Command::cgi - CGI command

=head1 SYNOPSIS

  use Mojolicious::Command::CGI;

  my $cgi = Mojolicious::Command::CGI->new;
  $cgi->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::cgi> starts applications with L<Mojo::Server::CGI>
backend.

=head1 ATTRIBUTES

L<Mojolicious::Command::cgi> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<description>

  my $description = $cgi->description;
  $cgi            = $cgi->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $cgi->usage;
  $cgi      = $cgi->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::cgi> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

  $cgi->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
