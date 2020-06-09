package Mojolicious::Command::Author::inflate;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Loader qw(data_section file_is_binary);
use Mojo::Util qw(encode);

has description => 'Inflate embedded files to real files';
has usage       => sub { shift->extract_usage };

sub run {
  my $self = shift;

  # Find all embedded files
  my %all;
  my $app = $self->app;
  for my $class (@{$app->renderer->classes}, @{$app->static->classes}) {
    for my $name (keys %{data_section $class}) {
      my $data = data_section $class, $name;
      $data = encode 'UTF-8', $data unless file_is_binary $class, $name;
      $all{$name} = $data;
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

Mojolicious::Command::Author::inflate - Inflate command

=head1 SYNOPSIS

  Usage: APPLICATION inflate [OPTIONS]

    ./myapp.pl inflate

  Options:
    -h, --help          Show this summary of available options
        --home <path>   Path to home directory of your application, defaults to
                        the value of MOJO_HOME or auto-detection
    -m, --mode <name>   Operating mode for your application, defaults to the
                        value of MOJO_MODE/PLACK_ENV or "development"

=head1 DESCRIPTION

L<Mojolicious::Command::Author::inflate> turns templates and static files embedded in the C<DATA> sections of your
application into real files.

This is a core command, that means it is always enabled and its code a good example for learning to build new commands,
you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::Author::inflate> inherits all attributes from L<Mojolicious::Command> and implements the
following new ones.

=head2 description

  my $description = $inflate->description;
  $inflate        = $inflate->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $inflate->usage;
  $inflate  = $inflate->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Author::inflate> inherits all methods from L<Mojolicious::Command> and implements the following
new ones.

=head2 run

  $inflate->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
