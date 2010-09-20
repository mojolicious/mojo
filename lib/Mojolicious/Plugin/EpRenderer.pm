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
    my ($self, $app, $conf) = @_;

    # Config
    $conf ||= {};
    my $name     = $conf->{name}     || 'ep';
    my $template = $conf->{template} || {};

    # Auto escape by default to prevent XSS attacks
    $template->{auto_escape} = 1 unless defined $template->{auto_escape};

    # Add "ep" handler
    $app->renderer->add_handler(
        $name => sub {
            my ($r, $c, $output, $options) = @_;

            # Generate name
            my $path = $r->template_path($options) || $options->{inline};
            return unless defined $path;
            my $list = join ', ', sort keys %{$c->stash};
            my $cache = $options->{cache} =
              b("$path($list)")->md5_sum->to_string;

            # Stash defaults
            $c->stash->{layout} ||= undef;

            # Reload
            delete $r->{_epl_cache} if $ENV{MOJO_RELOAD};
            local $ENV{MOJO_RELOAD} = 0 if $ENV{MOJO_RELOAD};

            # Cache
            my $ec = $r->{_epl_cache} ||= {};
            unless ($ec->{$cache}) {

                # Initialize
                $template->{namespace} ||= "Mojo::Template::$cache";
                my $mt = $ec->{$cache} = Mojo::Template->new($template);

                # Self
                my $prepend = 'my $self = shift;';

                # Weaken
                $prepend .= q/use Scalar::Util 'weaken'; weaken $self;/;

                # Be a bit more relaxed for helpers
                $prepend .= q/no strict 'refs'; no warnings 'redefine';/;

                # Helpers
                $prepend .= 'my $_H = $self->app->renderer->helper;';
                for my $name (sort keys %{$r->helper}) {
                    next unless $name =~ /^\w+$/;
                    $prepend .= "sub $name; *$name = sub { ";
                    $prepend .= "return \$_H->{'$name'}->(\$self, \@_) };";
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
    $self->plugin(ep_renderer => {name => 'foo'});
    $self->plugin(ep_renderer => {template => {line_start => '.'}});

    # Mojolicious::Lite
    plugin 'ep_renderer';
    plugin ep_renderer => {name => 'foo'};
    plugin ep_renderer => {template => {line_start => '.'}};

=head1 DESCRIPTION

L<Mojolicous::Plugin::EpRenderer> is a renderer for C<ep> templates.

=head1 TEMPLATES

C<ep> or C<Embedded Perl> is a simple template format where you embed perl
code into documents.
It is based on L<Mojo::Template>, but extends it with some convenient syntax
sugar designed specifically for L<Mojolicious>.
It supports L<Mojolicious> template helpers and exposes the stash directly as
perl variables.

=head2 Options

=over 4

=item name

    # Mojolicious::Lite
    plugin ep_renderer => {name => 'foo'};

=item template

    # Mojolicious::Lite
    plugin ep_renderer => {template => {line_start => '.'}};

=back

=head1 METHODS

L<Mojolicious::Plugin::EpRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
