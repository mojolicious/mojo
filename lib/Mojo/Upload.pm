package Mojo::Upload;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Asset::File;
use Mojo::Headers;

has asset => sub { Mojo::Asset::File->new };
has [qw/filename name/];
has headers => sub { Mojo::Headers->new };

# "B-6
#  You sunk my scrabbleship!
#  This game makes no sense.
#  Tell that to the good men who just lost their lives... SEMPER-FI!"
sub move_to { shift->asset->move_to(@_) }
sub size    { shift->asset->size }
sub slurp   { shift->asset->slurp }

1;
__END__

=head1 NAME

Mojo::Upload - Upload container

=head1 SYNOPSIS

  use Mojo::Upload;

  my $upload = Mojo::Upload->new;
  say $upload->filename;
  $upload->move_to('/foo/bar/baz.txt');

=head1 DESCRIPTION

L<Mojo::Upload> is a container for uploads.

=head1 ATTRIBUTES

L<Mojo::Upload> implements the following attributes.

=head2 C<asset>

  my $asset = $upload->asset;
  $upload   = $upload->asset(Mojo::Asset::File->new);

Asset containing the uploaded data, defaults to a L<Mojo::Asset::File>
object.

=head2 C<filename>

  my $filename = $upload->filename;
  $upload      = $upload->filename('foo.txt');

Name of the uploaded file.

=head2 C<headers>

  my $headers = $upload->headers;
  $upload     = $upload->headers(Mojo::Headers->new);

Headers for upload, defaults to a L<Mojo::Headers> object.

=head2 C<name>

  my $name = $upload->name;
  $upload  = $upload->name('foo');

Name of the upload.

=head1 METHODS

L<Mojo::Upload> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<move_to>

  $upload->move_to('/foo/bar/baz.txt');

Move uploaded data to a specific file.

=head2 C<size>

  my $size = $upload->size;

Size of upload in bytes.

=head2 C<slurp>

  my $string = $upload->slurp;

Read all upload data at once.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
