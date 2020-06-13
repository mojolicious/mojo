package Mojolicious::Plugin::EPRenderer;
use Mojo::Base 'Mojolicious::Plugin::EPLRenderer';

use Mojo::Template;
use Mojo::Util qw(encode md5_sum monkey_patch);

sub DESTROY { Mojo::Util::_teardown(shift->{namespace}) }

sub register {
  my ($self, $app, $conf) = @_;

  # Auto escape by default to prevent XSS attacks
  my $ep = {auto_escape => 1, %{$conf->{template} || {}}, vars => 1};
  my $ns = $self->{namespace} = $ep->{namespace} //= 'Mojo::Template::Sandbox::' . md5_sum "$self";

  # Make "$self" and "$c" available in templates
  $ep->{prepend} = 'my $self = my $c = _C;' . ($ep->{prepend} // '');

  # Add "ep" handler and make it the default
  $app->renderer->default_handler('ep')->add_handler(
    $conf->{name} || 'ep' => sub {
      my ($renderer, $c, $output, $options) = @_;

      my $name = $options->{inline} // $renderer->template_name($options);
      return unless defined $name;
      my $key = md5_sum encode 'UTF-8', $name;

      my $cache = $renderer->cache;
      my $mt    = $cache->get($key);
      $cache->set($key => $mt = Mojo::Template->new($ep)) unless $mt;

      # Export helpers only once
      ++$self->{helpers} and _helpers($ns, $renderer->helpers) unless $self->{helpers};

      # Make current controller available and render with "epl" handler
      no strict 'refs';
      no warnings 'redefine';
      local *{"${ns}::_C"} = sub {$c};
      Mojolicious::Plugin::EPLRenderer::_render($renderer, $c, $output, $options, $mt, $c->stash);
    }
  );
}

sub _helpers {
  my ($class, $helpers) = @_;
  for my $method (grep {/^\w+$/} keys %$helpers) {
    my $sub = $helpers->{$method};
    monkey_patch $class, $method, sub { $class->_C->$sub(@_) };
  }
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::EPRenderer - Embedded Perl renderer plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('EPRenderer');
  $app->plugin(EPRenderer => {name => 'foo'});
  $app->plugin(EPRenderer => {name => 'bar', template => {line_start => '.'}});

  # Mojolicious::Lite
  plugin 'EPRenderer';
  plugin EPRenderer => {name => 'foo'};
  plugin EPRenderer => {name => 'bar', template => {line_start => '.'}};

=head1 DESCRIPTION

L<Mojolicious::Plugin::EPRenderer> is a renderer for Embedded Perl templates. For more information see
L<Mojolicious::Guides::Rendering/"Embedded Perl">.

This is a core plugin, that means it is always enabled and its code a good example for learning to build new plugins,
you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available by default.

=head1 OPTIONS

L<Mojolicious::Plugin::EPRenderer> supports the following options.

=head2 name

  # Mojolicious::Lite
  plugin EPRenderer => {name => 'foo'};

Handler name, defaults to C<ep>.

=head2 template

  # Mojolicious::Lite
  plugin EPRenderer => {template => {line_start => '.'}};

Attribute values passed to L<Mojo::Template> objects used to render templates.

=head1 METHODS

L<Mojolicious::Plugin::EPRenderer> inherits all methods from L<Mojolicious::Plugin::EPLRenderer> and implements the
following new ones.

=head2 register

  $plugin->register(Mojolicious->new);
  $plugin->register(Mojolicious->new, {name => 'foo'});

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
