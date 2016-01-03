package Mojolicious::Command::generate::lite_app;
use Mojo::Base 'Mojolicious::Command';

has description => 'Generate Mojolicious::Lite application';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, $name) = @_;
  $name ||= 'myapp.pl';
  $self->render_to_rel_file('liteapp', $name);
  $self->chmod_rel_file($name, 0744);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::generate::lite_app - Lite app generator command

=head1 SYNOPSIS

  Usage: APPLICATION generate lite_app [OPTIONS] [NAME]

    mojo generate lite_app
    mojo generate lite_app foo.pl

  Options:
    -h, --help   Show this summary of available options

=head1 DESCRIPTION

L<Mojolicious::Command::generate::lite_app> generate fully functional
L<Mojolicious::Lite> applications.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::lite_app> inherits all attributes from
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

L<Mojolicious::Command::generate::lite_app> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $app->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut

__DATA__

@@ liteapp
#!/usr/bin/env perl
use Mojolicious::Lite;

# Documentation browser under "/perldoc"
plugin 'PODRenderer';

get '/' => sub {
  my $c = shift;
  $c->render(template => 'index');
};

app->start;
<% %>__DATA__

<% %>@@ index.html.ep
%% layout 'default';
%% title 'Welcome';
<h1>Welcome to the Mojolicious real-time web framework!</h1>
To learn more, you can browse through the documentation
<%%= link_to 'here' => '/perldoc' %>.

<% %>@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%%= title %></title></head>
  <body><%%= content %></body>
</html>
