package Mojolicious::Renderer;
use Mojo::Base -base;

use File::Spec;
use Mojo::ByteStream 'b';
use Mojo::Cache;
use Mojo::Command;
use Mojo::Home;
use Mojo::JSON;
use Mojo::Util 'encode';

has cache => sub { Mojo::Cache->new };
has default_format   => 'html';
has detect_templates => 1;
has encoding         => 'UTF-8';
has handlers         => sub { {} };
has helpers          => sub { {} };
has layout_prefix    => 'layouts';
has root             => '/';
has [qw/default_handler default_template_class/];

# DEPRECATED in Hot Beverage!
*handler = sub {
  warn <<EOF;
Mojolicious::Renderer->handler is DEPRECATED in favor of
Mojolicious::Renderer->handlers!!!
EOF
  shift->handlers(@_);
};
*helper = sub {
  warn <<EOF;
Mojolicious::Renderer->helper is DEPRECATED in favor of
Mojolicious::Renderer->helpers!!!
EOF
  shift->helpers(@_);
};

# "This is not how Xmas is supposed to be.
#  In my day Xmas was about bringing people together,
#  not blowing them apart."
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
  my ($self, $name, $cb) = @_;
  $self->handlers->{$name} = $cb;
  return $self;
}

sub add_helper {
  my ($self, $name, $cb) = @_;
  $self->helpers->{$name} = $cb;
  return $self;
}

sub get_inline_template {
  my ($self, $options, $template) = @_;
  return Mojo::Command->new->get_data($template,
    $self->_detect_template_class($options));
}

# "Bodies are for hookers and fat people."
sub render {
  my ($self, $c, $args) = @_;

  # Stash
  my $stash = $c->stash;

  # Arguments
  $args ||= {};

  # Content
  my $content = $stash->{'mojo.content'} ||= {};

  # Partial
  my $partial = $args->{partial};

  # Localize extends and layout
  local $stash->{layout}  = $partial ? undef : $stash->{layout};
  local $stash->{extends} = $partial ? undef : $stash->{extends};

  # Merge stash and arguments
  while (my ($key, $value) = each %$args) {
    $stash->{$key} = $value;
  }

  # Template
  my $template = delete $stash->{template};

  # Template class
  my $class = $stash->{template_class};

  # Format
  my $format = $stash->{format} || $self->default_format;

  # Handler
  my $handler = $stash->{handler};

  # Data
  my $data = delete $stash->{data};

  # JSON
  my $json = delete $stash->{json};

  # Text
  my $text = delete $stash->{text};

  # Inline
  my $inline = delete $stash->{inline};
  $handler = $self->default_handler if defined $inline && !defined $handler;

  my $options = {
    template       => $template,
    format         => $format,
    handler        => $handler,
    encoding       => $self->encoding,
    inline         => $inline,
    template_class => $class
  };
  my $output;

  # Text
  if (defined $text) {

    # Render
    $self->handlers->{text}->($self, $c, \$output, {text => $text});

    # Extends
    $content->{content} = b("$output")
      if ($c->stash->{extends} || $c->stash->{layout});
  }

  # Data
  elsif (defined $data) {

    # Render
    $self->handlers->{data}->($self, $c, \$output, {data => $data});

    # Extends
    $content->{content} = b("$output")
      if ($c->stash->{extends} || $c->stash->{layout});
  }

  # JSON
  elsif (defined $json) {

    # Render
    $self->handlers->{json}->($self, $c, \$output, {json => $json});
    $format = 'json';

    # Extends
    $content->{content} = b("$output")
      if ($c->stash->{extends} || $c->stash->{layout});
  }

  # Template or templateless handler
  else {

    # Render
    return unless $self->_render_template($c, \$output, $options);

    # Extends
    $content->{content} = b($output)
      if ($c->stash->{extends} || $c->stash->{layout});
  }

  # Extends
  while ((my $extends = $self->_extends($c)) && !$json && !$data) {

    # Stash
    my $stash = $c->stash;

    # Template class
    $class = $stash->{template_class};
    $options->{template_class} = $class;

    # Handler
    $handler = $stash->{handler};
    $options->{handler} = $handler;

    # Format
    $format = $stash->{format} || $self->default_format;
    $options->{format} = $format;

    # Template
    $options->{template} = $extends;

    # Render
    $self->_render_template($c, \$output, $options);
  }

  # Encoding (JSON is already encoded)
  unless ($partial) {
    my $encoding = $options->{encoding};
    encode $encoding, $output if $encoding && $output && !$json && !$data;
  }

  # Type
  my $type = $c->app->types->type($format) || 'text/plain';

  return ($output, $type);
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
  my $class = $self->_detect_template_class($options);

  # Templates
  my $templates = $self->{_templates};
  unless ($templates) {
    $templates = $self->{_templates} =
      Mojo::Home->new->parse($self->root)->list_files;
  }

  # Inline templates
  my $inline = $self->{_inline_templates}->{$class}
    ||= $self->_list_inline_templates($class);

  # Detect
  return unless my $file = $self->template_name($options);
  $file = quotemeta $file;
  for my $template (@$templates, @$inline) {
    if ($template =~ /^$file\.(\w+)$/) { return $1 }
  }

  return;
}

