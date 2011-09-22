package Mojolicious::Command::generate::makefile;
use Mojo::Base 'Mojo::Command';

has description => <<'EOF';
Generate "Makefile.PL".
EOF
has usage => <<"EOF";
usage: $0 generate makefile
EOF

# "If we don't go back there and make that event happen,
#  the entire universe will be destroyed...
#  And as an environmentalist, I'm against that."
sub run {
  my $self  = shift;
  my $class = $ENV{MOJO_APP} || 'MyApp';
  my $path  = $self->class_to_path($class);
  my $name  = $self->class_to_file($class);
  $self->render_to_rel_file('makefile', 'Makefile.PL', $class, $path, $name);
}

1;
__DATA__

@@ makefile
% my ($class, $path, $name) = @_;
#!/usr/bin/env perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => '<%= $class %>',
  VERSION_FROM => 'lib/<%= $path %>',
  AUTHOR       => 'A Good Programmer <nospam@cpan.org>',
  EXE_FILES    => ['script/<%= $name %>'],
  PREREQ_PM    => {'Mojolicious' => '1.90'},
  test         => {TESTS => 't/*.t'}
);

__END__
=head1 NAME

Mojolicious::Command::generate::makefile - Makefile generator command

=head1 SYNOPSIS

  use Mojolicious::Command::generate::makefile;

  my $makefile = Mojolicious::Command::generate::makefile->new;
  $makefile->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::generate::makefile> is a makefile generator.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::makefile> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

  my $description = $makefile->description;
  $makefile       = $makefile->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $makefile->usage;
  $makefile = $makefile->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::generate::makefile> inherits all methods from
L<Mojo::Command> and implements the following new ones.

=head2 C<run>

  $makefile->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
