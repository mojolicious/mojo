# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Script::Cgi;

use strict;
use warnings;

use base 'Mojo::Script';

use Mojo::Server::CGI;

__PACKAGE__->attr(description => (default => <<'EOF'));
* Start the cgi script. *
Takes no options.
    cgi
EOF

# Hi, Super Nintendo Chalmers!
sub run {
    Mojo::Server::CGI->new->run;
    return shift;
}

1;
__END__

=head1 NAME

Mojo::Script::Cgi - CGI Script

=head1 SYNOPSIS

    use Mojo::Script::CGI;

    my $cgi = Mojo::Script::CGI->new;
    $cgi->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Script::Cgi> is a script interface to L<Mojo::Server::CGI>.

=head1 ATTRIBUTES

L<Mojo::Script::Cgi> inherits all attributes from L<Mojo::Script> and
implements the following new ones.

=head2 C<description>

    my $description = $cgi->description;
    $cgi            = $cgi->description('Foo!');

=head1 METHODS

L<Mojo::Script::Cgi> inherits all methods from L<Mojo::Script> and implements
the following new ones.

=head2 C<run>

    $cgi = $cgi->run(@ARGV);

=cut
