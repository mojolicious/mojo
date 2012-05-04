package Mojolicious::Plugin;
use Mojo::Base -base;

use Carp 'croak';

# "This is Fry's decision.
#  And he made it wrong, so it's time for us to interfere in his life."
sub register { croak 'Method "register" not implemented by subclass' }

1;

=head1 NAME

Mojolicious::Plugin - Plugin base class

=head1 SYNOPSIS

  use Mojo::Base 'Mojolicious::Plugin';

=head1 DESCRIPTION

L<Mojolicious::Plugin> is an abstract base class for L<Mojolicious> plugins.

=head1 METHODS

L<Mojolicious::Plugin> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<register>

  $plugin->register;

This method will be called by L<Mojolicious::Plugins> at startup time. Meant
to be overloaded in a subclass.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
