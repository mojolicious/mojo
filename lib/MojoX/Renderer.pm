# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Renderer;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use Mojo::ByteStream 'b';
use Mojo::Command;
use Mojo::JSON;
use MojoX::Types;

__PACKAGE__->attr(default_format => 'html');
__PACKAGE__->attr([qw/default_handler default_template_class encoding/]);
__PACKAGE__->attr(default_status   => 200);
__PACKAGE__->attr(detect_templates => 1);
__PACKAGE__->attr(handler          => sub { {} });
__PACKAGE__->attr(helper           => sub { {} });
__PACKAGE__->attr(layout_prefix    => 'layouts');
__PACKAGE__->attr(root             => '/');
__PACKAGE__->attr(types            => sub { MojoX::Types->new });

# This is not how Xmas is supposed to be.
# In my day Xmas was about bringing people together, not blowing them apart.
sub new {
    my $self = shift->SUPER::new(@_);

    # Data
    $self->add_handler(
        data => sub {
            my ($r, $c, $output, $options) = @_;
            $$output = $options->{data};
        }
    );

    # JSON
    $self->add_handler(
        json => sub {
            my ($r, $c, $output, $options) = @_;
            $$output = Mojo::JSON->new->encode($options->{json});
        }
    );

    # Text
    $self->add_handler(
        text => sub {
            my ($r, $c, $output, $options) = @_;
            $$output = $options->{text};
        }
    );

    return $self;
}

sub add_handler {
    my $self = shift;

    # Merge
    my $handler = ref $_[0] ? $_[0] : {@_};
    $handler = {%{$self->handler}, %$handler};
    $self->handler($handler);

    return $self;
}

sub add_helper {
    my $self = shift;

    # Merge
    my $helper = ref $_[0] ? $_[0] : {@_};
    $helper = {%{$self->helper}, %$helper};
    $self->helper($helper);

    return $self;
}

sub get_inline_template {
    my ($self, $c, $template) = @_;
    return Mojo::Command->new->get_data($template,
        $self->_detect_template_class($c->stash));
}

# Bodies are for hookers and fat people.
sub render {
    my ($self, $c) = @_;

    # We got called
    $c->stash->{rendered} = 1;
    $c->stash->{content} ||= {};

    # Partial
    my $partial = delete $c->stash->{partial};

    # Template
    my $template = delete $c->stash->{template};

    # Format
    my $format = $c->stash->{format} || $self->default_format;

    # Handler
    my $handler = $c->stash->{handler};

    # Data
    my $data = delete $c->stash->{data};

    # JSON
    my $json = delete $c->stash->{json};

    # Text
    my $text = delete $c->stash->{text};

    my $options =
      {template => $template, format => $format, handler => $handler};
    my $output;

    # Text
    if (defined $text) {

        # Render
        $self->handler->{text}->($self, $c, \$output, {text => $text});

        # Extends
        $c->stash->{content}->{content} = b("$output")
          if ($c->stash->{extends} || $c->stash->{layout});
    }

    # Data
    elsif (defined $data) {

        # Render
        $self->handler->{data}->($self, $c, \$output, {data => $data});

        # Extends
        $c->stash->{content}->{content} = b("$output")
          if ($c->stash->{extends} || $c->stash->{layout});
    }

    # JSON
    elsif (defined $json) {

        # Render
        $self->handler->{json}->($self, $c, \$output, {json => $json});
        $format = 'json';

        # Extends
        $c->stash->{content}->{content} = b("$output")
          if ($c->stash->{extends} || $c->stash->{layout});
    }

    # Template or templateless handler
    else {

        # Render
        return unless $self->_render_template($c, \$output, $options);

        # Extends
        $c->stash->{content}->{content} = b("$output")
          if ($c->stash->{extends} || $c->stash->{layout});
    }

    # Extends
    while (my $extends = $self->_extends($c)) {

        # Handler
        $handler = $c->stash->{handler};
        $options->{handler} = $handler;

        # Format
        $format = $c->stash->{format} || $self->default_format;
        $options->{format} = $format;

        # Template
        $options->{template} = $extends;

        # Render
        $self->_render_template($c, \$output, $options);
    }

    # Partial
    return $output if $partial;

    # Encoding (JSON is already encoded)
    $output = b($output)->encode($self->encoding)->to_string
      if $self->encoding && !$json && !$data;

    # Response
    my $res = $c->res;
    my $req = $c->req;
    unless ($res->code) {
        $req->has_error
          ? $res->code($req->error)
          : $res->code($c->stash('status') || $self->default_status);
    }
    $res->body($output) unless $res->body;

    # Type
    my $type = $self->types->type($format) || 'text/plain';
    $res->headers->content_type($type) unless $res->headers->content_type;

    # Success!
    return 1;
}

