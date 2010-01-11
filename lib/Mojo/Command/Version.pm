# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command::Version;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo;
use Mojo::IOLoop;

__PACKAGE__->attr(description => <<'EOF');
Show versions of installed modules.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 version

EOF

# If at first you don't succeed, give up.
sub run {
    my $self = shift;

    # Mojo
    my $mojo = $Mojo::VERSION;

    # Epoll
    my $epoll = Mojo::IOLoop::EPOLL() ? $IO::Epoll::VERSION : 'not installed';

    # KQueue
    my $kqueue =
      Mojo::IOLoop::KQUEUE() ? $IO::KQueue::VERSION : 'not installed';

    # IPv6
    my $ipv6 =
      Mojo::IOLoop::IPV6() ? $IO::Socket::INET6::VERSION : 'not installed';

    # TLS
    my $tls =
      Mojo::IOLoop::TLS() ? $IO::Socket::SSL::VERSION : 'not installed';

    print <<"EOF";
CORE
  Perl ($])
  Mojo ($mojo)

OPTIONAL
  IO::Epoll         ($epoll)
  IO::KQueue        ($kqueue)
  IO::Socket::INET6 ($ipv6)
  IO::Socket::SSL   ($tls)
EOF

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Command::Version - Version Command

=head1 SYNOPSIS

    use Mojo::Command::Version;

    my $v = Mojo::Command::Version->new;
    $v->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Version> shows versions of installed modules.

=head1 ATTRIBUTES

L<Mojo::Command::Version> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<description>

    my $description = $v->description;
    $v              = $v->description('Foo!');

=head2 C<usage>

    my $usage = $v->usage;
    $v        = $v->usage('Foo!');

=head1 METHODS

L<Mojo::Command::Version> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

    $get = $v->run(@ARGV);

=cut
