# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoX::Renderer;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use MojoX::Types;

__PACKAGE__->attr(handler => (chained => 1, default => sub { {} }));
__PACKAGE__->attr(
    types => (
        chained => 1,
        default => sub { MojoX::Types->new }
    )
);
__PACKAGE__->attr(precedence => (chained => 1));
__PACKAGE__->attr(root => (chained => 1, default => '/'));

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
    my $handler       = $c->stash->{handler};
    my $template      = $c->stash->{template};
    my $template_path = $c->stash->{template_path};

    # Not enough informations
    return undef unless $template || $template_path;

    # Handler precedence
    $self->precedence([sort keys %{$self->handler}])
      unless $self->precedence;

    # Template path
    $template_path = File::Spec->catfile($self->root, $template)
      if $template && !$template_path;

    # Format
    unless ($template_path =~ /\.\w+(?:\.\w+)?$/) {
        if ($format) { $template_path .= ".$format" }
        else {
            $c->app->log->debug('Template format missing');
            return undef;
        }
    }

    # Handler
    unless ($template_path =~ /\.\w+\.\w+$/) {

        if ($handler) { $template_path .= ".$handler" }

        # Detect
        else {
            my $found = 0;
            for my $ext (@{$self->precedence}) {

                # Try
                my $path = "$template_path.$ext";
                if (-f $path) {
                    $found++;
                    $template_path = $path;
                    $c->app->log->debug(qq/Template found "$template_path"/);
                    last;
                }
            }

            # Nothing found
            unless ($found) {
                $c->app->log->debug(
                    qq/Template not found "$template_path.*"/);
                return undef;
            }
        }
    }

    # Store for handler usage
    local $c->stash->{template_path} = $template_path;

    # Extract
    $template_path =~ /\.(\w+)\.(\w+)$/;
    $format  = $1;
    $handler = $2;

    # Renderer
    my $r = $self->handler->{$handler};

    # Debug
    unless ($r) {
        $c->app->log->debug(qq/No handler for "$handler" available/);
        return undef;
    }

    # Partial?
    my $partial = $c->stash->{partial};

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

=head2 C<handler>

    my $handler = $renderer->handler;
    $renderer   = $renderer->handler({phtml => sub { ... }});

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

    $renderer = $renderer->add_handler(phtml => sub { ... });

=head2 C<render>

    my $success  = $renderer->render($c);

    $c->stash->{partial} = 1;
    my $output = $renderer->render($c);

=cut
