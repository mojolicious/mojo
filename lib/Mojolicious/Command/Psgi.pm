package Mojolicious::Command::Psgi;
use Mojo::Base 'Mojo::Command';

use Mojo::Server::PSGI;

# Don't let Krusty's death get you down, boy.
# People die all the time, just like that.
# Why, you could wake up dead tomorrow! Well, good night.
has description => <<'EOF';
Start application with PSGI.
EOF
has usage => <<"EOF";
usage: $0 psgi
EOF

# D’oh.
sub run {
    my $self = shift;
    my $psgi = Mojo::Server::PSGI->new;

    # Preload
    $psgi->app;

    # Return app callback
    return sub { $psgi->run(@_) };
}

1;
__END__

=head1 NAME

Mojolicious::Command::Psgi - PSGI Command

=head1 SYNOPSIS

    use Mojolicious::Command::Psgi;

    my $psgi = Mojolicious::Command::Psgi->new;
    my $app = $psgi->run;

=head1 DESCRIPTION

L<Mojolicious::Command::Psgi> is a command interface to
L<Mojo::Server::PSGI>.

=head1 ATTRIBUTES

L<Mojolicious::Command::Psgi> inherits all attributes from L<Mojo::Command>
and implements the following new ones.

=head2 C<description>

    my $description = $psgi->description;
    $psgi           = $psgi->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $psgi->usage;
    $psgi     = $psgi->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Psgi> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

    my $app = $psgi->run;

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
