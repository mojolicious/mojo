# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Command::Cgi;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::Server::CGI;

use Getopt::Long 'GetOptions';

__PACKAGE__->attr(description => <<'EOF');
Start application with CGI backend.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 cgi [OPTIONS]

These options are available:
  --nph    Enable non-parsed-header mode.
EOF

# Hi, Super Nintendo Chalmers!
sub run {
    my $self = shift;
    my $cgi  = Mojo::Server::CGI->new;

    # Options
    @ARGV = @_ if @_;
    GetOptions('nph' => sub { $cgi->nph(1) });

    # Run
    $cgi->run;

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Command::Cgi - CGI Command

=head1 SYNOPSIS

    use Mojo::Command::CGI;

    my $cgi = Mojo::Command::CGI->new;
    $cgi->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Cgi> is a command interface to L<Mojo::Server::CGI>.

=head1 ATTRIBUTES

L<Mojo::Command::Cgi> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<description>

    my $description = $cgi->description;
    $cgi            = $cgi->description('Foo!');

=head2 C<usage>

    my $usage = $cgi->usage;
    $cgi      = $cgi->usage('Foo!');

=head1 METHODS

L<Mojo::Command::Cgi> inherits all methods from L<Mojo::Command> and implements
the following new ones.

=head2 C<run>

    $cgi = $cgi->run(@ARGV);

=cut
