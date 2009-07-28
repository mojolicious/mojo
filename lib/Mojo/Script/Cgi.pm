# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Script::Cgi;

use strict;
use warnings;

use base 'Mojo::Script';

use Mojo::Server::CGI;

use Getopt::Long 'GetOptionsFromArray';

__PACKAGE__->attr('description', default => <<'EOF');
Start application with CGI backend.
EOF
__PACKAGE__->attr('usage', default => <<"EOF");
usage: $0 cgi [OPTIONS]

These options are available:
  --nph    Enable non-parsed-header mode.
EOF

# Hi, Super Nintendo Chalmers!
sub run {
    my $self = shift;
    my $cgi  = Mojo::Server::CGI->new;

    # Options
    my @options = @_ ? @_ : @ARGV;
    GetOptionsFromArray(\@options, 'nph' => sub { $cgi->nph(1) });

    # Run
    $cgi->run;

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

=head2 C<usage>

    my $usage = $cgi->usage;
    $cgi      = $cgi->usage('Foo!');

=head1 METHODS

L<Mojo::Script::Cgi> inherits all methods from L<Mojo::Script> and implements
the following new ones.

=head2 C<run>

    $cgi = $cgi->run(@ARGV);

=cut
