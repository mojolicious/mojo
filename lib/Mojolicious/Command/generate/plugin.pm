package Mojolicious::Command::generate::plugin;
use Mojo::Base 'Mojo::Command';

use Mojo::Util 'camelize';

# "You know Santa may have killed Scruffy, but he makes a good point."
has description => "Generate Mojolicious plugin directory structure.\n";
has usage       => "usage: $0 generate plugin [NAME]\n";

# "There we were in the park when suddenly some old lady says I stole her
#  purse.
#  I chucked the professor at her but she kept coming.
#  So I had to hit her with this purse I found."
sub run {
  my ($self, $name) = @_;
  $name ||= 'MyPlugin';

  # Class
  my $class = $name =~ /^[a-z]/ ? camelize($name) : $name;
  $class = "Mojolicious::Plugin::$class";
  my $app = $self->class_to_path($class);
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

<% %>=head2 C<register>

  $plugin->register;

Register plugin in L<Mojolicious> application.

<% %>=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

<% %>=cut

@@ test
% my $name = shift;
use Mojo::Base -strict;

use Test::More tests => 3;

use Mojolicious::Lite;
use Test::Mojo;

plugin '<%= $name %>';

get '/' => sub {
  my $self = shift;
  $self->render_text('Hello Mojo!');
};

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200)->content_is('Hello Mojo!');

@@ makefile
% my ($class, $path) = @_;
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => '<%= $class %>',
  VERSION_FROM => 'lib/<%= $path %>',
  AUTHOR       => 'A Good Programmer <nospam@cpan.org>',
  PREREQ_PM    => {'Mojolicious' => '2.60'},
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

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::plugin> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

  my $description = $plugin->description;
  $plugin         = $plugin->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $plugin->usage;
  $plugin   = $plugin->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::generate::plugin> inherits all methods from
L<Mojo::Command> and implements the following new ones.

=head2 C<run>

  $plugin->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
