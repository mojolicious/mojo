package Mojolicious::Command::Get;
use Mojo::Base 'Mojo::Command';

use Mojo::Client;
use Mojo::IOLoop;
use Mojo::Transaction::HTTP;
use Mojo::Util 'decode';

use Getopt::Long 'GetOptions';

has description => <<'EOF';
Get file from URL.
EOF
has usage => <<"EOF";
usage: $0 get [OPTIONS] [URL]

These options are available:
  --redirect   Follow up to 5 redirects.
  --verbose    Print verbose debug information to STDERR.
EOF

# I hope this has taught you kids a lesson: kids never learn.
sub run {
    my $self = shift;

    # Options
    local @ARGV = @_ if @_;
    my ($redirect, $verbose) = 0;
    GetOptions(
        'redirect' => sub { $redirect = 1 },
        'verbose'  => sub { $verbose  = 1 }
    );

    # URL
    my $url = $ARGV[0];
    die $self->usage unless $url;
    decode 'UTF-8', $url;

    # Client
    my $client = Mojo::Client->new(ioloop => Mojo::IOLoop->singleton);

    # Silence
    $client->log->level('fatal');

    # Absolute URL
    if ($url =~ /^\w+:\/\//) { $client->detect_proxy }

    # Application
    else { $client->app($ENV{MOJO_APP} || 'Mojo::HelloWorld') }

    # Follow redirects
    $client->max_redirects(5) if $redirect;

    # Start
    my $v;
    $client->on_start(
        sub {
            my $tx = pop;

            # Prepare request information
            my $req       = $tx->req;
            my $startline = $req->build_start_line;
            my $headers   = $req->build_headers;

            # Verbose callback
            my $v  = $verbose;
            my $cb = sub {
                my $res = shift;

                # Wait for headers
                return unless $v && $res->headers->is_done;

                # Request
                warn "$startline$headers";

                # Response
                my $version = $res->version;
                my $code    = $res->code;
                my $message = $res->message;
                warn "HTTP/$version $code $message\n",
                  $res->headers->to_string, "\n\n";

                # Done
                $v = 0;
            };

            # Progress
            $tx->res->on_progress(sub { $cb->(shift) });

            # Stream content
            $tx->res->body(
                sub {
                    $cb->(my $res = shift);

                    # Ignore intermediate content
                    return if $redirect && $res->is_status_class(300);

                    # Chunk
                    print pop;
                }
            );
        }
    );

    # Get
    my $tx = $client->get($url);

    # Error
    my ($message, $code) = $tx->error;
    warn qq/Problem loading URL "$url". ($message)\n/ if $message && !$code;

    return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Command::Get - Get Command

=head1 SYNOPSIS

    use Mojolicious::Command::Get;

    my $get = Mojolicious::Command::Get->new;
    $get->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Get> is a command interface to L<Mojo::Client>.

=head1 ATTRIBUTES

L<Mojolicious::Command::Get> inherits all attributes from L<Mojo::Command>
and implements the following new ones.

=head2 C<description>

    my $description = $get->description;
    $get            = $get->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $get->usage;
    $get      = $get->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Get> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

    $get = $get->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
