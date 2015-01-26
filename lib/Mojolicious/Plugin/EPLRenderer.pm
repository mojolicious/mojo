package Mojolicious::Plugin::EPLRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Template;
use Mojo::Util qw(encode md5_sum);

sub register { $_[1]->renderer->add_handler(epl => \&_epl) }

sub _epl {
  my ($renderer, $c, $output, $options) = @_;

  # Cached
  my $mt = delete $options->{'mojo.template'} || Mojo::Template->new;
  my $log = $c->app->log;
  if ($mt->compiled) {
    $log->debug("Rendering cached @{[$mt->name]}");
    $$output = $mt->interpret($c);
  }

  # Not cached
  else {
    my $inline = $options->{inline};
    my $name = defined $inline ? md5_sum encode('UTF-8', $inline) : undef;
    return undef unless defined($name //= $renderer->template_name($options));

    # Inline
    if (defined $inline) {
      $log->debug(qq{Rendering inline template "$name"});
      $$output = $mt->name(qq{inline template "$name"})->render($inline, $c);
    }

    # File
    else {
      if (my $encoding = $renderer->encoding) { $mt->encoding($encoding) }

      # Try template
      if (defined(my $path = $renderer->template_path($options))) {
        $log->debug(qq{Rendering template "$name"});
        $$output = $mt->name(qq{template "$name"})->render_file($path, $c);
      }

      # Try DATA section
      elsif (my $d = $renderer->get_data_template($options)) {
        $log->debug(qq{Rendering template "$name" from DATA section});
        $$output
          = $mt->name(qq{template "$name" from DATA section})->render($d, $c);
      }

      # No template
      else { $log->debug(qq{Template "$name" not found}) and return undef }
    }
  }

  # Exception or success
  return ref $$output ? die $$output : 1;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::EPLRenderer - Embedded Perl Lite renderer plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('EPLRenderer');

  # Mojolicious::Lite
  plugin 'EPLRenderer';

=head1 DESCRIPTION

L<Mojolicious::Plugin::EPLRenderer> is a renderer for C<epl> templates, which
are pretty much just raw L<Mojo::Template>.

This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins, you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available
by default.

=head1 METHODS

L<Mojolicious::Plugin::EPLRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
