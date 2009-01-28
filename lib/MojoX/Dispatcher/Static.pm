# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoX::Dispatcher::Static;

use strict;
use warnings;

use base 'Mojo::Base';

use File::stat;
use File::Spec;
use Mojo::Content;
use Mojo::File;
use MojoX::Types;

__PACKAGE__->attr(prefix => (chained => 1));
__PACKAGE__->attr(
    types => (
        chained => 1,
        default => sub { MojoX::Types->new }
    )
);
__PACKAGE__->attr(root => (chained => 1));

# Valentine's Day's coming? Aw crap! I forgot to get a girlfriend again!
sub dispatch {
    my ($self, $c) = @_;

    # Prefix
    if (my $prefix = $self->prefix) {
        return 0 unless $c->req->url->path =~ /^$prefix.*/;
    }

    # Path
    my @parts = @{$c->req->url->path->clone->canonicalize->parts};

    # Shortcut
    return 0 unless @parts;

    # Serve static file
    return $self->serve($c, File::Spec->catfile(@parts));
}

sub serve {
    my ($self, $c, $path) = @_;

    # Append path to root
    $path = File::Spec->catfile($self->root, split('/', $path));

    # Extension
    $path =~ /\.(\w+)$/;
    my $ext = $1;

    # Type
    my $type = $self->types->type($ext) || 'text/plain';

    # Dispatch
    if (-f $path) {

        # Log
        $c->app->log->debug(qq/Serving static file "$path"/);

        my $res = $c->res;
        if (-r $path) {
            my $req  = $c->req;
            my $stat = stat($path);

            # If modified since
            if (my $date = $req->headers->header('If-Modified-Since')) {

                # Not modified
                if (Mojo::Date->new($date)->epoch == $stat->mtime) {

                    # Log
                    $c->app->log->debug('File not modified');

                    $res->code(304);
                    $res->headers->remove('Content-Type');
                    $res->headers->remove('Content-Length');
                    $res->headers->remove('Content-Disposition');
                    return 1;
                }
            }

            $res->content(Mojo::Content->new(file => Mojo::File->new));
            $res->code(200);

            # Last modified
            $res->headers->header('Last-Modified',
                Mojo::Date->new($stat->mtime));

            $res->headers->content_type($type);
            $res->content->file->path($path);
            return 1;
        }

        # Exists, but is forbidden
        else {

            # Log
            $c->app->log->debug('File forbidden');

            $res->code(403);
            return 1;
        }
    }

    return 0;
}

sub serve_404 { shift->serve_error(shift, 404) }

sub serve_500 { shift->serve_error(shift, 500) }

sub serve_error {
    my ($self, $c, $code, $path) = @_;

    # Shortcut
    return 0 unless $c && $code;

    my $res = $c->res;

    # Code
    $res->code($code);

    # Default to "code.html"
    $path ||= "$code.html";

    # Append path to root
    $path = File::Spec->catfile($self->root, split('/', $path));

    # File
    if (-r $path) {

        # Log
        $c->app->log->debug(qq/Serving error file "$path"/);

        # File
        $res->content(Mojo::Content->new(file => Mojo::File->new));
        $res->content->file->path($path);

        # Extension
        $path =~ /\.(\w+)$/;
        my $ext = $1;

        # Type
        my $type = $self->types->type($ext) || 'text/plain';
        $res->headers->content_type($type);
    }

    # 404
    elsif ($code == 404) {

        # Log
        $c->app->log->debug('Serving 404 error');

        $res->headers->content_type('text/html');
        $res->body(<<'EOF');
<!doctype html>
    <head><title>File Not Found</title></head>
    <body>
        <h2>File Not Found</h2>
    </body>
</html>
EOF
    }

    # Error
    else {

        # Log
        $c->app->log->debug(qq/Serving error "$code"/);

        $res->headers->content_type('text/html');
        $res->body(<<'EOF');
<!doctype html>
    <head><title>Internal Server Error</title></head>
    <body>
        <h2>Internal Server Error</h2>
    </body>
</html>
EOF
    }

    return 1;
}

1;
__END__

=head1 NAME

MojoX::Dispatcher::Static - Serve Static Files

=head1 SYNOPSIS

    use MojoX::Dispatcher::Static;

    my $dispatcher = MojoX::Dispatcher::Static->new(
            prefix => '/images',
            root   => '/ftp/pub/images'
    );
    my $success = $dispatcher->dispatch($c);

=head1 DESCRIPTION

L<MojoX::Dispatcher::Static> is a dispatcher for static files.

=head2 ATTRIBUTES

=head2 C<prefix>

    my $prefix  = $dispatcher->prefix;
    $dispatcher = $dispatcher->prefix('/static');

Returns the path prefix if called without arguments.
Returns the invocant if called with arguments.
If defined, files will only get served for url paths beginning with this
prefix.

=head2 C<types>

    my $types   = $dispatcher->types;
    $dispatcher = $dispatcher->types(MojoX::Types->new);

Returns a L<Mojo::Types> object if called without arguments.
Returns the invocant if called with arguments.
If no type can be determined, C<text/plain> will be used.

=head2 C<root>

    my $root    = $dispatcher->root;
    $dispatcher = $dispatcher->root('/foo/bar/files');

Returns the root directory from which files get served if called without
arguments.
Returns the invocant if called with arguments.

=head1 METHODS

L<MojoX::Dispatcher::Static> inherits all methods from L<Mojo::Base> and
implements the follwing the ones.

=head2 C<dispatch>

    my $success = $dispatcher->dispatch($c);

Returns true if a file matching the request could be found and a response be
prepared.
Returns false otherwise.
Expects a L<MojoX::Context> object as first argument.

=head2 C<serve>

    my $success = $dispatcher->serve($c, 'foo/bar.html');

Returns true if a readable file could be found under C<root> and a response
be prepared.
Returns false otherwise.
Expects a L<MojoX::Context> object and a path as arguments.
If no type can be determined, C<text/plain> will be used.
A C<Last-Modified> header will always be set according to the last modified
time of the file.

=head2 C<serve_404>

    my $success = $dispatcher->serve_404($c);
    my $success = $dispatcher->serve_404($c, '404.html');

=head2 C<serve_500>

    my $success = $dispatcher->serve_500($c);
    my $success = $dispatcher->serve_500($c, '500.html');

=head2 C<serve_error>

    my $success = $dispatcher->serve_error($c, 404);
    my $success = $dispatcher->serve_error($c, 404, '404.html');

=cut
