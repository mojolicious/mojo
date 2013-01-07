package Mojolicious::Command::generate;
use Mojo::Base 'Mojolicious::Commands';

has description => "Generate files and directories from templates.\n";
has hint        => <<"EOF";

See '$0 generate help GENERATOR' for more information on a specific generator.
EOF
has message => <<"EOF";
usage: $0 generate GENERATOR [OPTIONS]

These generators are currently available:
EOF
has namespaces => sub { ['Mojolicious::Command::generate'] };
has usage => "usage: $0 generate GENERATOR [OPTIONS]\n";

sub help { shift->run(@_) }

1;

=head1 NAME

Mojolicious::Command::generate - Generator command

=head1 SYNOPSIS

  use Mojolicious::Command::generate;

  my $generator = Mojolicious::Command::generate->new;
  $generator->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::generate> lists available generators.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate> inherits all attributes from
L<Mojolicious::Commands> and implements the following new ones.

=head2 description

  my $description = $generator->description;
  $generator      = $generator->description('Foo!');

Short description of this command, used for the command list.

=head2 hint

  my $hint   = $generator->hint;
  $generator = $generator->hint('Foo!');

Short hint shown after listing available generator commands.

=head2 usage

  my $usage  = $generator->usage;
  $generator = $generator->usage('Foo!');

Usage information for this command, used for the help screen.

=head2 message

  my $msg    = $generator->message;
  $generator = $generator->message('Bar!');

Short usage message shown before listing available generator commands.

=head2 namespaces

  my $namespaces = $generator->namespaces;
  $generator     = $generator->namespaces(['MyApp::Command::generate']);

Namespaces to search for available generator commands, defaults to
L<Mojolicious::Command::generate>.

=head1 METHODS

L<Mojolicious::Command::generate> inherits all methods from
L<Mojolicious::Commands> and implements the following new ones.

=head2 help

  $generator->help('app');

Print usage information for generator command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
