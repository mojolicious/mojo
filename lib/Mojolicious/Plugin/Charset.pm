package Mojolicious::Plugin::Charset;
use Mojo::Base 'Mojolicious::Plugin';

# "Shut up friends. My internet browser heard us saying the word Fry and it
#  found a movie about Philip J. Fry for us.
#  It also opened my calendar to Friday and ordered me some french fries."
sub register {
  my ($self, $app, $conf) = @_;

  # Got a charset
  $conf ||= {};
  if (my $charset = $conf->{charset}) {

    # Add charset to text/html content type
    $app->types->type(html => "text/html;charset=$charset");

    # Allow defined but blank encoding to suppress unwanted
    # conversion
    my $encoding =
      defined $conf->{encoding}
      ? $conf->{encoding}
      : $conf->{charset};
    $app->renderer->encoding($encoding) if $encoding;

    # This has to be done before params are cloned
    $app->hook(after_build_tx => sub { shift->req->default_charset($charset) }
    );
  }
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

L<Mojolicious::Plugin::Charset> is a plugin to easily set the default charset
and encoding on all layers of L<Mojolicious>.

=head1 OPTIONS

=head2 C<charset>

  # Mojolicious::Lite
  plugin charset => {charset => 'Shift_JIS'};

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
