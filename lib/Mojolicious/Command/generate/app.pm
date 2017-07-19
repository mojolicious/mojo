package Mojolicious::Command::generate::app;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Util qw(class_to_file class_to_path decamelize);
use Mojo::Path;
use Mojo::File;

has description => 'Generate Mojolicious application directory structure';
has usage => sub { shift->extract_usage };

has locations => sub { { script => 'script',
                         class  => 'lib',
                         test   => 't',
                         static => 'public',
                         controller => 'Example',
                         action => 'welcome',
                     } };

sub run {
  my ($self, $class) = @_;
  $class ||= 'MyApp';

  # Prevent bad applications
  die <<EOF unless $class =~ /^[A-Z](?:\w|::)+$/;
Your application name has to be a well formed (CamelCase) Perl module name
like "MyApp".
EOF

  # Script
  my $name = class_to_file $class;
  my $script_name = Mojo::File->new($name, $self->locations->{script})->child($name);
  $self->render_to_rel_file('mojo',
                            $script_name,
                            $class, $self->locations->{class});
  $self->chmod_rel_file($script_name, 0744);

  # Config file (using the default moniker)
  my $config_base = decamelize $class . '.conf';
  $self->render_to_rel_file('config',
                            Mojo::File->new($name)->child(${config_base}),
                            $config_base);

  # Application class
  my $controller = $self->locations->{controller};
  my $action     = $self->locations->{action};
  $self->render_to_rel_file('appclass',
                            Mojo::File->new($name, $self->locations->{class}, class_to_path $class),
                            # NOTE: Mojo::Home currently requires
                            # application class in 'lib' or 'blib'
                            $class, $config_base, decamelize($controller), $action);

  # Controller
  my $controller_class = "${class}::Controller::${controller}";
  $self->render_to_rel_file('controller',
                            Mojo::File->new($name,  $self->locations->{class}, class_to_path $controller_class),
                            $controller_class, decamelize($controller), $action);

  # Test
  $self->render_to_rel_file('test',
                            Mojo::File->new($name, $self->locations->{test})->child('basic.t'),
                            $class);

  # Static file
  $self->render_to_rel_file('static',
                            Mojo::File->new($name, $self->locations->{static})->child('index.html'));

  # Templates
  $self->render_to_rel_file('layout',
                            Mojo::File->new($name, 'templates', 'layouts')->child('default.html.ep'));
  $self->render_to_rel_file('welcome',
                            Mojo::File->new($name, 'templates', decamelize $controller)->child("${action}.html.ep"),
                            decamelize($controller), $action);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::generate::app - App generator command

=head1 SYNOPSIS

  Usage: APPLICATION generate app [OPTIONS] [NAME]

    mojo generate app
    mojo generate app TestApp

  Options:
    -h, --help   Show this summary of available options

=head1 DESCRIPTION

L<Mojolicious::Command::generate::app> generates application directory
structures for fully functional L<Mojolicious> applications.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::app> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $app->description;
  $app            = $app->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $app->usage;
  $app      = $app->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::generate::app> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $app->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut

__DATA__

@@ mojo
% my ($class, $lib) = @_;
#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
BEGIN { unshift @INC, "$FindBin::Bin/../<%= $lib %>" }
use Mojolicious::Commands;

# Start command line interface for application
Mojolicious::Commands->start_app('<%= $class %>');

@@ appclass
% my ($class, $config, $controller, $action) = @_;
package <%= $class %>;
use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
  my $self = shift;

  # Load configuration from hash returned by .conf file
  my $config = $self->plugin('Config' => {file => "<%= $config %>"});

  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer') if $config->{perldoc};

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')->to('<%= $controller %>#<%= $action %>');
}

1;

@@ controller
% my ($class, $controller, $action) = @_;
package <%= $class %>;
use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub <%= $action %> {
  my $self = shift;

  # Render template "<%= $controller %>/<%= $action %>.html.ep" with message
  $self->render(msg => 'Welcome to the Mojolicious real-time web framework!');
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

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('<%= $class %>');
# Test controller
$t->get_ok('/')->status_is(200)->content_like(qr/Mojolicious/i);
# ...and static file
$t->get_ok('/index.html')->status_is(200)->content_like(qr/Welcome to the/i);

done_testing();

@@ layout
<!DOCTYPE html>
<html>
  <head><title><%%= title %></title></head>
  <body><%%= content %></body>
</html>

@@ welcome
%% layout 'default';
%% title 'Welcome';
% my ($controller, $action) = @_;
<h2><%%= $msg %></h2>
<p>
  This page was generated from the template "templates/<%= $controller %>/<%= $action %>.html.ep"
  and the layout "templates/layouts/default.html.ep",
  <%%= link_to 'click here' => url_for %> to reload the page or
  <%%= link_to 'here' => '/index.html' %> to move forward to a static page.
  %% if (config 'perldoc') {
    To learn more, you can also browse through the documentation
    <%%= link_to 'here' => '/perldoc' %>.
  %% }
</p>

@@ config
% use Mojo::Util qw(sha1_sum steady_time);
{
  perldoc => 1,
  secrets => ['<%= sha1_sum $$ . steady_time . rand  %>']
}
