# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoX::Renderer;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use Mojo::JSON;
use MojoX::Types;

__PACKAGE__->attr(default_format => 'html');
__PACKAGE__->attr('default_handler');
__PACKAGE__->attr(default_status => 200);
__PACKAGE__->attr(handler        => sub { {} });
__PACKAGE__->attr(layout_prefix  => 'layouts');
__PACKAGE__->attr(root           => '/');
__PACKAGE__->attr(types          => sub { MojoX::Types->new });

# This is not how Xmas is supposed to be.
# In my day Xmas was about bringing people together, not blowing them apart.
sub new {
    my $self = shift->SUPER::new(@_);

    # JSON
    $self->add_handler(
        json => sub {
            my ($r, $c, $output) = @_;
            $$output = Mojo::JSON->new->encode(delete $c->stash->{json});
        }
    );

    # Text
    $self->add_handler(
        text => sub {
            my ($r, $c, $output) = @_;
            $$output = delete $c->stash->{text};
        }
    );
}

sub add_handler {
    my $self = shift;

    # Merge
    my $handler = ref $_[0] ? $_[0] : {@_};
    $handler = {%{$self->handler}, %$handler};
    $self->handler($handler);

    return $self;
}

# Bodies are for hookers and fat people.
sub render {
    my ($self, $c) = @_;

    # We got called
    $c->stash->{rendered} = 1;

    # Partial?
    my $partial = delete $c->stash->{partial};

    # Template
    my $template = delete $c->stash->{template};

    # Format
    my $format = $c->stash->{format} || $self->default_format;

    # Handler
    my $handler = $c->stash->{handler} || $self->default_handler;

    my $options =
      {template => $template, format => $format, handler => $handler};
    my $output;

    # Text
    if ($c->stash->{text}) {

        # Render
        $self->handler->{text}->($self, $c, \$output);

        # Layout?
        $c->stash->{inner_template} = $output
          if $c->stash->{layout} && !$partial;
    }

    # JSON
    elsif ($c->stash->{json}) {

        # Render
        $self->handler->{json}->($self, $c, \$output);
        $format = 'json';

        # Layout?
        $c->stash->{inner_template} = $output
          if $c->stash->{layout} && !$partial;
    }

    # Template or templateless handler
    elsif ($template || $handler) {

        # Render
        return unless $self->_render_template($c, \$output, $options);

        # Layout?
        $c->stash->{inner_template} = $output
          if $c->stash->{layout} && !$partial;
    }

    # Layout
    if (!$partial && (my $layout = delete $c->stash->{layout})) {

        # Handler
        $handler = $c->stash->{handler} || $self->default_handler;
        $options->{handler} = $handler;

        # Format
        $format = $c->stash->{format} || $self->default_format;
        $options->{format} = $format;

        # Fix
        $options->{template} = $self->layout_prefix . "/$layout";

        # Render
        $self->_render_template($c, \$output, $options);
    }

    # Partial
    return $output if $partial;

    # Response
    my $res = $c->res;
    $res->code($c->stash('status') || $self->default_status)
      unless $res->code;
    $res->body($output) unless $res->body;

    # Type
    my $type = $self->types->type($format) || 'text/plain';
    $res->headers->content_type($type) unless $res->headers->content_type;

    # Success!
    return 1;
}

sub template_name {
    my ($self, $options) = @_;

    my $template = $options->{template} || '';
    my $format   = $options->{format};
    my $handler  = $options->{handler};

    return "$template.$format.$handler";
}

sub template_path {
    my $self = shift;
    return File::Spec->catfile($self->root, split '/',
        $self->template_name(shift));
}

# Well, at least here you'll be treated with dignity.
# Now strip naked and get on the probulator.
sub _render_template {
    my ($self, $c, $output, $options) = @_;

    # Renderer
    my $handler  = $options->{handler};
    my $renderer = $self->handler->{$handler};

    # No handler
    unless ($renderer) {
        $c->app->log->error(qq/No handler for "$handler" available./);
        return;
    }

    # Render
    return unless $renderer->($self, $c, $output, $options);

    # Success!
    return 1;
}

1;
__END__

=head1 NAME

MojoX::Renderer - Renderer

=head1 SYNOPSIS

    use MojoX::Renderer;

    my $renderer = MojoX::Renderer->new;

=head1 DESCRIPTION

L<MojoX::Renderer> is a MIME type based renderer.

=head2 ATTRIBUTES

L<MojoX::Types> implements the follwing attributes.

=head2 C<default_format>

    my $default = $renderer->default_format;
    $renderer   = $renderer->default_format('html');

=head2 C<default_handler>

    my $default = $renderer->default_handler;
    $renderer   = $renderer->default_handler('epl');

=head2 C<default_status>

    my $default = $renderer->default_status;
    $renderer   = $renderer->default_status(404);

=head2 C<handler>

    my $handler = $renderer->handler;
    $renderer   = $renderer->handler({epl => sub { ... }});

=head2 C<layout_prefix>

    my $prefix = $renderer->layout_prefix;
    $renderer  = $renderer->layout_prefix('layouts');

=head2 C<root>

   my $root  = $renderer->root;
   $renderer = $renderer->root('/foo/bar/templates');

=head2 C<types>

    my $types = $renderer->types;
    $renderer = $renderer->types(MojoX::Types->new);

=head1 METHODS

L<MojoX::Types> inherits all methods from L<Mojo::Base> and implements the
follwing the ones.

=head2 C<new>

    my $renderer = MojoX::Renderer->new;

=head2 C<add_handler>

    $renderer = $renderer->add_handler(epl => sub { ... });

=head2 C<render>

    my $success  = $renderer->render($c);

    $c->stash->{partial} = 1;
    my $output = $renderer->render($c);

=head2 C<template_name>

    my $template = $renderer->template_path({
        template => 'foo/bar',
        format   => 'html',
        handler  => 'epl'
    });

=head2 C<template_path>

    my $path = $renderer->template_name({
        template => 'foo/bar',
        format   => 'html',
        handler  => 'epl'
    });

=cut
