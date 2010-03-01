# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Filter;

use strict;
use warnings;

use base 'Mojo::Stateful';

use Carp 'croak';
use Mojo::ByteStream;
use Mojo::Headers;

__PACKAGE__->attr(headers => sub { Mojo::Headers->new });
__PACKAGE__->attr(
    [qw/input_buffer output_buffer/] => sub { Mojo::ByteStream->new });

# Quick Smithers. Bring the mind eraser device!
# You mean the revolver, sir?
# Precisely.
sub build { croak 'Method "build" not implemented by subclass' }

sub parse { croak 'Method "parse" not implemented by subclass' }

1;
__END__

=head1 NAME

Mojo::Filter - HTTP 1.1 Filter Base Class

=head1 SYNOPSIS

    use base 'Mojo::Filter';

=head1 DESCRIPTION

L<Mojo::Filter> is an abstract base class for HTTP 1.1 filters as described
in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Filter> inherits all attributes from L<Mojo::Stateful> and implements
the following new ones.

=head2 C<headers>

    my $headers = $filter->headers;
    $filter     = $filter->headers(Mojo::Headers->new);

The headers.

=head2 C<input_buffer>

    my $input_buffer = $filter->input_buffer;
    $filter          = $filter->input_buffer(Mojo::ByteStream->new);

Input buffer for filtering.

=head2 C<output_buffer>

    my $output_buffer = $filter->output_buffer;
    $filter           = $filter->output_buffer(Mojo::ByteStream->new);

Output buffer for filtering.

=head1 METHODS

L<Mojo::Filter> inherits all methods from L<Mojo::Stateful> and implements
the following new ones.

=head2 C<build>

    my $formatted = $filter->build('Hello World!');

Build filtered content.

=head2 C<parse>

    $filter = $filter->parse;

Filter content.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
