package Mojolicious::Command::Hypnotoad;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::Server;

__PACKAGE__->attr(description => <<'EOF');
Start application with Hypnotoad.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 hypnotoad
EOF

# This calls for a party, baby.
# I'm ordering 100 kegs, 100 hookers and 100 Elvis impersonators that aren't
# above a little hooking should the occasion arise.
sub run { return Mojo::Server->new->app }

1;
__END__

=head1 NAME

Mojolicious::Command::Hypnotoad - Hypnotoad Command

=head1 SYNOPSIS

    use Mojolicious::Command::Hypnotoad;

    my $toad = Mojolicious::Command::Hypnotoad->new;
    $toad->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Hypnotoad> is a command interface to
L<Mojo::Server::Hypnotoad>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojolicious::Command::Hypnotoad> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

    my $description = $toad->description;
    $toad           = $toad->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $toad->usage;
    $toad     = $toad->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Hypnotoad> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

    $toad = $toad->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
