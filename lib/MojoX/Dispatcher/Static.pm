package MojoX::Dispatcher::Static;

use strict;
use warnings;

use base 'Mojo::Base';

use File::stat;
use File::Spec;
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::ByteStream 'b';
use Mojo::Command;
use Mojo::Content::Single;
use Mojo::Path;
use MojoX::Types;

__PACKAGE__->attr([qw/default_static_class prefix root/]);
__PACKAGE__->attr(types => sub { MojoX::Types->new });

# Valentine's Day's coming? Aw crap! I forgot to get a girlfriend again!
sub dispatch {
    my ($self, $c) = @_;

    # Already rendered
    return if $c->res->code;

    # Canonical path
    my $path = $c->req->url->path->clone->canonicalize->to_string;

    # Prefix
    if (my $prefix = $self->prefix) {
        return 1 unless $path =~ s/^$prefix//;
    }

    # Parts
    my @parts = @{Mojo::Path->new->parse($path)->parts};

    # Shortcut
    return 1 unless @parts;

    # Prevent directory traversal
    return 1 if $parts[0] eq '..';

    # Serve static file
    return $self->serve($c, join('/', @parts));
}

sub serve {
    my ($self, $c, $rel) = @_;

    # Append path to root
    my $path = File::Spec->catfile($self->root, split('/', $rel));

    # Extension
    $path =~ /\.(\w+)$/;
    my $ext = $1;

    # Type
    my $type = $self->types->type($ext) || 'text/plain';

    # Response
    my $res = $c->res;

    # Asset
    my $asset;

    # Modified
    my $modified = $self->{_modified} ||= time;

    # Size
    my $size = 0;

    # File
    if (-f $path) {

        # Readable
        if (-r $path) {

            # Modified
            my $stat = stat($path);
            $modified = $stat->mtime;

            # Size
            $size = $stat->size;

            # Content
            $asset = Mojo::Asset::File->new(path => $path);
        }

        # Exists, but is forbidden
        else {
            $c->app->log->debug('File forbidden.');
            $res->code(403) and return;
        }
    }

    # Inline file
    elsif (defined(my $file = $self->_get_inline_file($c, $rel))) {
        $size  = length $file;
        $asset = Mojo::Asset::Memory->new->add_chunk($file);
    }

    # Found
    if ($asset) {

        # Log
        $c->app->log->debug(qq/Serving static file "$rel"./);

        # Resume
        $c->tx->resume;

        # Request
        my $req = $c->req;

        # Request headers
        my $rqh = $req->headers;

        # Response headers
        my $rsh = $res->headers;

        # If modified since
        if (my $date = $rqh->if_modified_since) {

            # Not modified
            my $since = Mojo::Date->new($date)->epoch;
            if (defined $since && $since == $modified) {
                $c->app->log->debug('File not modified.');
                $res->code(304);
                $rsh->remove('Content-Type');
                $rsh->remove('Content-Length');
                $rsh->remove('Content-Disposition');
                return;
            }
        }

        # Start and end
        my $start = 0;
        my $end = $size - 1 >= 0 ? $size - 1 : 0;

        # Range
        if (my $range = $rqh->range) {
            if ($range =~ m/^bytes=(\d+)\-(\d+)?/ && $1 <= $end) {
                $start = $1;
                $end = $2 if defined $2 && $2 <= $end;
                $res->code(206);
                $rsh->content_length($end - $start + 1);
                $rsh->content_range("bytes $start-$end/$size");
                $c->app->log->debug("Range request: $start-$end/$size.");
            }
            else {

                # Not satisfiable
                $res->code(416);
                return;
            }
        }
        $asset->start_range($start);
        $asset->end_range($end);

        # Response
        $res->code(200) unless $res->code;
        $res->content->asset($asset);
        $rsh->content_type($type);
        $rsh->accept_ranges('bytes');
        $rsh->last_modified(Mojo::Date->new($modified));
        return;
    }

    return 1;
}

sub serve_404 { shift->serve_error(shift, 404) }

sub serve_500 { shift->serve_error(shift, 500) }

