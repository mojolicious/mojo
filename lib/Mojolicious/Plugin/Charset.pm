package Mojolicious::Plugin::Charset;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

# Shut up friends. My internet browser heard us saying the word Fry and it
# found a movie about Philip J. Fry for us.
# It also opened my calendar to Friday and ordered me some french fries.
sub register {
    my ($self, $app, $conf) = @_;

    # Config
    $conf ||= {};

    # Set charset
    $app->hook(
        before_dispatch => sub {
            my $self = shift;

            # Got a charset
            if (my $charset = $conf->{charset}) {

                # This has to be done before params are cloned
                $self->tx->req->default_charset($charset);

                # Add charset to text/html content type
                my $type = $self->app->types->type('html');
                unless ($type =~ /charset=/) {
                    $type .= ";charset=$charset";
                    $self->app->types->type(html => $type);
                }
            }

            # Allow defined but blank encoding to suppress unwanted
            # conversion
            my $encoding =
              defined $conf->{encoding}
              ? $conf->{encoding}
              : $conf->{charset};
            $self->app->renderer->encoding($encoding) if $encoding;
        }
    );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::Charset - Charset Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin(charset => {charset => 'Shift_JIS'});

    # Mojolicious::Lite
    plugin charset => {charset => 'Shift_JIS'};

=head1 DESCRIPTION

L<Mojolicous::Plugin::Charset> is a plugin to easily set the default charset
and encoding on all layers of L<Mojolicious>.

=head2 Options

=over 4

=item charset

=back

=head1 METHODS

L<Mojolicious::Plugin::Charset> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register plugin hooks in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
