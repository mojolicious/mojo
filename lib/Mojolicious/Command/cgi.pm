package Mojolicious::Command::cgi;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::Server::CGI;

has description => 'Start application with CGI';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;
  GetOptionsFromArray \@args, nph => \(my $nph = 0);
  Mojo::Server::CGI->new(app => $self->app, nph => $nph)->run;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::cgi - CGI command

=head1 SYNOPSIS

  Usage: APPLICATION cgi [OPTIONS]

  Options:
    --nph   Enable non-parsed-header mode

=head1 DESCRIPTION

L<Mojolicious::Command::cgi> starts applications with L<Mojo::Server::CGI>
backend.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::cgi> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $cgi->description;
  $cgi            = $cgi->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $cgi->usage;
  $cgi      = $cgi->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::cgi> inherits all methods from L<Mojolicious::Command>
and implements the following new ones.

=head2 run

  $cgi->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
