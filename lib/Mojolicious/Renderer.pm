# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Renderer;

use strict;
use warnings;

use base 'MojoX::Renderer';

use File::Spec;
use Mojo::ByteStream 'b';
use Mojo::Command;
use Mojo::Template;

__PACKAGE__->attr(helper => sub { {} });

__PACKAGE__->attr(_epl_cache => sub { {} });

# What do you want?
# I'm here to kick your ass!
# Wishful thinking. We have long since evolved beyond the need for asses.
sub new {
    my $self = shift->SUPER::new(@_);

    # Add "epl" handler
    $self->add_handler(
        epl => sub {
            my ($r, $c, $output, $options) = @_;

            # Template
            my $t     = $r->template_name($options);
            my $path  = $r->template_path($options);
            my $cache = $options->{cache} || $path;

            # Check cache
            my $mt = $r->_epl_cache->{$cache};

            # Interpret again
            if ($mt && $mt->compiled) { $$output = $mt->interpret($c) }

            # No cache
            else {

                # Initialize
                $mt ||= Mojo::Template->new;

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
                        qq/Template "$t" missing or not readable./)
                      and return;
                }

                # Cache
                $r->_epl_cache->{$cache} = $mt;
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

    # Add "ep" handler
    $self->add_handler(
        ep => sub {
            my ($r, $c, $output, $options) = @_;

            # Generate name
            my $path  = $r->template_path($options);
            my $list  = join ', ', sort keys %{$c->stash};
            my $cache = $options->{cache} = b($list)->md5_sum->to_string;

            # Stash defaults
            $c->stash->{layout} ||= undef;

            # Cache
            unless ($r->_epl_cache->{$cache}) {

                # Debug
                $c->app->log->debug(
                    qq/Caching template "$path" with stash "$list"./);

                # Initialize
                my $mt = $r->_epl_cache->{$cache} = Mojo::Template->new;
                $mt->namespace("Mojo::Template::$cache");

                # Self
                my $prepend = 'my $self = shift;';

                # Be a bit more relaxed for helpers
                $prepend .= q/no strict 'refs'; no warnings 'redefine';/;

                # Helpers
                for my $name (sort keys %{$self->helper}) {
                    $prepend .= "sub $name;";
                    $prepend .= " *$name = sub { \$self->app->renderer";
                    $prepend .= "->helper->{'$name'}->(\$self, \@_) };";
                }

                # Be less relaxed for everything else
                $prepend .= q/use strict; use warnings;/;

                # Stash
                my $append = '';
                for my $var (keys %{$c->stash}) {
                    next unless $var =~ /^\w+$/;
                    $prepend .= " my \$$var = \$self->stash->{'$var'};";
                    $append  .= " \$self->stash->{'$var'} = \$$var;";
                }

                # Prepend
                $mt->prepend($prepend);

                # Append
                $mt->append($append);
            }

            # Render with epl
            return $r->handler->{epl}->($r, $c, $output, $options);
        }
    );

    # Add "url_for" helper
    $self->add_helper(url_for => sub { shift->url_for(@_) });

    # Set default handler to "epl"
    $self->default_handler('epl');

    return $self;
}

sub add_helper {
    my $self = shift;

    # Merge
    my $helper = ref $_[0] ? $_[0] : {@_};
    $helper = {%{$self->helper}, %$helper};
    $self->helper($helper);

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

L<Mojolicious::Renderer> inherits all attributes from L<MojoX::Renderer> and
implements the following new ones.

=head2 C<helper>

    my $helper = $renderer->helper;
    $renderer  = $renderer->helper({url_for => sub { ... }});

=head1 METHODS

L<Mojolicious::Renderer> inherits all methods from L<MojoX::Renderer> and
implements the following new ones.

=head2 C<new>

    my $renderer = Mojolicious::Renderer->new;

=head2 C<add_helper>

    $renderer = $renderer->add_helper(url_for => sub { ... });

=cut
