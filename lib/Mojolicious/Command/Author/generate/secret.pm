package Mojolicious::Command::Author::generate::secret;
use Mojo::Base 'Mojolicious::Command';
use Mojo::File qw(path);
use Mojo::Util qw(urandom_urlsafe);

has description => 'Generate secret';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, $secret_file) = (shift, shift);

  $secret_file //= $self->app->secrets_file;

  my $token = urandom_urlsafe();

  print "Writing secret to $secret_file\n";

  path($secret_file)->touch->chmod(0600)->spew($token);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::Author::generate::secret - Secret generator command

=head1 SYNOPSIS

  Usage: APPLICATION generate secret [PATH]

    mojo generate secret
    mojo generate secret /path/to/secret

  Options:
    -h, --help   Show this summary of available options

=head1 DESCRIPTION

L<Mojolicious::Command::Author::generate::secret> generates a secret token for protecting session cookies

This is a core command, that means it is always enabled and its code a good example for learning to build new commands,
you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::Author::generate::secret> inherits all attributes from L<Mojolicious::Command> and implements
the following new ones.

=head2 description

  my $description = $app->description;
  $app            = $app->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $app->usage;
  $app      = $app->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Author::generate::secret> inherits all methods from L<Mojolicious::Command> and implements
the following new ones.

=head2 run

  $app->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
