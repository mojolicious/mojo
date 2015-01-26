package Mojolicious::Command::inflate;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Loader;
use Mojo::Util 'encode';

has description => 'Inflate embedded files to real files';
has usage => sub { shift->extract_usage };

sub run {
  my $self = shift;

  # Find all embedded files
  my %all;
  my $app    = $self->app;
  my $loader = Mojo::Loader->new;
  for my $class (@{$app->renderer->classes}, @{$app->static->classes}) {
    for my $name (keys %{$loader->data($class)}) {
      my $data = $loader->data($class, $name);
      $all{$name}
        = $loader->is_binary($class, $name) ? $data : encode('UTF-8', $data);
    }
  }

  # Turn them into real files
  for my $name (grep {/\.\w+$/} keys %all) {
    my $prefix = $name =~ /\.\w+\.\w+$/ ? 'templates' : 'public';
    $self->write_file($self->rel_file("$prefix/$name"), $all{$name});
  }
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::inflate - Inflate command

=head1 SYNOPSIS

  Usage: APPLICATION inflate

=head1 DESCRIPTION

L<Mojolicious::Command::inflate> turns templates and static files embedded in
the C<DATA> sections of your application into real files.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::inflate> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $inflate->description;
  $inflate        = $inflate->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $inflate->usage;
  $inflate  = $inflate->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::inflate> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $inflate->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
