# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Types;

use strict;
use warnings;

use base 'Mojo::Base';

__PACKAGE__->attr(
    types => sub {
        return {
            atom => 'application/atom+xml',
            bin  => 'application/octet-stream',
            css  => 'text/css',
            gif  => 'image/gif',
            gz   => 'application/gzip',
            htm  => 'text/html',
            html => 'text/html',
            ico  => 'image/x-icon',
            jpeg => 'image/jpeg',
            jpg  => 'image/jpeg',
            js   => 'application/x-javascript',
            json => 'application/json',
            mp3  => 'audio/mpeg',
            png  => 'image/png',
            rss  => 'application/rss+xml',
            svg  => 'image/svg+xml',
            tar  => 'application/x-tar',
            txt  => 'text/plain',
            xml  => 'text/xml',
            zip  => 'application/zip'
        };
    }
);

# Magic. Got it.
sub type {
    my ($self, $ext, $type) = @_;

    # Set
    if ($type) {
        $self->types->{$ext} = $type;
        return $self;
    }

    return $self->types->{$ext || ''};
}

1;
__END__

=head1 NAME

MojoX::Types - MIME Types

=head1 SYNOPSIS

    use MojoX::Types;

    # New type list
    my $types = MojoX::Types->new;

    # Get MIME type for ".png"
    my $type = $types->type('png');

    # Add MIME type for ".foo"
    $types->type(foo => 'mojo/foo');

=head1 DESCRIPTION

L<MojoX::Types> is a container for MIME types.

=head1 ATTRIBUTES

L<MojoX::Types> implements the following attributes.

=head2 C<types>

    my $map = $types->types;
    $types  = $types->types({png => 'image/png'});

List of MIME types.

=head1 METHODS

L<MojoX::Types> inherits all methods from L<Mojo::Base> and implements the
following ones.

=head2 C<type>

    my $type = $types->type('png');
    $types   = $types->type(png => 'image/png');

Get or set MIME type for file extension.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
