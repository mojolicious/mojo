# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Renderer;

use strict;
use warnings;

use base 'MojoX::Renderer';

use File::Spec;
use Mojo::Template;

# What do you want?
# I'm here to kick your ass!
# Wishful thinking. We have long since evolved beyond the need for asses.
sub new {
    my $self = shift->SUPER::new(@_);

    # Epl
    $self->add_handler(
        epl => sub {
            my ($r, $c, $output) = @_;

            # Template
            my $template = $c->stash->{template};
            my $path =
              File::Spec->catfile($c->app->renderer->root, $template);

            # Initialize cache
            $r->{_mt_cache} ||= {};

            # Shortcut
            unless (-r $path || $r->{_mt_cache}->{$path}) {
                $c->app->log->error(
                    qq/Template "$template" missing or not readable./);
                return;
            }

            # Check cache
            my $mt = $r->{_mt_cache}->{$path};

            # Interpret again
            if ($mt) { $$output = $mt->interpret($c) }

            # No cache
            else {

                # Initialize
                $mt = $r->{_mt_cache}->{$path} = Mojo::Template->new;
                $$output = $mt->render_file($path, $c);
            }

            # Exception
            if (ref $$output) {
                my $e = $$output;
                $$output = '';

                # Log
                $c->app->log->error(qq/Template error in "$template": $e/);

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
                            template => 'exception.html'
                        )
                    );

                    return 1;
                }
            }

            # Success or exception?
            return ref $$output ? 0 : 1;
        }
    );

    # Eplite
    $self->add_handler(
        eplite => sub {
            my ($r, $c, $output) = @_;

            # Template
            my $template = $c->stash->{template};

            # Class
            my $class =
                 delete $c->stash->{eplite_class}
              || $ENV{MOJO_EPLITE_CLASS}
              || 'main';

            # Path
            my $path =
              File::Spec->catfile($c->app->renderer->root, $template);

            # Prepare
            unless ($r->{_mt_cache}->{$path}) {

                # Portable templates
                $template = join '/', File::Spec->splitdir($template);

                # Data
                my $d = Mojo::Script->new->get_data($template, $class);
                unless ($d) {

                    # Nothing found
                    $c->app->log->debug(
                        qq/Template "$template" not found in class "$class"./
                    );
                    return;
                }

                # Template
                my $t = Mojo::Template->new;
                $t->namespace($class);
                $t->parse($d);
                $t->build;
                $r->{_mt_cache}->{$path} = $t;
            }

            # Render
            return $r->handler->{epl}->($r, $c, $output);
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
