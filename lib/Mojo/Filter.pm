# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Filter;

use strict;
use warnings;

use base 'Mojo::Stateful';

use Carp 'croak';
use Mojo::Buffer;
use Mojo::Headers;

__PACKAGE__->attr(headers => sub { Mojo::Headers->new });
__PACKAGE__->attr(
    [qw/input_buffer output_buffer/] => sub { Mojo::Buffer->new });

# Quick Smithers. Bring the mind eraser device!
# You mean the revolver, sir?
# Precisely.
sub build { croak 'Method "build" not implemented by subclass' }

sub parse { croak 'Method "parse" not implemented by subclass' }

1;
__END__

=head1 NAME

Mojo::Filter - Filter Base Class

=head1 SYNOPSIS

    use base 'Mojo::Filter';

=head1 DESCRIPTION

L<Mojo::Filter> is a base class for HTTP filters.

=head1 ATTRIBUTES

L<Mojo::Filter> inherits all attributes from L<Mojo::Stateful> and implements
the following new ones.

=head2 C<headers>

    my $headers = $filter->headers;
    $filter     = $filter->headers(Mojo::Headers->new);

=head2 C<input_buffer>

    my $input_buffer = $filter->input_buffer;
    $filter          = $filter->input_buffer(Mojo::Buffer->new);

=head2 C<output_buffer>

    my $output_buffer = $filter->output_buffer;
    $filter           = $filter->output_buffer(Mojo::Buffer->new);

=head1 METHODS

L<Mojo::Filter> inherits all methods from L<Mojo::Stateful> and implements the
following new ones.

=head2 C<build>

    my $formatted = $filter->build('Hello World!');

=head2 C<parse>

    $filter = $filter->parse;

=cut
