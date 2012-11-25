package Locales;
use Mojo::Base 'Mojolicious';

sub startup {
  my $self = shift;

  $self->plugin(charset => {charset           => 'utf8'});
  $self->plugin(I18N    => {support_url_langs => [qw( ms )]});

  # We use TT as xgettext.pl has support for TT parsing.
  $self->plugin('tt_renderer' => {template_options => {WRAPPER => 'layouts/default.html.tt'}});

  $self->routes->get('/')->to('example#welcome');
}

1;
