package Mojolicious::Command::eval;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);

has description => "Run code against application.\n";
has usage       => <<"EOF";
usage: $0 eval [OPTIONS] CODE

  mojo eval 'say app->ua->get("/")->res->body'
  mojo eval -v 'app->home'

These options are available:
  -v, --verbose   Print return value to STDOUT.
EOF

sub run {
  my ($self, @args) = @_;

  GetOptionsFromArray \@args, 'v|verbose' => \my $verbose;
  my $code = shift @args || '';

  # Run code against application
  my $app = $self->app;
  no warnings;
  my $result = eval "package main; sub app { \$app }; $code";
  say $result if $verbose && defined $result;
  return $@ ? die $@ : $result;
}

1;

=head1 NAME

Mojolicious::Command::eval - Eval command

=head1 SYNOPSIS

  use Mojolicious::Command::eval;

  my $eval = Mojolicious::Command::eval->new;
  $eval->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::eval> runs code against applications.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::eval> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $eval->description;
  $eval           = $eval->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $eval->usage;
  $eval     = $eval->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::eval> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $eval->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
