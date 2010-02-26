# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command::Fastcgi;

use strict;
use warnings;

use base 'Mojo::Command';

use Getopt::Long 'GetOptions';
use Mojo::Server::FastCGI;

__PACKAGE__->attr(description => <<'EOF');
Start application with FastCGI backend.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 fastcgi [OPTIONS]

These options are available:
  --reload   Automatically reload application when the source code changes.
EOF

# Oh boy! Sleep! That's when I'm a Viking!
sub run {
    my $self    = shift;
    my $fastcgi = Mojo::Server::FastCGI->new;

    # Options
    @ARGV = @_ if @_;
    GetOptions(reload => sub { $fastcgi->reload(1) });

    # Run
    $fastcgi->run;

    return $self;
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

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $fastcgi->usage;
    $fastcgi  = $fastcgi->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojo::Command::Fastcgi> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

    $fastcgi = $fastcgi->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