sub template_name {
    my ($self, $options) = @_;

    # Template
    return unless my $template = $options->{template} || '';

    # Format
    return unless my $format = $options->{format};

    # Handler
    my $handler = $options->{handler};

    # File
    my $file = "$template.$format";
    $file = "$file.$handler" if $handler;

    return $file;
}

sub template_path {
    my $self = shift;
    return unless my $name = $self->template_name(shift);
    return File::Spec->catfile($self->root, split '/', $name);
}

sub _detect_handler {
    my ($self, $options) = @_;

    # Disabled
    return unless $self->detect_templates;

    # Template class
    my $class = $self->_detect_template_class;

    # Templates
    my $templates = $self->{_templates};
    unless ($templates) {
        $templates = $self->_list_templates;
        $self->{_templates} = $templates;
    }

    # Inline templates
    my $inline = $self->{_inline_templates}->{$class}
      ||= $self->_list_inline_templates($class);

    # Detect
    return unless my $file = $self->template_name($options);
    for my $template (@$templates, @$inline) {
        if ($template =~ /^$file\.(\w+)$/) { return $1 }
    }

    return;
}

sub _detect_template_class {
    my ($self, $options) = @_;
    return
         $options->{template_class}
      || $ENV{MOJO_TEMPLATE_CLASS}
      || $self->default_template_class
      || 'main';
}

sub _extends {
    my ($self, $c) = @_;

    # Layout
    if (my $layout = delete $c->stash->{layout}) {
        $c->stash->{extends} ||= $self->layout_prefix . '/' . $layout;
    }

    # Extends
    return delete $c->stash->{extends};
}

sub _list_inline_templates {
    my ($self, $class) = @_;

    # Get all
    my $all = Mojo::Command->new->get_all_data($class);

    # List
    return [keys %$all];
}

sub _list_templates {
    my ($self, $dir) = @_;

    # Root
    my $root = $self->root;
    $dir ||= $root;

    # Read directory
    my (@files, @dirs);
    opendir DIR, $dir or return [];
    for my $file (readdir DIR) {

        # Hidden file
        next if $file =~ /^\./;

        # File
        my $path = File::Spec->catfile($dir, $file);
        if (-f $path) {
            $path = File::Spec->abs2rel($path, $root);
            push @files, $path;
            next;
        }

        # Directory
        push @dirs, $path if -d $path;
    }
    closedir DIR;

    # Walk directories
    for my $path (@dirs) {
        my $new = $self->_list_templates($path);
        push @files, @$new;
    }

    return [sort @files];
}

