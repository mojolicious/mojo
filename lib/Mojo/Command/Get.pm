# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command::Get;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::ByteStream 'b';
use Mojo::Client;
use Mojo::Transaction::HTTP;

use Getopt::Long 'GetOptions';

__PACKAGE__->attr(description => <<'EOF');
Get file from URL.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 get [OPTIONS] [URL]

These options are available:
  --verbose   Print response start line and headers to STDERR.
EOF

# I hope this has taught you kids a lesson: kids never learn.
sub run {
    my $self = shift;

    # Options
    local @ARGV = @_ if @_;
    my $verbose = 0;
    GetOptions('verbose' => sub { $verbose = 1 });

    # URL
    my $url = $ARGV[0];
    die $self->usage unless $url;
    $url = b($url)->decode('UTF-8')->to_string;

    # Client
    my $client = Mojo::Client->new;

    # Silence
    $client->log->level('fatal');

    # Application
    $client->app($ENV{MOJO_APP} || 'Mojo::HelloWorld')
      unless $url =~ /^\w+:\/\//;

    # Transaction
    my $tx = $client->build_tx(GET => $url);
    $tx->res->body(
        sub {
            my ($res, $chunk) = @_;
            print STDERR $tx->res->build_start_line if $verbose;
            print STDERR $res->headers->to_string, "\n\n" if $verbose;
            print $chunk;
            $verbose = 0;
        }
    );

    # Request
    $client->process($tx);

    # Error
    if ($tx->has_error) {
        my $message = $tx->error;
        $message = $message ? " ($message)" : '';
        print qq/Couldn't open page "$url".$message\n/;
    }

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

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $get->usage;
    $get      = $get->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojo::Command::Get> inherits all methods from L<Mojo::Command> and implements
the following new ones.

=head2 C<run>

    $get = $get->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
