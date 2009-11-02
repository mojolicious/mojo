# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Command::Get;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::Client;
use Mojo::Transaction::Single;

__PACKAGE__->attr(description => <<'EOF');
Get file from URL.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 get [URL]
EOF

# I hope this has taught you kids a lesson: kids never learn.
sub run {
    my ($self, $url) = @_;

    # URL
    die $self->usage unless $url;

    # Client
    my $client = Mojo::Client->new;

    # Transaction
    my $tx = Mojo::Transaction::Single->new;
    $tx->req->method('GET');
    $tx->req->url->parse($url);
    $tx->res->body(sub { print $_[1] });

    # Request
    $client->process($tx);

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Command::Get - Get Command

=head1 SYNOPSIS

    use Mojo::Command::Get;

    my $get = Mojo::Command::Get->new;
    $get->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Get> is a command interface to L<Mojo::Client>.

=head1 ATTRIBUTES

L<Mojo::Command::Get> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<description>

    my $description = $get->description;
    $get            = $get->description('Foo!');

=head2 C<usage>

    my $usage = $get->usage;
    $get      = $get->usage('Foo!');

=head1 METHODS

L<Mojo::Command::Get> inherits all methods from L<Mojo::Command> and implements
the following new ones.

=head2 C<run>

    $get = $get->run(@ARGV);

=cut
