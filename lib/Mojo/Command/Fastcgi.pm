# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Command::Fastcgi;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::Server::FastCGI;

__PACKAGE__->attr(description => <<'EOF');
Start application with FastCGI backend.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 fastcgi
EOF

# Oh boy! Sleep! That's when I'm a Viking!
sub run {
    Mojo::Server::FastCGI->new->run;
    return shift;
}

1;
__END__

=head1 NAME

Mojo::Command::Fastcgi - FastCGI Command

=head1 SYNOPSIS

    use Mojo::Command::Fastcgi;

    my $fastcgi = Mojo::Command::Fastcgi->new;
    $fastcgi->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Fastcgi> is a command interface to L<Mojo::Server::FastCGI>.

=head1 ATTRIBUTES

L<Mojo::Command::FastCGI> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<description>

    my $description = $fastcgi->description;
    $fastcgi        = $fastcgi->description('Foo!');

=head2 C<usage>

    my $usage = $fastcgi->usage;
    $fastcgi  = $fastcgi->usage('Foo!');

=head1 METHODS

L<Mojo::Command::Fastcgi> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

    $fastcgi = $fastcgi->run(@ARGV);

=cut
