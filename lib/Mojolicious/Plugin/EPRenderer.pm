package Mojolicious::Plugin::EPRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Template;
use Mojo::Util qw(encode md5_sum monkey_patch);

sub register {
  my ($self, $app, $conf) = @_;

  # Auto escape by default to prevent XSS attacks
  my $template = {auto_escape => 1, %{$conf->{template} || {}}};

  # Add "ep" handler and make it the default
  $app->renderer->default_handler('ep')->add_handler(
    $conf->{name} || 'ep' => sub {
      my ($renderer, $c, $output, $options) = @_;

      # Generate name
      my $path = $options->{inline} || $renderer->template_path($options);
      return undef unless defined $path;
      my @keys = sort grep {/^\w+$/} keys %{$c->stash};
      my $id = encode 'UTF-8', join(',', $path, @keys);
      my $key = $options->{cache} = md5_sum $id;

      # Cache template for "epl" handler
      my $cache = $renderer->cache;
      my $mt    = $cache->get($key);
      unless ($mt) {
        $mt = Mojo::Template->new($template);

        # Helpers (only once)
        ++$self->{helpers} and _helpers($mt->namespace, $renderer->helpers)
          unless $self->{helpers};

        # Stash values (every time)
        my $prepend = 'my $self = shift; my $_S = $self->stash;';
        $prepend .= " my \$$_ = \$_S->{'$_'};" for @keys;

        $cache->set($key => $mt->prepend($prepend . $mt->prepend));
      }

      # Make current controller available
      no strict 'refs';
      no warnings 'redefine';
      local *{"@{[$mt->namespace]}::_C"} = sub {$c};

      # Render with "epl" handler
      return $renderer->handlers->{epl}->($renderer, $c, $output, $options);
    }
  );
}

sub _helpers {
  my ($namespace, $helpers) = @_;
  for my $name (grep {/^\w+$/} keys %$helpers) {
    monkey_patch $namespace, $name,
      sub { $helpers->{$name}->($namespace->_C, @_) };
  }
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::EPRenderer - Embedded Perl renderer plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('EPRenderer');
  $self->plugin(EPRenderer => {name => 'foo'});
  $self->plugin(EPRenderer => {template => {line_start => '.'}});

  # Mojolicious::Lite
  plugin 'EPRenderer';
  plugin EPRenderer => {name => 'foo'};
  plugin EPRenderer => {template => {line_start => '.'}};

=head1 DESCRIPTION

L<Mojolicious::Plugin::EPRenderer> is a renderer for C<ep> templates.

C<ep> or C<Embedded Perl> is a simple template format where you embed perl
code into documents. It is based on L<Mojo::Template>, but extends it with
some convenient syntax sugar designed specifically for L<Mojolicious>. It
supports L<Mojolicious> template helpers and exposes the stash directly as
Perl variables.

This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins, you're welcome to fork it.

=head1 OPTIONS

L<Mojolicious::Plugin::EPRenderer> supports the following options.

=head2 name

  # Mojolicious::Lite
  plugin EPRenderer => {name => 'foo'};

Handler name, defaults to C<ep>.

=head2 template

  # Mojolicious::Lite
  plugin EPRenderer => {template => {line_start => '.'}};

Attribute values passed to L<Mojo::Template> object used to render templates.

=head1 METHODS

L<Mojolicious::Plugin::EPRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);
  $plugin->register(Mojolicious->new, {name => 'foo'});

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
