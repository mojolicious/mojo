# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::HelloWorld;

use strict;
use warnings;

use base 'Mojo';

use Data::Dumper;
use Mojo::Filter::Chunked;

# How is education supposed to make me feel smarter? Besides,
# every time I learn something new, it pushes some old stuff out of my brain.
# Remember when I took that home winemaking course,
# and I forgot how to drive?
sub new {
    my $self = shift->SUPER::new(@_);

    # This app should log only errors to STDERR
    $self->log->level('error');
    $self->log->path(undef);

    return $self;
}

sub handler {
    my ($self, $tx) = @_;

    # Default to 200
    $tx->res->code(200);

    # Dispatch to diagnostics functions
    return $self->_diag($tx) if $tx->req->url->path =~ m|^/diag|;

    # Hello world!
    $tx->res->headers->content_type('text/plain');
    $tx->res->body('Congratulations, your Mojo is working!');
}

sub _diag {
    my ($self, $tx) = @_;

    # Dispatch
    my $path = $tx->req->url->path;
    $self->_chunked_params($tx) if $path =~ m|^/diag/chunked_params|;
    $self->_dump_env($tx)       if $path =~ m|^/diag/dump_env|;
    $self->_dump_params($tx)    if $path =~ m|^/diag/dump_params|;
    $self->_dump_tx($tx)        if $path =~ m|^/diag/dump_tx|;
    $self->_dump_url($tx)       if $path =~ m|^/diag/dump_url|;
    $self->_proxy($tx)          if $path =~ m|^/diag/proxy|;

    # Defaults
    $tx->res->headers->content_type('text/plain')
      unless $tx->res->headers->content_type;

    # List
    if ($path =~ m|^/diag[/]?$|) {
        $tx->res->headers->content_type('text/html');
        $tx->res->body(<<'EOF');
<!doctype html><html>
    <head><title>Mojo Diagnostics</title></head>
    <body>
        <a href="/diag/chunked_params">Chunked Request Parameters</a><br />
        <a href="/diag/dump_env">Dump Environment Variables</a><br />
        <a href="/diag/dump_params">Dump Request Parameters</a><br />
        <a href="/diag/dump_tx">Dump Transaction</a><br />
        <a href="/diag/dump_url">Dump Request URL</a><br />
        <a href="/diag/proxy">Proxy</a>
    </body>
</html>
EOF
    }
}

sub _chunked_params {
    my ($self, $tx) = @_;

    # Chunked
    $tx->res->headers->transfer_encoding('chunked');

    # Chunks
    my $params = $tx->req->params->to_hash;
    my $chunks = [];
    for my $key (sort keys %$params) {
        push @$chunks, $params->{$key};
    }

    # Callback
    my $counter = 0;
    my $chunked = Mojo::Filter::Chunked->new;
    $tx->res->body(
        sub {
            my $self = shift;
            my $chunk = $chunks->[$counter] || '';
            $counter++;
            return $chunked->build($chunk);
        }
    );
}

sub _dump_env {
    my ($self, $tx) = @_;
    $tx->res->body(Dumper \%ENV);
}

sub _dump_params {
    my ($self, $tx) = @_;
    $tx->res->body(Dumper $tx->req->params->to_hash);
}

sub _dump_tx {
    my ($self, $tx) = @_;
    $tx->res->body(Dumper $tx);
}

sub _dump_url {
    my ($self, $tx) = @_;
    $tx->res->body(Dumper $tx->req->url);
}

sub _proxy {
    my ($self, $tx) = @_;

    # Proxy
    if (my $url = $tx->req->param('url')) {

        # Pause transaction
        $tx->pause;

        # Fetch
        $self->client->get(
            $url => sub {
                my ($self, $tx2) = @_;

                # Resume transaction
                $tx->resume;

                # Pass through content
                $tx->res->headers->content_type(
                    $tx2->res->headers->content_type);
                $tx->res->body($tx2->res->content->asset->slurp);
            }
        )->process;

        return;
    }

    # Form
    my $url = $tx->req->url->clone;
    $url->path('/diag/proxy');
    $tx->res->headers->content_type('text/html');
    $tx->res->body(<<"EOF");
<!doctype html><html>
    <head><title>Mojo Diagnostics</title></head>
    <body>
        <form action="$url" method="GET">
            <input type="text" name="url" value="http://"/>
            <input type="submit" value="Fetch" />
        </form>
    </body>
</html>
EOF
}

1;
__END__

=head1 NAME

Mojo::HelloWorld - Hello World!

=head1 SYNOPSIS

    use Mojo::Transaction::Single;
    use Mojo::HelloWorld;

    my $hello = Mojo::HelloWorld->new;
    my $tx = $hello->handler(Mojo::Transaction::Single->new);

=head1 DESCRIPTION

L<Mojo::HelloWorld> is the default L<Mojo> application, used mostly for
testing.

=head1 METHODS

L<Mojo::HelloWorld> inherits all methods from L<Mojo> and implements the
following new ones.

=head2 C<new>

    my $hello = Mojo::HelloWorld->new;

=head2 C<handler>

    $tx = $hello->handler($tx);

=cut
