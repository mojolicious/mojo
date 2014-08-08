package Mojolicious::Renderer::Helpers;
use Mojo::Base -base;

use Carp 'croak';
use Scalar::Util 'blessed';

has [qw(controller prefix)];

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = split /::(\w+)$/, our $AUTOLOAD;
  croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  my $c    = $self->controller;
  my $name = $self->prefix . ".$method";
  croak qq{Can't locate object method "$method" via package "$package"}
    unless my $helper = $c->app->renderer->get_helper($name);
  return $c->$helper(@_);
}

1;
