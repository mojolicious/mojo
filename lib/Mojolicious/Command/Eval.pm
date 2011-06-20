package Mojolicious::Command::Eval;
use Mojo::Base 'Mojo::Command';

use Getopt::Long 'GetOptions';
use Mojo::Server;

has description => <<'EOF';
Run code against application.
EOF
has usage => <<"EOF";
usage: $0 eval [OPTIONS] CODE

  mojo eval 'print app->ua->get("/")->res->body'
  mojo eval -v 'app->home'

These options are available:
  --verbose   Print return value to STDOUT.
EOF

# "It worked!
#  Gravity normal.
#  Air pressure returning.
#  Terror replaced by cautious optimism."
sub run {
  my $self = shift;

  # Load application
  my $server = Mojo::Server->new;
  my $app    = $server->app;

  local @ARGV = @_ if @_;
  my $verbose;
  GetOptions('verbose' => sub { $verbose = 1 });
  my $code = shift @ARGV || '';

  # Run code against application
  no warnings;
  my $result = eval "package main; sub app { \$app }; $code";
  print "$result\n" if $verbose && defined $result;
  die $@ if $@;
  $result;
}

1;
__END__

=head1 NAME

Mojolicious::Command::Eval - Eval Command

=head1 SYNOPSIS

  use Mojolicious::Command::Eval;

  my $eval = Mojolicious::Command::Eval->new;
  $eval->run;

=head1 DESCRIPTION

L<Mojolicious::Command::Eval> runs code against applications.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojolicious::Command::Eval> inherits all attributes from L<Mojo::Command>
and implements the following new ones.

=head2 C<description>

  my $description = $eval->description;
  $eval           = $eval->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $eval->usage;
  $eval     = $eval->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Eval> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

  $eval->run;

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
