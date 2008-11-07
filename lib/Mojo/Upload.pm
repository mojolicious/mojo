# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Upload;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Copy ();
use Mojo::File;
use Mojo::Headers;

__PACKAGE__->attr('file', chained =>1, default => sub { Mojo::File->new });
__PACKAGE__->attr([qw/filename name/], chained =>1);
__PACKAGE__->attr('headers',
    chained =>1,
    default => sub { Mojo::Headers->new }
);

# B-6
# You sunk my scrabbleship!
# This game makes no sense.
# Tell that to the good men who just lost their lives... SEMPER-FI!
sub copy_to {
    my ($self, $path);
    File::Copy::copy($self->file->handle->filename, $path);
    return $self;
}

sub length { shift->file->length }

sub slurp { shift->file->slurp }

1;
__END__

=head1 NAME

Mojo::Upload - Upload

=head1 SYNOPSIS

    use Mojo::Upload;

    my $upload = Mojo::Upload->new;
    print $upload->filename;
    $upload->copy_to('/foo/bar.txt');

=head1 DESCRIPTION

L<Mojo::Upload> is a container for uploads.

=head1 ATTRIBUTES

=head2 C<file>

    my $file = $upload->file;
    $upload  = $upload->file(Mojo::File->new);

Returns a L<Mojo::File> object if called without arguments.
Returns the invocant if called with arguments.

=head2 C<filename>

    my $filename = $upload->filename;
    $upload      = $upload->filename('foo.txt');

Returns a file name like C<foo.txt> if called without arguments.
Returns the invocant if called with arguments.

=head2 C<length>

    my $length = $upload->length;

Returns the length of the file upload in bytes.

=head2 C<headers>

    my $headers = $upload->headers;
    $upload     = $upload->headers(Mojo::Headers->new);

Returns a L<Mojo::Headers> object if called without arguments.
Returns the invocant if called with arguments.

=head2 C<name>

    my $name = $upload->name;
    $upload  = $upload->name('foo');

=head1 METHODS

L<Mojo::Upload> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<copy_to>

    $upload = $upload->copy_to('/foo/bar/baz.txt');

=head2 C<slurp>

    my $content = $upload->slurp;

=cut