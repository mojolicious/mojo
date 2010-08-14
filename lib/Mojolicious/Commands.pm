package Mojolicious::Commands;

use strict;
use warnings;

use base 'Mojo::Commands';

__PACKAGE__->attr(
    namespaces => sub { [qw/Mojolicious::Command Mojo::Command/] });

# One day a man has everything, the next day he blows up a $400 billion
# space station, and the next day he has nothing. It makes you think.

1;
__END__

=head1 NAME

Mojolicious::Commands - Commands

=head1 SYNOPSIS

    use Mojo::Commands;

    # Command line interface
    my $commands = Mojolicious::Commands->new;
    $commands->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicous::Commands> is the interactive command line interface to the
L<Mojolicious> framework.
It will automatically detect available commands in the
L<Mojolicious::Command> namespace.

These commands are available by default in addition to the commands listed in
L<Mojo::Commands>.

=over 4

=item C<generate>

    mojolicious generate
    mojolicious generate help

List available generator commands with short descriptions.

    mojolicious generate help <generator>

List available options for generator command with short descriptions.

=item C<generate app>

    mojolicious generate app <AppName>

Generate application directory structure for a fully functional
L<Mojolicious> application.

=item C<generate lite_app>

    mojolicious generate lite_app

Generate a fully functional L<Mojolicious::Lite> application.

=item C<inflate>

    myapp.pl inflate

Turn embedded files from the C<DATA> section into real files.

=item C<routes>

    myapp.pl routes
    script/myapp routes

List application routes.

=back

=head1 ATTRIBUTES

L<Mojolicious::Commands> inherits all attributes from L<Mojo::Commands> and
implements the following new ones.

=head2 C<namespaces>

    my $namespaces = $commands->namespaces;
    $commands      = $commands->namespaces(['Mojolicious::Commands']);

Namespaces to search for available commands, defaults to L<Mojo::Command> and
L<Mojolicious::Command>.

=head1 METHODS

L<Mojolicious::Commands> inherits all methods from L<Mojo::Commands>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
