# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Dispatcher::Static;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use Mojo::Content;
use Mojo::File;
use MojoX::Types;

__PACKAGE__->attr('prefix', chained => 1);
__PACKAGE__->attr('types',
    chained => 1,
    default => sub { MojoX::Types->new }
);
__PACKAGE__->attr('root', chained => 1);

# Valentine's Day's coming? Aw crap! I forgot to get a girlfriend again!
sub dispatch {
    my ($self, $tx) = @_;

    # Prefix
    if (my $prefix = $self->prefix) {
        return $self unless $tx->req->url->path =~ /^$prefix.*/;
    }

    # Path
    my @parts = @{$tx->req->url->path->clone->canonicalize->parts};

    # Shortcut
    return $self unless @parts;

    # Serve static file
    $self->serve($tx, File::Spec->catfile(@parts));

    return $self;
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
        $res->headers->content_type($type);
        $res->content->file->file_name($path);
    }

    return $self;
}

1;
__END__

=head1 NAME

MojoX::Dispatcher::Static - Static Dispatcher

=head1 SYNOPSIS

    use MojoX::Dispatcher::Static;

    my $dispatcher = MojoX::Dispatcher::Static->new;

=head1 DESCRIPTION

L<MojoX::Dispatcher::Static> is a dispatcher for static files.

=head2 ATTRIBUTES

=head2 C<prefix>

    my $prefix  = $dispatcher->prefix;
    $dispatcher = $dispatcher->prefix('/static');

=head2 C<types>

    my $types   = $dispatcher->types;
    $dispatcher = $dispatcher->types(MojoX::Types->new);

=head2 C<root>

    my $root    = $dispatcher->root;
    $dispatcher = $dispatcher->root('/foo/bar/files');

=head1 METHODS

L<MojoX::Dispatcher::Static> inherits all methods from L<Mojo::Base> and
implements the follwing the ones.

=head2 C<dispatch>

    $dispatcher = $dispatcher->dispatch($tx);

=head2 C<serve>

    $dispatcher = $dispatcher->serve($tx, '/foo/bar.html');

=cut