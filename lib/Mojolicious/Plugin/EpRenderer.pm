# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugin::EpRenderer;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::ByteStream 'b';
use Mojo::Template;

# What do you want?
# I'm here to kick your ass!
# Wishful thinking. We have long since evolved beyond the need for asses.
sub register {
    my ($self, $app) = @_;

    # Add "ep" handler
    $app->renderer->add_handler(
        ep => sub {
            my ($r, $c, $output, $options) = @_;

            # Generate name
            my $path  = $r->template_path($options);
            my $list  = join ', ', sort keys %{$c->stash};
            my $cache = $options->{cache} =
              b("$path($list)")->md5_sum->to_string;

            # Stash defaults
            $c->stash->{layout} ||= undef;

            # Cache
            $r->{_epl_cache} ||= {};
            unless ($r->{_epl_cache}->{$cache}) {

                # Debug
                $c->app->log->debug(
                    qq/Caching template "$path" with stash "$list"./);

                # Initialize
                my $mt = $r->{_epl_cache}->{$cache} = Mojo::Template->new;
                $mt->namespace("Mojo::Template::$cache");

                # Auto escape by default to prevent XSS attacks
                $mt->auto_escape(1);

                # Self
                my $prepend = 'my $self = shift;';

                # Be a bit more relaxed for helpers
                $prepend .= q/no strict 'refs'; no warnings 'redefine';/;

                # Helpers
                for my $name (sort keys %{$r->helper}) {
                    next unless $name =~ /^\w+$/;
                    $prepend .= "sub $name;";
                    $prepend .= " *$name = sub { \$self->app->renderer";
                    $prepend .= "->helper->{'$name'}->(\$self, \@_) };";
                }

                # Be less relaxed for everything else
                $prepend .= q/use strict; use warnings;/;

                # Stash
                for my $var (keys %{$c->stash}) {
                    next unless $var =~ /^\w+$/;
                    $prepend .= " my \$$var = \$self->stash->{'$var'};";
                }

                # Prepend
                $mt->prepend($prepend);
            }

            # Render with epl
            return $r->handler->{epl}->($r, $c, $output, $options);
        }
    );

    # Set default handler
    $app->renderer->default_handler('ep');
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::EpRenderer - EP Renderer Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('ep_renderer');

    # Mojolicious::Lite
    plugin 'ep_renderer';

=head1 DESCRIPTION

L<Mojolicous::Plugin::EpRenderer> is a renderer for C<ep> templates.

=head1 METHODS

L<Mojolicious::Plugin::EpRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

=cut
