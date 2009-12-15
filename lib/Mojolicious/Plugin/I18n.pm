package Mojolicious::Plugin::I18n;

use strict;
use warnings;
use base 'Mojolicious::Plugin';

sub register {
    my ($self, $app, $conf) = @_;

    $conf ||= {};

    $app->plugins->add_hook(
        before_dispatch => sub {
            my ($self, $c) = @_;

            if (my $charset = $conf->{charset}) {
                # We need to do this before we clone params
                $c->tx->req->default_charset($charset);

                # We should add charset to text/html content type
                my $type = $c->app->types->type('html');
                unless ($type =~ /charset=/) {
                    $type .= ";charset=$charset";
                    $c->app->types->type(html => $type);
                }
            }

            # Allow defined but blank encoding to suppress unwanted
            # conversion
            my $encoding = (defined $conf->{encoding})
                ? $conf->{encoding}
                : $conf->{charset};
            $c->app->renderer->encoding($encoding) if $encoding;
        }
    );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::I18n - Internationalization

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('i18n', { charset => 'Shift_JIS' });

    # Mojolicious::Lite
    plugin 'i18n', { charset => 'Shift_JIS' };

=head1 DESCRIPTION

L<Mojolicous::Plugin::I18n> is a plugin to set charset and encoding.

=head1 METHODS

L<Mojolicious::Plugin::I18n> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

=cut
