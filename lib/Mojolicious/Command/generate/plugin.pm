package Mojolicious::Command::generate::plugin;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Util qw(camelize class_to_path);
use Mojolicious;

has description => "Generate Mojolicious plugin directory structure.\n";
has usage       => "usage: $0 generate plugin [NAME]\n";

sub run {
  my ($self, $name) = @_;
  $name ||= 'MyPlugin';

  # Class
  my $class = $name =~ /^[a-z]/ ? camelize($name) : $name;
  $class = "Mojolicious::Plugin::$class";
  my $app = class_to_path $class;
  $self->render_to_rel_file('class', "$name/lib/$app", $class, $name);

  # Test
  $self->render_to_rel_file('test', "$name/t/basic.t", $name);

  # Makefile
  $self->render_to_rel_file('makefile', "$name/Makefile.PL", $class, $app);
}

1;
__DATA__

@@ class
% my ($class, $name) = @_;
package <%= $class %>;
use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '0.01';

sub register {
  my ($self, $app) = @_;
}

1;
<% %>__END__

<% %>=head1 NAME

<%= $class %> - Mojolicious Plugin

<% %>=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('<%= $name %>');

  # Mojolicious::Lite
  plugin '<%= $name %>';

<% %>=head1 DESCRIPTION

L<<%= $class %>> is a L<Mojolicious> plugin.

<% %>=head1 METHODS

L<<%= $class %>> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

<% %>=head2 register

  $plugin->register(Mojolicious->new);

Register plugin in L<Mojolicious> application.

<% %>=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

<% %>=cut

@@ test
% my $name = shift;
use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

plugin '<%= $name %>';

get '/' => sub {
  my $self = shift;
  $self->render(text => 'Hello Mojo!');
};

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200)->content_is('Hello Mojo!');

done_testing();

@@ makefile
% my ($class, $path) = @_;
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => '<%= $class %>',
  VERSION_FROM => 'lib/<%= $path %>',
  AUTHOR       => 'A Good Programmer <nospam@cpan.org>',
  PREREQ_PM    => {'Mojolicious' => '<%= $Mojolicious::VERSION %>'},
  test         => {TESTS => 't/*.t'}
);

__END__
=head1 NAME

Mojolicious::Command::generate::plugin - Plugin generator command

=head1 SYNOPSIS

  use Mojolicious::Command::generate::plugin;

  my $plugin = Mojolicious::Command::generate::plugin->new;
  $plugin->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::generate::plugin> generates directory structures for
fully functional L<Mojolicious> plugins.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::plugin> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $plugin->description;
  $plugin         = $plugin->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $plugin->usage;
  $plugin   = $plugin->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::generate::plugin> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $plugin->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
