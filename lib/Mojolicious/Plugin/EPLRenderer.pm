package Mojolicious::Plugin::EPLRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Template;
use Mojo::Util qw(encode md5_sum);

sub register { $_[1]->renderer->add_handler(epl => \&_epl) }

sub _epl {
  my ($renderer, $c, $output, $options) = @_;

  # Template
  my $inline = $options->{inline};
  my $path   = $renderer->template_path($options);
  $path = md5_sum encode('UTF-8', $inline) if defined $inline;
  return undef unless defined $path;

  # Cached
  my $key   = delete $options->{cache} || $path;
  my $cache = $renderer->cache;
  my $mt    = $cache->get($key);
  $mt ||= $cache->set($key => Mojo::Template->new)->get($key);
  my $log = $c->app->log;
  if ($mt->compiled) {
    $log->debug("Rendering cached @{[$mt->name]}.");
    $$output = $mt->interpret($c);
  }

  # Not cached
  else {

    # Inline
    if (defined $inline) {
      $log->debug('Rendering inline template.');
      $$output = $mt->name('inline template')->render($inline, $c);
    }

    # File
    else {
      $mt->encoding($renderer->encoding) if $renderer->encoding;
      return undef unless my $t = $renderer->template_name($options);

      # Try template
      if (-r $path) {
        $log->debug(qq{Rendering template "$t".});
        $$output = $mt->name(qq{template "$t"})->render_file($path, $c);
      }

      # Try DATA section
      elsif (my $d = $renderer->get_data_template($options)) {
        $log->debug(qq{Rendering template "$t" from DATA section.});
        $$output
          = $mt->name(qq{template "$t" from DATA section})->render($d, $c);
      }

      # No template
      else { $log->debug(qq{Template "$t" not found.}) and return undef }
    }
  }

  # Exception or success
  return ref $$output ? die $$output : 1;
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

=head2 register

  $plugin->register(Mojolicious->new);

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
