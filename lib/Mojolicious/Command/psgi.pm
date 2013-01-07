package Mojolicious::Command::psgi;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Server::PSGI;

has description => "Start application with PSGI.\n";
has usage       => "usage: $0 psgi\n";

sub run { Mojo::Server::PSGI->new(app => shift->app)->to_psgi_app }

1;

=head1 NAME

Mojolicious::Command::psgi - PSGI command

=head1 SYNOPSIS

  use Mojolicious::Command::psgi;

  my $psgi = Mojolicious::Command::psgi->new;
  my $app  = $psgi->run;

=head1 DESCRIPTION

L<Mojolicious::Command::psgi> starts applications with L<Mojo::Server::PSGI>
backend.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::psgi> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $psgi->description;
  $psgi           = $psgi->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $psgi->usage;
  $psgi     = $psgi->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::psgi> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  my $app = $psgi->run;

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
