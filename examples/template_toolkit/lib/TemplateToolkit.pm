package TemplateToolkit;
use Mojo::Base 'Mojolicious';

sub startup {
  my $self = shift;

  # See documentation for Mojolicious::Plugin::TtRenderer for details.
  $self->plugin('tt_renderer' => {template_options => {WRAPPER => 'layouts/default.html.tt'}});

  $self->routes->get('/')->to('home#index');
}

1;
