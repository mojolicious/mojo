# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoX::Renderer;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use MojoX::Types;

__PACKAGE__->attr([qw/default_handler precedence/]);
__PACKAGE__->attr('handler', default => sub { {} });
__PACKAGE__->attr('types',   default => sub { MojoX::Types->new });
__PACKAGE__->attr('root',    default => '/');

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

sub rel_template {
    my ($self, $template, $format, $handler) = @_;
    $template ||= '';
    return File::Spec->catfile($self->root, split '/', $template)
      . ".$format.$handler";
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
    my $format = $c->stash->{format} || 'html';

    # Handler
    my $handler = $c->stash->{handler};

    my $options =
      {template => $template, format => $format, handler => $handler};
    my $output;

    # Text
    if (my $text = delete $c->stash->{text}) {
        $output = $text;
        $c->stash->{inner_template} = $output if $c->stash->{layout};
    }

    # Template or templateless handler
    elsif ($template || $handler) {

        # Handler
        $options->{handler} ||= $self->_detect_handler($template, $format)
          || $self->default_handler;

        # Render
        return unless $self->_render_template($c, \$output, $options);

        # Layout?
        $c->stash->{inner_template} = $output if $c->stash->{layout};
    }

    # Layout
    if (my $layout = delete $c->stash->{layout}) {

        # Handler
        $handler =
             $c->stash->{handler}
          || $self->_detect_handler($template, $format)
          || $self->default_handler;
        $options->{handler} = $handler;

        # Format
        $format = $c->stash->{format} || 'html';
        $options->{format} = $format;

        # Fix
        $options->{template} = "layouts/$layout";

        # Render
        $self->_render_template($c, \$output, $options);
    }

    # Partial
    return $output if $partial;

    # Response
    my $res = $c->res;
    $res->code(200) unless $res->code;
    $res->body($output) unless $res->body;

    # Type
    my $type = $self->types->type($format) || 'text/plain';
    $res->headers->content_type($type) unless $res->headers->content_type;

    # Success!
    return 1;
}

# Well, at least here you'll be treated with dignity.
# Now strip naked and get on the probulator.
sub _detect_handler {
    my ($self, $template, $format) = @_;

    # Shortcut
    return unless $template || $format;

    # Handler precedence
    $self->precedence([sort keys %{$self->handler}])
      unless $self->precedence;

    # Try all
    for my $ext (@{$self->precedence}) {

        # Found
        return $ext if -r $self->rel_template($template, $format, $ext);
    }

    # Nothing found
    return;
}

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

=head2 C<default_handler>

    my $default = $renderer->default_handler;
    $renderer   = $renderer->default_handler('epl');

=head2 C<handler>

    my $handler = $renderer->handler;
    $renderer   = $renderer->handler({epl => sub { ... }});

=head2 C<precedence>

    my $precedence = $renderer->precedence;
    $renderer      = $renderer->precedence(qw/epl tt mason/);

=head2 C<types>

    my $types = $renderer->types;
    $renderer = $renderer->types(MojoX::Types->new);

=head2 C<root>

   my $root  = $renderer->root;
   $renderer = $renderer->root('/foo/bar/templates');

=head1 METHODS

L<MojoX::Types> inherits all methods from L<Mojo::Base> and implements the
follwing the ones.

=head2 C<add_handler>

    $renderer = $renderer->add_handler(epl => sub { ... });

=head2 C<rel_template>

    my $path = $renderer->rel_template('foo/bar', 'html', 'epl');

=head2 C<render>

    my $success  = $renderer->render($c);

    $c->stash->{partial} = 1;
    my $output = $renderer->render($c);

=cut
