package Mojolicious::Command::inflate;
use Mojo::Base 'Mojo::Command';

use Mojo::Util 'encode';

has description => "Inflate embedded files to real files.\n";
has usage       => "usage: $0 inflate\n";

# "Come on stem cells! Work your astounding scientific nonsense!"
sub run {
  my $self = shift;

  # Find all embedded files
  my $all = {};
  my $app = $self->app;
  $all = {%{$self->get_all_data($_)}, %$all}
    for @{$app->renderer->classes}, @{$app->static->classes};

  # Turn them into real files
  for my $file (keys %$all) {
    my $prefix = $file =~ /\.\w+\.\w+$/ ? 'templates' : 'public';
    my $path = $self->rel_file("$prefix/$file");
    $self->write_file($path, encode('UTF-8', $all->{$file}));
  }
}

1;
__END__

=head1 NAME

Mojolicious::Command::inflate - Inflate command

=head1 SYNOPSIS

  use Mojolicious::Command::inflate;

  my $inflate = Mojolicious::Command::inflate->new;
  $inflate->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::inflate> turns templates and static files embedded in
the C<DATA> sections of your application into real files.

=head1 ATTRIBUTES

L<Mojolicious::Command::inflate> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

  my $description = $inflate->description;
  $inflate        = $inflate->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $inflate->usage;
  $inflate  = $inflate->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::inflate> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

  $inflate->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
