package Mojolicious::Plugin::EPLRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Template;
use Mojo::Util qw(encode md5_sum);

# "Clever things make people feel stupid and unexpected things make them feel
#  scared."
sub register {
  my ($self, $app) = @_;

  # Add "epl" handler
  $app->renderer->add_handler(epl => \&_epl);
}

sub _epl {
  my ($r, $c, $output, $options) = @_;

  # Template
  my $inline = $options->{inline};
  my $path   = $r->template_path($options);
  $path = md5_sum encode('UTF-8', $inline) if defined $inline;
  return unless defined $path;

  # Cached
  my $cache = $r->cache;
  my $key   = delete $options->{cache} || $path;
  my $mt    = $cache->get($key) || Mojo::Template->new;
  if ($mt->compiled) {
    $c->app->log->debug("Rendering cached @{[$mt->name]}.");
    $$output = $mt->interpret($c);
  }

  # Not cached
  else {

    # Inline
    if (defined $inline) {
      $c->app->log->debug('Rendering inline template.');
      $mt->name('inline template');
      $$output = $mt->render($inline, $c);
    }

    # File
    else {
      $mt->encoding($r->encoding) if $r->encoding;
      return unless my $t = $r->template_name($options);

      # Try template
      if (-r $path) {
        $c->app->log->debug(qq{Rendering template "$t".});
        $mt->name(qq{template "$t"});
        $$output = $mt->render_file($path, $c);
      }

      # Try DATA section
      elsif (my $d = $r->get_data_template($options, $t)) {
        $c->app->log->debug(qq{Rendering template "$t" from DATA section.});
        $mt->name(qq{template "$t" from DATA section});
        $$output = $mt->render($d, $c);
      }

      # No template
      else { $c->app->log->debug(qq{Template "$t" not found.}) and return }
    }

    # Cache
    $cache->set($key => $mt);
  }

  # Exception or success
  return ref $$output ? die($$output) : 1;
}

1;

=head1 NAME

Mojolicious::Plugin::EPLRenderer - Embedded Perl Lite renderer plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('EPLRenderer');

  # Mojolicious::Lite
  plugin 'EPLRenderer';

=head1 DESCRIPTION

L<Mojolicious::Plugin::EPLRenderer> is a renderer for C<epl> templates. C<epl>
templates are pretty much just raw L<Mojo::Template>.

This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins, you're welcome to fork it.

=head1 METHODS

L<Mojolicious::Plugin::EPLRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register(Mojolicious->new);

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