# "You are hereby conquered.
#  Please line up in order of how much beryllium it takes to kill you."
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
  my $stash = $c->stash;
  if (my $layout = delete $stash->{layout}) {
    $stash->{extends} ||= $self->layout_prefix . '/' . $layout;
  }

  # Extends
  return delete $stash->{extends};
}

sub _list_inline_templates {
  my ($self, $class) = @_;

  # Get all
  my $all = Mojo::Command->new->get_all_data($class);

  # List
  return [keys %$all];
}

# "Well, at least here you'll be treated with dignity.
#  Now strip naked and get on the probulator."
sub _render_template {
  my ($self, $c, $output, $options) = @_;

  # Renderer
  my $handler =
       $options->{handler}
    || $self->_detect_handler($options)
    || $self->default_handler;
  $options->{handler} = $handler;
  my $renderer = $self->handlers->{$handler};

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

Mojolicious::Renderer - MIME Type Based Renderer

=head1 SYNOPSIS

  use Mojolicious::Renderer;

  my $renderer = Mojolicious::Renderer->new;

=head1 DESCRIPTION

L<Mojolicious::Renderer> is the standard L<Mojolicious> renderer.
It turns your stashed data structures into content.
See L<Mojolicious::Guides::Rendering> for more.

=head1 ATTRIBUTES

L<Mojolicious::Renderer> implements the following attributes.

=head2 C<cache>

  my $cache = $renderer->cache;
  $renderer = $renderer->cache(Mojo::Cache->new);

Renderer cache, by default a L<Mojo::Cache> object.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<default_format>

  my $default = $renderer->default_format;
  $renderer   = $renderer->default_format('html');

The default format to render if C<format> is not set in the stash.
The renderer will use L<Mojolicious::Types> to look up the content MIME type.

=head2 C<default_handler>

  my $default = $renderer->default_handler;
  $renderer   = $renderer->default_handler('epl');

The default template handler to use for rendering in cases where auto
detection doesn't work, like for C<inline> templates.

=over 2

=item epl

C<Embedded Perl Lite> handled by L<Mojolicious::Plugin::EplRenderer>.

=item ep

C<Embedded Perl> handled by L<Mojolicious::Plugin::EpRenderer>.

=back

=head2 C<default_template_class>

  my $default = $renderer->default_template_class;
  $renderer   = $renderer->default_template_class('main');

The renderer will use this class to look for templates in the C<DATA>
section.

=head2 C<detect_templates>

  my $detect = $renderer->detect_templates;
  $renderer  = $renderer->detect_templates(1);

Template auto detection, the renderer will try to select the right template
and renderer automatically.

=head2 C<encoding>

  my $encoding = $renderer->encoding;
  $renderer    = $renderer->encoding('koi8-r');

Will encode the content if set, defaults to C<UTF-8>.

=head2 C<handlers>

  my $handlers = $renderer->handlers;
  $renderer    = $renderer->handlers({epl => sub { ... }});

Registered handlers.

=head2 C<helpers>

  my $helpers = $renderer->helpers;
  $renderer   = $renderer->helpers({url_for => sub { ... }});

Registered helpers.

=head2 C<layout_prefix>

  my $prefix = $renderer->layout_prefix;
  $renderer  = $renderer->layout_prefix('layouts');

Directory to look for layouts in, defaults to C<layouts>.

=head2 C<root>

  my $root  = $renderer->root;
  $renderer = $renderer->root('/foo/bar/templates');
   
Directory to look for templates in.

=head1 METHODS

L<Mojolicious::Renderer> inherits all methods from L<Mojo::Base> and implements the
following ones.

=head2 C<new>

  my $renderer = Mojolicious::Renderer->new;

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

  my $template = $renderer->get_inline_template({
    template       => 'foo/bar',
    format         => 'html',
    handler        => 'epl'
    template_class => 'main'
  }, 'foo.html.ep');

Get an inline template by name, usually used by handlers.

=head2 C<render>

  my ($output, $type) = $renderer->render($c);
  my ($output, $type) = $renderer->render($c, $args);

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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
