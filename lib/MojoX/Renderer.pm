# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Renderer;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use MojoX::Types;

__PACKAGE__->attr(default_format => (chained => 1));
__PACKAGE__->attr(handler => (chained => 1, default => sub { {} }));
__PACKAGE__->attr(
    types => (
        chained => 1,
        default => sub { MojoX::Types->new }
    )
);
__PACKAGE__->attr(root => (chained => 1));

# This is not how Xmas is supposed to be.
# In my day Xmas was about bringing people together, not blowing them apart.
sub add_handler {
    my $self = shift;

    # Merge
    my $handler = ref $_[0] ? $_[0] : {@_};
    $handler = {%{$self->handler}, %$handler};
    $self->handler($handler);

    return $self;
}

sub render {
    my ($self, $c) = @_;

    my $format        = $c->stash->{format};
    my $template      = $c->stash->{template};
    my $template_path = $c->stash->{template_path};

    return undef unless $format || $template || $template_path;

    # Default format
    my $default = $self->default_format;

    # Template but no path
    if ($template && !$template_path) {

        # Build template_path
        $template .= ".$default"
          if $default && $template !~ /\.\w+$/;
        my $path = File::Spec->catfile($self->root, $template);
        $c->stash->{template_path} = $path;
    }

    # Format
    unless ($format) {
        $c->stash->{template_path} =~ /\.(\w+)$/;
        $format = $1;
    }

    return undef unless $format;

    my $handler = $self->handler->{$format};

    if ($handler) {
        # Debug
        $c->app->log->debug(qq/Rendering with handler "$format"/);
    }
    # No format found? give up.
    else {
        $c->app->log->debug(
            qq/No handler for "$format" configured/);
        return undef;

    }


    # Render
    my $output;
    return undef unless $handler->($self, $c, \$output);

    # Partial
    return $output if $c->stash->{partial};

    # Response
    my $res = $c->res;
    $res->code(200) unless $c->res->code;
    $res->body($output);

    my $type = $self->types->type($format) || 'text/plain';
    $res->headers->content_type($type);

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

=head2 C<default_format>

    my $format = $renderer->default_format;
    $renderer  = $renderer->default_format('phtml');

Returns the file extesion of the default handler unsed for rendering if
called without arguments.
Returns the invocant if called with arguments.

=head2 C<handler>

    my $handler = $renderer->handler;
    $renderer   = $renderer->handler({phtml => sub { ... }});

Returns a hashref of handlers if called without arguments.
Returns the invocant if called with arguments.
Keys are file extensions and values are coderefs.

=head2 C<types>

    my $types = $renderer->types;
    $renderer = $renderer->types(MojoX::Types->new);

Returns a L<MojoX::Types> object if called without arguments.
Returns the invocant if called with arguments.

=head2 C<root>

   my $root  = $renderer->root;
   $renderer = $renderer->root('/foo/bar/templates');

Return the root file system path where templates are stored if called without
arguments.
Returns the invocant if called with arguments.

=head1 METHODS

L<MojoX::Types> inherits all methods from L<Mojo::Base> and implements the
follwing the ones.

=head2 C<add_handler>

    $renderer = $renderer->add_handler(phtml => sub { ... });

=head2 C<render>

    my $success  = $renderer->render($c);

    $c->stash->{partial} = 1;
    my $output = $renderer->render($c);

Returns a true value  if a template is successfully rendered.
Returns the template output if C<partial> is set in the stash.
Returns C<undef> if none of C<format>, C<template> or C<template_path> are
set in the stash.
Returns C<undef> if the C<template> is defined, but lacks an extension
and no default handler has been defined.
Returns C<undef> if the handler returns a false value.
Expects a L<MojoX::Context> object.

To determine the format to use, we first check C<format> in the stash, and
if that is empty, we check the extensions of C<template_path> and
C<template>.

C<format> may contain a value like C<html>.
C<template_path> may contain an absolute path like  C</templates/page.html>.
C<template> may contain a path relative to C<root>, like C<users/list.html>.

If C<template_path> is not set in the stash, we create it by appending
C<template> to the C<root>.

If C<template> lacks an extension, we add one using C<default_format>.

If C<format> is not defined, we try to determine it from the extension of
C<template_path>.

If no handler is found for the C<format>, we emit a warning, and check for a
handler for the C<default_format>.

A handler receives three arguments: the renderer object, the
L<MojoX::Context> object and a reference to an empty scalar, where the output
can be accumulated.

If C<partial> is defined in the stash, the output from the handler is simply
returned.

Otherwise, we build our own L<Mojo::Message::Response> and return C<true> for
success. We set the response code to 200 if none is provided, and default to
C<text/plain> if there is no type associated with the format.

=cut
