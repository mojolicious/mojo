package Mojolicious::Command::generate::app;
use Mojo::Base 'Mojo::Command';

has description => "Generate Mojolicious application directory structure.\n";
has usage       => "usage: $0 generate app [CLASS]\n";

# "I say, you've damaged our servants quarters... and our servants."
sub run {
  my ($self, $class) = @_;
  $class ||= 'MyMojoliciousApp';

  # Prevent bad applications
  die <<EOF unless $class =~ /^[A-Z](?:\w|\:\:)+$/;
Your application name has to be a well formed (camel case) Perl module name
like "MyApp".
EOF

  # Script
  my $name = $self->class_to_file($class);
  $self->render_to_rel_file('mojo', "$name/script/$name", $class);
  $self->chmod_file("$name/script/$name", 0744);

  # Appclass
  my $app = $self->class_to_path($class);
  $self->render_to_rel_file('appclass', "$name/lib/$app", $class);

  # Controller
  my $controller = "${class}::Example";
  my $path       = $self->class_to_path($controller);
  $self->render_to_rel_file('controller', "$name/lib/$path", $controller);

  # Test
  $self->render_to_rel_file('test', "$name/t/basic.t", $class);

  # Log
  $self->create_rel_dir("$name/log");

  # Static
  $self->render_to_rel_file('static', "$name/public/index.html");

  # Layout and Templates
  $self->render_to_rel_file('layout',
    "$name/templates/layouts/default.html.ep");
  $self->render_to_rel_file('welcome',
    "$name/templates/example/welcome.html.ep");
}

1;
__DATA__

@@ mojo
% my $class = shift;
#!/usr/bin/env perl
use Mojo::Base -strict;

use File::Basename 'dirname';
use File::Spec::Functions qw/catdir splitdir/;

# Source directory has precedence
my @base = (splitdir(dirname(__FILE__)), '..');
my $lib = join('/', @base, 'lib');
-e catdir(@base, 't') ? unshift(@INC, $lib) : push(@INC, $lib);

# Check if Mojolicious is installed;
die <<EOF unless eval 'use Mojolicious::Commands; 1';
It looks like you don't have the Mojolicious framework installed.
Please visit http://mojolicio.us for detailed installation instructions.

EOF

# Application
$ENV{MOJO_APP} ||= '<%= $class %>';

# Start commands
Mojolicious::Commands->start;

@@ appclass
% my $class = shift;
package <%= $class %>;
use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
  my $self = shift;

  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer');

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->route('/')->to('example#welcome');
}

1;

@@ controller
% my $class = shift;
package <%= $class %>;
use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub welcome {
  my $self = shift;

  # Render template "example/welcome.html.ep" with message
  $self->render(
    message => 'Welcome to the Mojolicious real-time web framework!');
}

1;

@@ static
<!DOCTYPE html>
<html>
  <head>
    <title>Welcome to the Mojolicious real-time web framework!</title>
  </head>
  <body>
    <h2>Welcome to the Mojolicious real-time web framework!</h2>
    This is the static document "public/index.html",
    <a href="/">click here</a> to get back to the start.
  </body>
</html>

@@ test
% my $class = shift;
use Mojo::Base -strict;

use Test::More tests => 3;
use Test::Mojo;

my $t = Test::Mojo->new('<%= $class %>');
$t->get_ok('/')->status_is(200)->content_like(qr/Mojolicious/i);

@@ layout
<!DOCTYPE html>
<html>
  <head><title><%%= title %></title></head>
  <body><%%= content %></body>
</html>

@@ welcome
%% layout 'default';
%% title 'Welcome';
<h2><%%= $message %></h2>
This page was generated from the template
"templates/example/welcome.html.ep" and the layout
"templates/layouts/default.html.ep",
<a href="<%%== url_for %>">click here</a>
to reload the page or
<a href="/index.html">here</a>
to move forward to a static page.

__END__
=head1 NAME

Mojolicious::Command::generate::app - App generator command

=head1 SYNOPSIS

  use Mojolicious::Command::generate::app;

  my $app = Mojolicious::Command::generate::app->new;
  $app->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::generate::app> is an application generator.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::app> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

  my $description = $app->description;
  $app            = $app->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $app->usage;
  $app      = $app->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::generate::app> inherits all methods from
L<Mojo::Command> and implements the following new ones.

=head2 C<run>

  $app->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
