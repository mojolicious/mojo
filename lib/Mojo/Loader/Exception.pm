# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Loader::Exception;

use strict;
use warnings;

use base 'Mojo::Template::Exception';

use IO::File;
use Mojo::Script;

__PACKAGE__->attr('loaded', default => 0);
__PACKAGE__->attr('module');

# You killed zombie Flanders!
# He was a zombie?
sub new {
    my $self = shift->SUPER::new();

    # Module
    my $module = shift;
    $self->module($module);

    # Message
    my $msg = shift;
    $self->message($msg);

    if ($msg =~ /at\s+([^\s]+)\s+line\s+(\d+)/) {
        my $file = $1;
        my $line = $2;

        # Context
        if (-r $file) {

            # Slurp
            my $handle = IO::File->new("< $file");
            my @lines  = <$handle>;

            # Line
            $self->parse_context(\@lines, $line);
        }
    }

    # Loaded?
    my $path = Mojo::Script->class_to_path($module);
    $self->loaded(1) unless $msg =~ /^Can't locate $path in \@INC/;

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Loader::Exception - Loader Exception

=head1 SYNOPSIS

    use Mojo::Loader::Exception;
    my $e = Mojo::Loader::Exception->new;

=head1 DESCRIPTION

L<Mojo::Loader::Exception> is a container for loader exceptions.

=head1 ATTRIBUTES

L<Mojo::Loader::Exception> inherits all methods from
L<Mojo::Template::Exception> and implements the following new ones.

=head2 C<loaded>

    my $loaded = $e->loaded;
    $e         = $e->loaded(1);

=head2 C<module>

    my $module = $e->module;
    $e         = $e->module('Foo::Bar');

=head1 METHODS

L<Mojo::Loader::Exception> inherits all methods from
L<Mojo::Template::Exception> and implements the following new ones.

=head2 C<new>

    my $e = Mojo::Loader::Exception->new(
        'SomeClass',
        'Something bad happened!'
    );

=cut
