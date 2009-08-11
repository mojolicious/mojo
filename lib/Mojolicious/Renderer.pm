# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Renderer;

use strict;
use warnings;

use base 'MojoX::Renderer';

use File::Spec;
use Mojo::Template;

__PACKAGE__->attr(_epl_cache => sub { {} });

# What do you want?
# I'm here to kick your ass!
# Wishful thinking. We have long since evolved beyond the need for asses.
sub new {
    my $self = shift->SUPER::new(@_);

    # Epl
    $self->add_handler(
        epl => sub {
            my ($r, $c, $output, $options) = @_;

            # Template
            my $t    = $r->template_name($options);
            my $path = $r->template_path($options);

            # Check cache
            my $mt = $r->_epl_cache->{$path};

            # Interpret again
            if ($mt) { $$output = $mt->interpret($c) }

            # No cache
            else {

                # Initialize
                $mt = Mojo::Template->new;

                # Class
                my $class =
                     $c->stash->{template_class}
                  || $ENV{MOJO_TEMPLATE_CLASS}
                  || 'main';

                # Try template
                if (-r $path) { $$output = $mt->render_file($path, $c) }

                # Try DATA section
                elsif (my $d = Mojo::Script->new->get_data($t, $class)) {
                    $mt->namespace($class);
                    $$output = $mt->render($d, $c);
                }

                # No template
                else {
                    $c->app->log->error(
                        qq/Template "$t" missing or not readable./)
                      and return;
                }

                # Cache
                $r->_epl_cache->{$path} = $mt;
            }

            # Exception
            if (ref $$output) {
                my $e = $$output;
                $$output = '';

                # Log
                $c->app->log->error(qq/Template error in "$t": $e/);

                # Development mode
                if ($c->app->mode eq 'development') {

                    # Exception template failed
                    return if $c->stash->{exception};

                    # Render exception template
                    $c->stash(exception => $e);
                    $c->res->code(500);
                    $c->res->body(
                        $c->render(
                            partial  => 1,
                            template => 'exception',
                            format   => 'html'
                        )
                    );

                    return 1;
                }
            }

            # Success or exception?
            return ref $$output ? 0 : 1;
        }
    );

    # Set default handler to "epl"
    $self->default_handler('epl');

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
