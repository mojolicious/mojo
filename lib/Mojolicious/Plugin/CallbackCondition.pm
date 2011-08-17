package Mojolicious::Plugin::CallbackCondition;
use Mojo::Base 'Mojolicious::Plugin';

# "Stop being such a spineless jellyfish!
#  You know full well I'm more closely related to the sea cucumber.
#  Not where it counts."
sub register {
  my ($self, $app) = @_;

  # "cb" condition
  $app->routes->add_condition(
    cb => sub {
      my ($r, $c, $captures, $cb) = @_;
      return unless $cb && ref $cb eq 'CODE';
      $r->$cb($c, $captures);
    }
  );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::CallbackCondition - Callback Condition Plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('CallbackCondition');
  $self->routes->route('/:controller/:action')->over(cb => sub {
    my ($r, $c, $captures) = @_;
    ...
  });

  # Mojolicious::Lite
  plugin 'CallbackCondition';
  get '/' => (cb => sub {
    my ($r, $c, $captures) = @_;
    ...
  }) => sub {...};

=head1 DESCRIPTION

L<Mojolicious::Plugin::CallbackCondition> is a routes condition for
callbacks.
This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojolicious::Plugin::CallbackCondition> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register;

Register condition in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
