package Mojolicious::Plugin::EPRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Template;
use Mojo::Util qw(encode md5_sum);
use Scalar::Util ();

sub register {
  my ($self, $app, $conf) = @_;

  # Auto escape by default to prevent XSS attacks
  my $template = {auto_escape => 1, %{$conf->{template} || {}}};

  # Add "ep" handler
  $app->renderer->add_handler(
    $conf->{name} || 'ep' => sub {
      my ($r, $c, $output, $options) = @_;

      # Generate name
      my $path = $options->{inline} || $r->template_path($options);
      return unless defined $path;
      my $id = encode 'UTF-8', join(', ', $path, sort keys %{$c->stash});
      my $key = $options->{cache} = md5_sum $id;

      # Compile helpers and stash values
      my $cache = $r->cache;
      unless ($cache->get($key)) {
        my $mt = Mojo::Template->new($template);

        # Be a bit more relaxed for helpers
        my $prepend = q[my $self = shift; Scalar::Util::weaken $self;]
          . q[no strict 'refs'; no warnings 'redefine';];

        # Helpers
        $prepend .= 'my $_H = $self->app->renderer->helpers;';
        $prepend .= "sub $_; *$_ = sub { \$_H->{'$_'}->(\$self, \@_) };"
          for grep {/^\w+$/} keys %{$r->helpers};

        # Be less relaxed for everything else
        $prepend .= 'use strict;';

        # Stash
        $prepend .= 'my $_S = $self->stash;';
        $prepend .= " my \$$_ = \$_S->{'$_'};"
          for grep {/^\w+$/} keys %{$c->stash};

        # Cache
        $cache->set($key => $mt->prepend($prepend . $mt->prepend));
      }

      # Render with "epl" handler
      return $r->handlers->{epl}->($r, $c, $output, $options);
    }
  );

  # Set default handler
  $app->renderer->default_handler('ep');
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

=head2 C<name>

  # Mojolicious::Lite
  plugin EPRenderer => {name => 'foo'};

Handler name.

=head2 C<template>

  # Mojolicious::Lite
  plugin EPRenderer => {template => {line_start => '.'}};

Attribute values passed to L<Mojo::Template> object used to render templates.

=head1 METHODS

L<Mojolicious::Plugin::EPRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register(Mojolicious->new);
  $plugin->register(Mojolicious->new, {name => 'foo'});

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
