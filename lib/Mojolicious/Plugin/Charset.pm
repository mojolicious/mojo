package Mojolicious::Plugin::Charset;
use Mojo::Base 'Mojolicious::Plugin';

# "Shut up friends. My internet browser heard us saying the word Fry and it
#  found a movie about Philip J. Fry for us.
#  It also opened my calendar to Friday and ordered me some french fries."
sub register {
  my ($self, $app, $conf) = @_;
  $conf ||= {};

  # Change default charset on all layers
  return unless my $charset = $conf->{charset};
  $app->types->type(html => "text/html;charset=$charset");
  $app->renderer->encoding($charset);
  $app->hook(after_build_tx => sub { shift->req->default_charset($charset) });
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::Charset - Charset plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin(Charset => {charset => 'Shift_JIS'});

  # Mojolicious::Lite
  plugin Charset => {charset => 'Shift_JIS'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::Charset> is a plugin to easily set the default charset
and encoding on all layers of L<Mojolicious>.

=head1 OPTIONS

L<Mojolicious::Plugin::Charset> supports the following options.

=head2 C<charset>

  # Mojolicious::Lite
  plugin Charset => {charset => 'Shift_JIS'};

Application charset.

=head1 METHODS

L<Mojolicious::Plugin::Charset> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register;

Register plugin hooks in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
