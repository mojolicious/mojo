# Copyright (C) 2008, Sebastian Riedel.

package Mojolicious::Renderer;

use strict;
use warnings;

use base 'MojoX::Renderer';

use Mojo::Template;

# What do you want?
# I'm here to kick your ass!
# Wishful thinking. We have long since evolved beyond the need for asses.
sub new {
    my $self = shift->SUPER::new(@_);
    $self->default_format('phtml');
    $self->add_handler(
        phtml => sub {
            my ($self, $c, $output) = @_;

            my $path = $c->stash->{template_path};

            # Check cache
            $self->{_mt_cache} ||= {};
            my $mt = $self->{_mt_cache}->{$path};

            # No cache
            unless ($mt) {

                # Initialize
                $mt = $self->{_mt_cache}->{$path} = Mojo::Template->new;
                return $mt->render_file($path, $output, $c);
            }

            # Interpret again
            $mt->interpret($output, $c);
        }
    );
    return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Renderer - Renderer

=head1 SYNOPSIS

    use Mojolicious::Renderer;

    my $renderer = Mojolicious::Renderer->new;

=head1 DESCRIPTION

L<Mojolicous::Renderer> is the default L<Mojolicious> renderer.

=head1 ATTRIBUTES

L<Mojolicious::Renderer> inherits all attributes from L<MojoX::Renderer>.

=head1 METHODS

L<Mojolicious::Renderer> inherits all methods from L<MojoX::Renderer> and
implements the following new ones.

=head2 C<new>

    my $renderer = Mojolicious::Renderer->new;

=cut
