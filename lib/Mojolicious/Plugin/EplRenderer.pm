# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Plugin::EplRenderer;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::Command;
use Mojo::Template;

# Clever things make people feel stupid and unexpected things make them feel
# scared.
sub register {
    my ($self, $app) = @_;

    # Add "epl" handler
    $app->renderer->add_handler(
        epl => sub {
            my ($r, $c, $output, $options) = @_;

            # Template
            return unless my $t    = $r->template_name($options);
            return unless my $path = $r->template_path($options);
            my $cache = $options->{cache} || $path;

            # Check cache
            $r->{_epl_cache} ||= {};
            my $mt = $r->{_epl_cache}->{$cache};

            # Interpret again
            if ($mt && $mt->compiled) { $$output = $mt->interpret($c) }

            # No cache
            else {

                # Initialize
                $mt ||= Mojo::Template->new;

                # Encoding
                $mt->encoding($app->renderer->encoding)
                  if $app->renderer->encoding;

                # Class
                my $class =
                     $c->stash->{template_class}
                  || $ENV{MOJO_TEMPLATE_CLASS}
                  || 'main';

                # Try template
                if (-r $path) { $$output = $mt->render_file($path, $c) }

                # Try DATA section
                elsif (my $d = Mojo::Command->new->get_data($t, $class)) {
                    $$output = $mt->render($d, $c);
                }

                # No template
                else {
                    $c->app->log->error(
                        qq/Template "$t" missing or not readable./);
                    my $options = {
                        template  => 'not_found',
                        format    => 'html',
                        status    => 404,
                        not_found => 1
                    };
                    $c->app->static->serve_404($c)
                      if $c->stash->{not_found} || !$c->render($options);
                    return;
                }

                # Cache
                $r->{_epl_cache}->{$cache} = $mt;
            }

            # Exception
            if (ref $$output) {
                my $e = $$output;
                $$output = '';

                # Log
                $c->app->log->error(qq/Template error in "$t": $e/);

                # Render exception template
                my $options = {
                    template  => 'exception',
                    format    => 'html',
                    status    => 500,
                    exception => $e
                };
                $c->app->static->serve_500($c)
                  if $c->stash->{exception} || !$c->render($options);
            }

            # Success or exception?
            return ref $$output ? 0 : 1;
        }
    );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::EplRenderer - EPL Renderer Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('epl_renderer');

    # Mojolicious::Lite
    plugin 'epl_renderer';

=head1 DESCRIPTION

L<Mojolicous::Plugin::EplRenderer> is a renderer for C<epl> templates.

=head1 METHODS

L<Mojolicious::Plugin::EplRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

=cut