sub serve_error {
    my ($self, $c, $code, $rel) = @_;

    # Shortcut
    return 1 unless $c && $code;

    my $res = $c->res;

    # Render once
    return if ($res->code || '') eq $code;

    # Code
    $res->code($code);

    # Default to "code.html"
    $rel ||= "$code.html";

    # File
    if (!$self->serve($c, $rel)) {

        # Log
        $c->app->log->debug(qq/Serving error file "$rel"./);
    }

    # 404
    elsif ($code == 404) {

        # Log
        $c->app->log->debug('Serving 404 error.');

        $res->headers->content_type('text/html');
        $res->body(<<'EOF');
<!doctype html><html>
    <head><title>File Not Found</title></head>
    <body><h2>File Not Found</h2></body>
</html>
EOF
    }

    # Error
    else {

        # Log
        $c->app->log->debug(qq/Serving error "$code"./);

        $res->headers->content_type('text/html');
        $res->body(<<'EOF');
<!doctype html><html>
    <head><title>Internal Server Error</title></head>
    <body><h2>Internal Server Error</h2></body>
</html>
EOF
    }

    return;
}

sub _get_inline_file {
    my ($self, $c, $rel) = @_;

    # Protect templates
    return if $rel =~ /\.\w+\.\w+$/;

    # Class
    my $class =
         $c->stash->{static_class}
      || $ENV{MOJO_STATIC_CLASS}
      || $self->default_static_class
      || 'main';

    # Inline files
    my $inline = $self->{_inline_files}->{$class};
    unless ($inline) {
        my $files = Mojo::Command->new->get_all_data($class) || {};
        $inline = $self->{_inline_files}->{$class} = [keys %$files];
    }

    # Find
    for my $path (@$inline) {
        return Mojo::Command->new->get_data($path, $class) if $path eq $rel;
    }

    # Nothing
    return;
}

1;
__END__

=head1 NAME

MojoX::Dispatcher::Static - Serve Static Files

=head1 SYNOPSIS

    use MojoX::Dispatcher::Static;

    # New dispatcher
    my $dispatcher = MojoX::Dispatcher::Static->new(
        prefix => '/images',
        root   => '/ftp/pub/images'
    );

    # Dispatch
    my $success = $dispatcher->dispatch($c);

=head1 DESCRIPTION

L<MojoX::Dispatcher::Static> is a dispatcher for static files with C<Range>
and C<If-Modified-Since> support.

=head1 ATTRIBUTES

L<MojoX::Dispatcher::Static> implements the following attributes.

=head2 C<default_static_class>

    my $class   = $dispatcher->default_static_class;
    $dispatcher = $dispatcher->default_static_class('main');

The dispatcher will use this class to look for files in the C<DATA> section.

=head2 C<prefix>

    my $prefix  = $dispatcher->prefix;
    $dispatcher = $dispatcher->prefix('/static');

Prefix path to remove from incoming paths before dispatching.

=head2 C<types>

    my $types   = $dispatcher->types;
    $dispatcher = $dispatcher->types(MojoX::Types->new);

MIME types, by default a L<MojoX::Types> object.

=head2 C<root>

    my $root    = $dispatcher->root;
    $dispatcher = $dispatcher->root('/foo/bar/files');

Directory to serve static files from.

=head1 METHODS

L<MojoX::Dispatcher::Static> inherits all methods from L<Mojo::Base> and
implements the following ones.

=head2 C<dispatch>

    my $success = $dispatcher->dispatch($c);

Dispatch a L<MojoX::Controller> object.

=head2 C<serve>

    my $success = $dispatcher->serve($c, 'foo/bar.html');

Serve a specific file.

=head2 C<serve_404>

    my $success = $dispatcher->serve_404($c);
    my $success = $dispatcher->serve_404($c, '404.html');

Serve a C<404> error page, guaranteed to render at least a default page.

=head2 C<serve_500>

    my $success = $dispatcher->serve_500($c);
    my $success = $dispatcher->serve_500($c, '500.html');

Serve a C<500> error page, guaranteed to render at least a default page.

=head2 C<serve_error>

    my $success = $dispatcher->serve_error($c, 404);
    my $success = $dispatcher->serve_error($c, 404, '404.html');

Serve error page, guaranteed to render at least a default page.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
