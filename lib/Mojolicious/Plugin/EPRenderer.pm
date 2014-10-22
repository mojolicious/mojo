package Mojolicious::Plugin::EPRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Template;
use Mojo::Util qw(encode md5_sum monkey_patch);

sub DESTROY { Mojo::Util::_teardown(shift->{namespace}) }

sub register {
  my ($self, $app, $conf) = @_;

  # Auto escape by default to prevent XSS attacks
  my $template = {auto_escape => 1, %{$conf->{template} || {}}};
  my $ns = $self->{namespace} = $template->{namespace}
    //= 'Mojo::Template::Sandbox::' . md5_sum "$self";

  # Add "ep" handler and make it the default
  $app->renderer->default_handler('ep')->add_handler(
    $conf->{name} || 'ep' => sub {
      my ($renderer, $c, $output, $options) = @_;

      my $name = $options->{inline} // $renderer->template_name($options);
      return undef unless defined $name;
      my @keys = sort grep {/^\w+$/} keys %{$c->stash};
      my $key = md5_sum encode 'UTF-8', join(',', $name, @keys);

      # Prepare template for "epl" handler
      my $cache = $renderer->cache;
      unless ($options->{'mojo.template'} = $cache->get($key)) {
        my $mt = $options->{'mojo.template'} = Mojo::Template->new($template);

        # Helpers (only once)
        ++$self->{helpers} and _helpers($ns, $renderer->helpers)
          unless $self->{helpers};

        # Stash values (every time)
        my $prepend = 'my $self = my $c = shift; my $_S = $c->stash; {';
        $prepend .= join '', map {" my \$$_ = \$_S->{'$_'};"} @keys;
        $mt->prepend($prepend . $mt->prepend)->append('}' . $mt->append);

        $cache->set($key => $mt);
      }

      # Make current controller available
      no strict 'refs';
      no warnings 'redefine';
      local *{"${ns}::_C"} = sub {$c};

      # Render with "epl" handler
      return $renderer->handlers->{epl}->($renderer, $c, $output, $options);
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
  $self->plugin('EPRenderer');
  $self->plugin(EPRenderer => {name => 'foo'});
  $self->plugin(EPRenderer => {template => {line_start => '.'}});

  # Mojolicious::Lite
  plugin 'EPRenderer';
  plugin EPRenderer => {name => 'foo'};
  plugin EPRenderer => {template => {line_start => '.'}};

=head1 DESCRIPTION

L<Mojolicious::Plugin::EPRenderer> is a renderer for C<ep> or C<Embedded Perl>
templates.

C<Embedded Perl> is a simple template format where you embed perl code into
documents. It is based on L<Mojo::Template>, but extends it with some
convenient syntax sugar designed specifically for L<Mojolicious>. It supports
L<Mojolicious> template helpers and exposes the stash directly as Perl
variables.

This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins, you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available
by default.

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
