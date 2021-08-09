package Mojolicious::Plugin::EPLRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Template;
use Mojo::Util qw(encode md5_sum);

sub register {
  my ($self, $app) = @_;
  $app->renderer->add_handler(epl => sub { _render(@_, Mojo::Template->new, $_[1]) });
}

sub _render {
  my ($renderer, $c, $output, $options, $mt, @args) = @_;

  # Cached
  if ($mt->compiled) {
    $c->helpers->log->trace("Rendering cached @{[$mt->name]}");
    $$output = $mt->process(@args);
  }

  # Not cached
  else {
    my $inline = $options->{inline};
    my $name   = defined $inline ? md5_sum encode('UTF-8', $inline) : undef;
    return unless defined($name //= $renderer->template_name($options));

    # Inline
    if (defined $inline) {
      $c->helpers->log->trace(qq{Rendering inline template "$name"});
      $$output = $mt->name(qq{inline template "$name"})->render($inline, @args);
    }

    # File
    else {
      if (my $encoding = $renderer->encoding) { $mt->encoding($encoding) }

      # Try template
      if (defined(my $path = $renderer->template_path($options))) {
        $c->helpers->log->trace(qq{Rendering template "$name"});
        $$output = $mt->name(qq{template "$name"})->render_file($path, @args);
      }

      # Try DATA section
      elsif (defined(my $d = $renderer->get_data_template($options))) {
        $c->helpers->log->trace(qq{Rendering template "$name" from DATA section});
        $$output = $mt->name(qq{template "$name" from DATA section})->render($d, @args);
      }

      # No template
      else { $c->helpers->log->trace(qq{Template "$name" not found}) }
    }
  }

  # Exception
  die $$output if ref $$output;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::EPLRenderer - Embedded Perl Lite renderer plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('EPLRenderer');

  # Mojolicious::Lite
  plugin 'EPLRenderer';

=head1 DESCRIPTION

L<Mojolicious::Plugin::EPLRenderer> is a renderer for C<epl> templates, which are pretty much just raw
L<Mojo::Template>.

This is a core plugin, that means it is always enabled and its code a good example for learning to build new plugins,
you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available by default.

=head1 METHODS

L<Mojolicious::Plugin::EPLRenderer> inherits all methods from L<Mojolicious::Plugin> and implements the following new
ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
