package Mojolicious::Plugin::EPRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Template;
use Mojo::Util qw(encode md5_sum);
use Scalar::Util ();

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
      my $id = encode 'UTF-8', join(', ', $path, sort keys %{$c->stash});
      my $key = $options->{cache} = md5_sum $id;

      # Compile helpers and stash values
      my $cache = $renderer->cache;
      unless ($cache->get($key)) {
        my $mt = Mojo::Template->new($template);

        # Be a bit more relaxed for helpers
        my $prepend = 'my $self = shift; Scalar::Util::weaken $self;'
          . q[no strict 'refs'; no warnings 'redefine';];

        # Helpers
        $prepend .= 'my $_H = $self->app->renderer->helpers;';
        $prepend .= "sub $_; *$_ = sub { \$_H->{'$_'}->(\$self, \@_) };"
          for grep {/^\w+$/} keys %{$renderer->helpers};

        # Be less relaxed for everything else
        $prepend .= 'use strict;';

        # Stash values
        $prepend .= 'my $_S = $self->stash;';
        $prepend .= " my \$$_ = \$_S->{'$_'};"
          for grep {/^\w+$/} keys %{$c->stash};

        # Cache
        $cache->set($key => $mt->prepend($prepend . $mt->prepend));
      }

      # Render with "epl" handler
      return $renderer->handlers->{epl}->($renderer, $c, $output, $options);
    }
  );
}

1;

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
