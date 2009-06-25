# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoX::Renderer;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use MojoX::Types;

__PACKAGE__->attr([qw/default_handler precedence/]);
__PACKAGE__->attr(handler => (default => sub { {} }));
__PACKAGE__->attr(types   => (default => sub { MojoX::Types->new }));
__PACKAGE__->attr(root    => (default => '/'));

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

    my ($template, $template_path);
    my $is_layout = 0;

    # Layout first
    if ($c->stash->{layout} || $c->stash->{layout_path}) {
        $template      = $c->stash->{layout};
        $template_path = $c->stash->{layout_path};
        $is_layout     = 1;
    }

    # Normal template
    else {
        $template      = $c->stash->{template};
        $template_path = $c->stash->{template_path};
    }

    # Not enough information
    return undef unless $template || $template_path;

    # Handler precedence
    $self->precedence([sort keys %{$self->handler}])
      unless $self->precedence;

    # Inner
    local $c->stash->{inner_template} = $c->stash->{template} if $is_layout;
    local $c->stash->{inner_template_path} = $c->stash->{template_path}
      if $is_layout;

    # Template has priority
    $template_path = undef if $template;

    # Path
    return undef
      unless $template_path =
          $self->_fix_path($c, $template, $template_path, $is_layout);

    # Store for handler usage
    local $c->stash->{template_path} = $template_path;

    # Extract
    $template_path =~ /\.(\w+)(?:\.(\w+))?$/;
    my $format = $1;
    my $handler = $2 || $self->default_handler;

    # Renderer
    my $r = $self->handler->{$handler};

    # Debug
    unless ($r) {
        $c->app->log->debug(qq/No handler for "$handler" available./);
        return undef;
    }

    # Partial?
    my $partial = $c->stash->{partial};

    # Clean
    local $c->stash->{layout}      = undef;
    local $c->stash->{layout_path} = undef;
    local $c->stash->{template}    = undef;

    # Render
    my $output;
    return undef unless $r->($self, $c, \$output);

    # Partial
    return $output if $partial;

    # Response
    my $res = $c->res;
    $res->code(200) unless $c->res->code;
    $res->body($output);

    # Type
    my $type = $self->types->type($format) || 'text/plain';
    $res->headers->content_type($type);

    # Success!
    $c->stash->{partial}  = $partial;
    $c->stash->{rendered} = 1;
    return 1;
}

sub _detect_default_handler { return 1 if shift->default_handler && -f shift }

sub _fix_format {
    my ($self, $c, $path) = @_;

    # Format ok
    return $path if $path =~ /\.\w+(?:\.\w+)?$/;

    my $format = $c->stash->{format};

    # Append format
    if ($format) { $path .= ".$format" }

    # Missing format
    else {
        $c->app->log->debug('Template format missing.');
        return undef;
    }

    return $path;
}

sub _fix_handler {
    my ($self, $c, $path) = @_;

    # Handler ok
    return $path if $path =~ /\.\w+\.\w+$/;

    my $handler = $c->stash->{handler};

    # Append handler
    if ($handler) { $path .= ".$handler" }

    # Detect
    elsif (!$self->_detect_default_handler($path)) {
        my $found = 0;
        for my $ext (@{$self->precedence}) {

            # Try
            my $p = "$path.$ext";
            if (-f $p) {
                $found++;
                $path = $p;
                $c->app->log->debug(qq/Template found "$path"./);
                last;
            }
        }

        # Nothing found
        unless ($found) {
            $c->app->log->debug(qq/Template not found "$path.*"./);
            return undef;
        }
    }

    return $path;
}

sub _fix_path {
    my ($self, $c, $template, $template_path, $is_layout) = @_;

    # Root
    my $root =
      $is_layout ? File::Spec->catfile($self->root, 'layouts') : $self->root;

    # Path
    $template_path = File::Spec->catfile($root, $template)
      if $template && !$template_path;

    # Format
    return undef
      unless $template_path = $self->_fix_format($c, $template_path);

    # Handler
    return undef
      unless $template_path = $self->_fix_handler($c, $template_path);

    return $template_path;
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

=head2 C<default_handler>

    my $default = $renderer->default_handler;
    $renderer   = $renderer->default_handler('epl');

=head2 C<handler>

    my $handler = $renderer->handler;
    $renderer   = $renderer->handler({epl => sub { ... }});

Returns a hashref of handlers if called without arguments.
Returns the invocant if called with arguments.
Keys are file extensions and values are coderefs.

=head2 C<precedence>

    my $precedence = $renderer->precedence;
    $renderer      = $renderer->precedence(qw/epl tt mason/);

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

    $renderer = $renderer->add_handler(epl => sub { ... });

=head2 C<render>

    my $success  = $renderer->render($c);

    $c->stash->{partial} = 1;
    my $output = $renderer->render($c);

=cut