# Well, at least here you'll be treated with dignity.
# Now strip naked and get on the probulator.
sub _render_template {
    my ($self, $c, $output, $options) = @_;

    # Renderer
    my $handler =
         $options->{handler}
      || $self->_detect_handler($options)
      || $self->default_handler;
    $options->{handler} = $handler;
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

MojoX::Renderer - MIME Type Based Renderer

=head1 SYNOPSIS

    use MojoX::Renderer;

    my $renderer = MojoX::Renderer->new;

=head1 DESCRIPTION

L<MojoX::Renderer> is the standard L<Mojolicious> renderer.
It turns your stashed data structures into content.

=head2 ATTRIBUTES

L<MojoX::Types> implements the following attributes.

=head2 C<default_format>

    my $default = $renderer->default_format;
    $renderer   = $renderer->default_format('html');

The default format to render if C<format> is not set in the stash.
The renderer will use L<MojoX::Types> to look up the content MIME type.

=head2 C<default_handler>

    my $default = $renderer->default_handler;
    $renderer   = $renderer->default_handler('epl');

The default template handler to use for rendering.
There are two handlers in this distribution.

=over 4

=item epl

C<Embedded Perl Lite> handled by L<Mojolicious::Plugin::EplRenderer>.

=item ep

C<Embedded Perl> handled by L<Mojolicious::Plugin::EpRenderer>.

=back

=head2 C<default_status>

    my $default = $renderer->default_status;
    $renderer   = $renderer->default_status(404);

The default status to set when rendering content, defaults to C<200>.

=head2 C<default_template_class>

    my $default = $renderer->default_template_class;
    $renderer   = $renderer->default_template_class('main');

The renderer will use this class to look for templates in the C<__DATA__>
section.

=head2 C<detect_templates>

    my $detect = $renderer->detect_templates;
    $renderer  = $renderer->detect_templates(1);

Template auto detection, the renderer will try to select the right template
and renderer automatically.
A very powerful alternative to C<default_handler> that allows parallel use of
multiple template systems.

=head2 C<encoding>

    my $encoding = $renderer->encoding;
    $renderer    = $renderer->encoding('koi8-r');

Will encode the content if set.

=head2 C<handler>

    my $handler = $renderer->handler;
    $renderer   = $renderer->handler({epl => sub { ... }});

Registered handlers.

=head2 C<helper>

    my $helper = $renderer->helper;
    $renderer  = $renderer->helper({url_for => sub { ... }});

Registered helpers.

=head2 C<layout_prefix>

    my $prefix = $renderer->layout_prefix;
    $renderer  = $renderer->layout_prefix('layouts');

Directory to look for layouts in, defaults to C<layouts>.

=head2 C<root>

   my $root  = $renderer->root;
   $renderer = $renderer->root('/foo/bar/templates');
   
Directory to look for templates in.

=head2 C<types>

    my $types = $renderer->types;
    $renderer = $renderer->types(MojoX::Types->new);

L<MojoX::Types> object to use for looking up MIME types.

=head1 METHODS

L<MojoX::Renderer> inherits all methods from L<Mojo::Base> and implements the
following ones.

=head2 C<new>

    my $renderer = MojoX::Renderer->new;

Construct a new renderer.

=head2 C<add_handler>

    $renderer = $renderer->add_handler(epl => sub { ... });
    
Add a new handler to the renderer.
See L<Mojolicious::Plugin::EpRenderer> for a sample renderer.

=head2 C<add_helper>

    $renderer = $renderer->add_helper(url_for => sub { ... });

Add a new helper to the renderer.
See L<Mojolicious::Plugin::EpRenderer> for sample helpers.

=head2 C<get_inline_template>

    my $template = $renderer->get_inline_template($c, 'foo.html.ep');

Get an inline template by name, usually used by handlers.

=head2 C<render>

    my $success = $renderer->render($c);

    $c->stash->{partial} = 1;
    my $output = $renderer->render($c);

Render output through one of the Mojo renderers.
This renderer requires some configuration, at the very least you will need to
have a default C<format> and a default C<handler> as well as a C<template> or
C<text>/C<json>.
See L<Mojolicious::Controller> for a more user friendly interface.

=head2 C<template_name>

    my $template = $renderer->template_name({
        template => 'foo/bar',
        format   => 'html',
        handler  => 'epl'
    });
    
Builds a template name based on an options hash with C<template>, C<format>
and C<handler>.

=head2 C<template_path>

    my $path = $renderer->template_path({
        template => 'foo/bar',
        format   => 'html',
        handler  => 'epl'
    });

Builds a full template path based on an options hash with C<template>,
C<format> and C<handler>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
