package Mojolicious::Command::Author::generate::dockerfile;
use Mojo::Base 'Mojolicious::Command';

use Mojo::File qw(path);

has description => 'Generate "Dockerfile"';
has usage       => sub { shift->extract_usage };

sub run {
  my $self = shift;
  my $name = $self->app->moniker;
  my $exe  = $ENV{MOJO_EXE} ? path($ENV{MOJO_EXE})->to_rel($self->app->home)->to_string : "script/$name";
  $self->render_to_rel_file('dockerfile', 'Dockerfile', {name => $name, cmd => "./$exe prefork"});
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::Author::generate::dockerfile - Dockerfile generator command

=head1 SYNOPSIS

  Usage: APPLICATION generate dockerfile [OPTIONS]

    ./myapp.pl generate dockerfile
    ./script/my_app generate dockerfile

  Options:
    -h, --help   Show this summary of available options

=head1 DESCRIPTION

L<Mojolicious::Command::Author::generate::dockerfile> generates C<Dockerfile> for applications.

This is a core command, that means it is always enabled and its code a good example for learning to build new commands,
you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::Author::generate::dockerfile> inherits all attributes from L<Mojolicious::Command> and
implements the following new ones.

=head2 description

  my $description = $dockerfile->description;
  $dockerfile     = $dockerfile->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage   = $dockerfile->usage;
  $dockerfile = $dockerfile->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Author::generate::dockerfile> inherits all methods from L<Mojolicious::Command> and implements
the following new ones.

=head2 run

  $dockerfile->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut

__DATA__

@@ dockerfile
FROM perl
WORKDIR /opt/<%= $name %>
COPY . .
RUN cpanm --installdeps -n .
EXPOSE 3000
CMD <%= $cmd %>
