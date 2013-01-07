package Mojolicious::Plugin;
use Mojo::Base -base;

use Carp 'croak';

sub register { croak 'Method "register" not implemented by subclass' }

1;

=head1 NAME

Mojolicious::Plugin - Plugin base class

=head1 SYNOPSIS

  # Camel case plugin name
  package Mojolicious::Plugin::MyPlugin;
  use Mojo::Base 'Mojolicious::Plugin';

  sub register {
    my ($self, $app, $conf) = @_;

    # Magic here! :)
  }

=head1 DESCRIPTION

L<Mojolicious::Plugin> is an abstract base class for L<Mojolicious> plugins.

=head1 METHODS

L<Mojolicious::Plugin> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);
  $plugin->register(Mojolicious->new, {foo => 'bar'});

This method will be called by L<Mojolicious::Plugins> at startup time. Meant
to be overloaded in a subclass.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
