package Mojolicious::Command::generate::lite_app;
use Mojo::Base 'Mojo::Command';

has description => <<'EOF';
Generate Mojolicious::Lite application.
EOF
has usage => <<"EOF";
usage: $0 generate lite_app [NAME]
EOF

# "As a scientist,
#  I can assure you that we did in fact evolve from filthy monkey-men."
sub run {
  my ($self, $name) = @_;
  $name ||= 'myapp.pl';
  $self->render_to_rel_file('liteapp', $name);
  $self->chmod_file($name, 0744);
}

1;
__DATA__

@@ liteapp
% my $class = shift;
#!/usr/bin/env perl
use Mojolicious::Lite;

# Documentation browser under "/perldoc" (this plugin requires Perl 5.10)
plugin 'PODRenderer';

get '/welcome' => sub {
  my $self = shift;
  $self->render('index');
};

app->start;
<% %>__DATA__

<% %>@@ index.html.ep
%% layout 'default';
%% title 'Welcome';
Welcome to Mojolicious!

<% %>@@ layouts/default.html.ep
<!doctype html><html>
  <head><title><%%= title %></title></head>
  <body><%%= content %></body>
</html>

__END__
=head1 NAME

Mojolicious::Command::generate::lite_app - Lite App Generator Command

=head1 SYNOPSIS

  use Mojolicious::Command::generate::lite_app;

  my $app = Mojolicious::Command::generate::lite_app->new;
  $app->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::generate::lite_app> is a application generator.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::lite_app> inherits all attributes from
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

L<Mojolicious::Command::generate::lite_app> inherits all methods from
L<Mojo::Command> and implements the following new ones.

=head2 C<run>

  $app->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
