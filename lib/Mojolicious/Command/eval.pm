package Mojolicious::Command::eval;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Promise;
use Mojo::Util qw(getopt);

has description => 'Run code against application';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  die $self->usage unless getopt \@args, 'v|verbose' => \my $v1, 'V' => \my $v2;
  my $code = shift @args || '';

  # Run code against application
  my $app    = $self->app;
  my $result = eval "package main; no warnings 'redefine'; sub app; local *app = sub { \$app }; $code";
  die $@ if $@;

  # Handle promises
  my $err;
  Mojo::Promise->resolve($result)->then(sub { $result = shift }, sub { $err = shift })->wait;
  die $err if $err;

  return $result unless defined $result && ($v1 || $v2);
  $v2 ? print($app->dumper($result)) : say $result;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::eval - Eval command

=head1 SYNOPSIS

  Usage: APPLICATION eval [OPTIONS] CODE

    ./myapp.pl eval 'say app->ua->get("/")->result->body'
    ./myapp.pl eval 'say for sort keys %{app->renderer->helpers}'
    ./myapp.pl eval -v 'app->home'
    ./myapp.pl eval -V 'app->renderer->paths'

  Options:
    -h, --help          Show this summary of available options
        --home <path>   Path to home directory of your application, defaults to
                        the value of MOJO_HOME or auto-detection
    -m, --mode <name>   Operating mode for your application, defaults to the
                        value of MOJO_MODE/PLACK_ENV or "development"
    -v, --verbose       Print return value to STDOUT
    -V                  Print returned data structure to STDOUT

=head1 DESCRIPTION

L<Mojolicious::Command::eval> runs code against applications. If the result is a promise (then-able), it will wait
until the promise is fulfilled or rejected and the result is returned.

This is a core command, that means it is always enabled and its code a good example for learning to build new commands,
you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::eval> inherits all attributes from L<Mojolicious::Command> and implements the following new
ones.

=head2 description

  my $description = $eval->description;
  $eval           = $eval->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $eval->usage;
  $eval     = $eval->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::eval> inherits all methods from L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $eval->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
