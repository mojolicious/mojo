# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Dispatcher::Static;

use strict;
use warnings;

use base 'Mojo::Base';

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
    my ($self, $tx) = @_;

    # Prefix
    if (my $prefix = $self->prefix) {
        return 0 unless $tx->req->url->path =~ /^$prefix.*/;
    }

    # Path
    my @parts = @{$tx->req->url->path->clone->canonicalize->parts};

    # Shortcut
    return 0 unless @parts;

    # Serve static file
    return $self->serve($tx, File::Spec->catfile(@parts));
}

sub serve {
    my ($self, $tx, $path) = @_;

    # Append path to root
    $path = File::Spec->catfile($self->root, $path);

    # Extension
    $path =~ /\.(\w+)$/;
    my $ext = $1;

    # Type
    my $type = $self->types->type($ext) || 'text/plain';

    # Dispatch
    if (-f $path && -r $path) {
        my $res = $tx->res;
        $res->content(Mojo::Content->new(file => Mojo::File->new));
        $res->code(200);

        # Last modified
        my $mtime = (stat $path)[9];
        $res->headers->header('Last-Modified', Mojo::Date->new($mtime));

        $res->headers->content_type($type);
        $res->content->file->path($path);
        return 1;
    }

    return 0;
}

1;
__END__

=head1 NAME

MojoX::Dispatcher::Static - Serve static files over HTTP

=head1 SYNOPSIS

    use MojoX::Dispatcher::Static;

    my $dispatcher = MojoX::Dispatcher::Static->new;

=head1 DESCRIPTION

L<MojoX::Dispatcher::Static> is a dispatcher for static files.

=head2 ATTRIBUTES

=head2 C<prefix>

    my $prefix  = $dispatcher->prefix;
    $dispatcher = $dispatcher->prefix('/static');

If the prefix attribute is set, we will only try to dispatch URI which begins with this 
prefix. The URI should begin a "/"

=head2 C<types>

    my $types   = $dispatcher->types;
    $dispatcher = $dispatcher->types(MojoX::Types->new);

C<types> maps file extensions to MIME types. This is done with MojoX::Types
by default. If no type can be determined, C<text/plain> is used. 

=head2 C<root>

    my $root    = $dispatcher->root;
    $dispatcher = $dispatcher->root('/foo/bar/files');

Define the root directory where the static files are stored. 

=head1 METHODS

L<MojoX::Dispatcher::Static> inherits all methods from L<Mojo::Base> and
implements the follwing the ones.

=head2 C<dispatch>

    my $success = $dispatcher->dispatch($tx);

Prepare an HTTP response via C<< $tx->res >>and return true if we can dispatch
to a static file, returns false if C<< $tx->req->url->path>> fails to match the
prefix or if the URI is empty. 

=head2 C<serve>

    my $success = $dispatcher->serve($tx, '/foo/bar.html');

Given a L<Mojo::Transaction> object and URI for a file, attempt to
prepare a HTTP response via C<< $tx->res >> that contains the file and
return true. 

To succeed, the URI must map exactly to a readable file between C<root>.  We
will determin the Content-type via C<< types() >>, defaulting to "text/plain".
A C<Last-Modified> header will always be set according the last modified time
of the file.

On failure, no response will be prepared and false will returned.

=cut
