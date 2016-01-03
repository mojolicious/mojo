package Mojolicious::Command::generate::plugin;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Util qw(camelize class_to_path);
use Mojolicious;

has description => 'Generate Mojolicious plugin directory structure';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, $name) = @_;
  $name ||= 'MyPlugin';

  # Class
  my $class = $name =~ /^[a-z]/ ? camelize $name : $name;
  $class = "Mojolicious::Plugin::$class";
  my $app = class_to_path $class;
  my $dir = join '-', split('::', $class);
  $self->render_to_rel_file('class', "$dir/lib/$app", $class, $name);

  # Test
  $self->render_to_rel_file('test', "$dir/t/basic.t", $name);

  # Makefile
  $self->render_to_rel_file('makefile', "$dir/Makefile.PL", $class, $app);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::generate::plugin - Plugin generator command

=head1 SYNOPSIS

  Usage: APPLICATION generate plugin [OPTIONS] [NAME]

    mojo generate plugin
    mojo generate plugin TestPlugin

  Options:
    -h, --help   Show this summary of available options

=head1 DESCRIPTION

L<Mojolicious::Command::generate::plugin> generates directory structures for
fully functional L<Mojolicious> plugins.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::plugin> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $plugin->description;
  $plugin         = $plugin->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $plugin->usage;
  $plugin   = $plugin->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::generate::plugin> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $plugin->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut

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

<% %>=encoding utf8

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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

<% %>=cut

@@ test
% my $name = shift;
use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

plugin '<%= $name %>';

get '/' => sub {
  my $c = shift;
  $c->render(text => 'Hello Mojo!');
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
