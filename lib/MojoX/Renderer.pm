# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Renderer;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp qw/carp croak/;
use File::Spec;
use MojoX::Types;

__PACKAGE__->attr(default_ext => (chained => 1));
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

    my $template = $c->stash->{template};

    return undef unless $template;

    # Extension
    my $default = $self->default_ext;
    $template .= ".$default" if $default && $template !~ /\.\w+$/;
    $template =~ /\.(\w+)$/;
    my $ext = $1;

    # Path
    my $path = File::Spec->catfile($self->root, $template);
    $c->stash->{template_path} ||= $path;

    return undef unless $ext;

    my $handler = $self->handler->{$ext};

    # Fallback
    unless ($handler) {
        carp qq/No handler for "$ext" files configured/;
        $handler = $self->handler->{$default};
        croak 'Need a valid handler for rendering' unless $handler;
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

    my $type = $self->types->type($ext) || 'text/plain';
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

=head2 C<default_ext>

    my $ext   = $renderer->default_ext;
    $renderer = $renderer->default_ext('phtml');

=head2 C<handler>

    my $handler = $renderer->handler;
    $renderer   = $renderer->handler({phtml => sub { ... }});

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

    $renderer = $renderer->add_handler(phtml => sub { ... });

=head2 C<render>

    $renderer = $renderer->render($c);

=cut
