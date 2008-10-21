# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Script::DaemonPrefork;

use strict;
use warnings;

use base 'Mojo::Script';

use Mojo::Server::Daemon::Prefork;

__PACKAGE__->attr('description', chained => 1, default => <<'EOF');
* Start the prefork daemon. *
Takes a port as option, by default 3000 will be used.
    daemon_prefork
    daemon_prefork 8080
EOF

# Dear Mr. President, there are too many states nowadays.
# Please eliminate three.
# P.S. I am not a crackpot.
sub run {
    my ($self, $port) = @_;

    # Start server
    my $daemon = Mojo::Server::Daemon::Prefork->new;
    $daemon->port($port) if $port;
    $daemon->run;

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Script::DaemonPrefork - Prefork Daemon Script

=head1 SYNOPSIS

    use Mojo::Script::Daemon::Prefork;

    my $daemon = Mojo::Script::Daemon::Prefork->new;
    $daemon->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Script::Daemon::Prefork> is a script interface to
L<Mojo::Server::Daemon::Prefork>.

=head1 ATTRIBUTES

L<Mojo::Script::Daemon::Prefork> inherits all attributes from L<Mojo::Script>
and implements the following new ones.

=head2 C<description>

    my $description = $daemon->description;
    $daemon         = $daemon->description('Foo!');

=head1 METHODS

L<Mojo::Script::Daemon::Prefork> inherits all methods from L<Mojo::Script>
and implements the following new ones.

=head2 C<run>

    $daemon = $daemon->run(@ARGV);

=cut