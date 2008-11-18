# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Script::Daemon;

use strict;
use warnings;

use base 'Mojo::Script';

use Mojo::Server::Daemon;

__PACKAGE__->attr(description => (chained => 1, default => <<'EOF'));
* Start the daemon. *
Takes a port as option, by default 3000 will be used.
    daemon
    daemon 8080
EOF


# This is the worst thing you've ever done.
# You say that so often that it lost its meaning.
sub run {
    my ($self, $port) = @_;

    # Start server
    $port ||= 3000;
    my $daemon = Mojo::Server::Daemon->new;
    $daemon->port($port);
    $daemon->run;

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Script::Daemon - Daemon Script

=head1 SYNOPSIS

    use Mojo::Script::Daemon;

    my $daemon = Mojo::Script::Daemon->new;
    $daemon->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Script::Daemon> is a script interface to
L<Mojo::Server::Daemon>.

=head1 ATTRIBUTES

L<Mojo::Script::Daemon> inherits all attributes from L<Mojo::Script> and
implements the following new ones.

=head2 C<description>

    my $description = $daemon->description;
    $daemon         = $daemon->description('Foo!');

=head1 METHODS

L<Mojo::Script::Daemon> inherits all methods from L<Mojo::Script> and
implements the following new ones.

=head2 C<run>

    $daemon = $daemon->run(@ARGV);

=cut
