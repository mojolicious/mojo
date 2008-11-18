# Copyright (C) 2008, Sebastian Riedel.

package Mojo::HelloWorld;

use strict;
use warnings;

use base 'Mojo';

use Data::Dumper;

# How is education supposed to make me feel smarter? Besides,
# every time I learn something new, it pushes some old stuff out of my brain.
# Remember when I took that home winemaking course,
# and I forgot how to drive?
sub new {
    my $self = shift->SUPER::new();

    # This app should log only errors to STDERR
    $self->log->level('error');
    $self->log->path(undef);

    return $self;
}

sub handler {
    my ($self, $tx) = @_;

    # Dispatch to diagnostics functions
    return $self->_diag($tx) if $tx->req->url->path =~ m|^/diag|;

    # Hello world!
    $tx->res->code(200);
    $tx->res->headers->content_type('text/plain');
    $tx->res->body('Congratulations, your Mojo is working!');

    return $tx;
}

sub _diag {
    my ($self, $tx) = @_;

    # Dispatch
    my $path = $tx->req->url->path;
    $self->_dump_env($tx) if $path =~ m|^/diag/dump_env|;

    # Defaults
    $tx->res->code(200) unless $tx->res->code;
    $tx->res->headers->content_type('text/plain')
      unless $tx->res->headers->content_type;

    # List
    if ($path =~ m|^/diag[/]?$|) {
        $tx->res->headers->content_type('text/html');
        $tx->res->body(<<'EOF');
<!doctype html>
  <head><title>Mojo Diagnostics</title></head>
  <body>
    <a href="/diag/dump_env">Dump Environment Variables</a><br />
  </body>
</html>
EOF
    }

    return $tx;
}

sub _dump_env {
    my ($self, $tx) = @_;
    $tx->res->body(Dumper \%ENV);
}

1;
__END__

=head1 NAME

Mojo::HelloWorld - Hello World!

=head1 SYNOPSIS

    use Mojo::Transaction;
    use Mojo::HelloWorld;

    my $hello = Mojo::HelloWorld->new;
    my $tx = $hello->handler(Mojo::Transaction->new);

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
