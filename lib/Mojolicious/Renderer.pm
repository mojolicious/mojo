package Mojolicious::Renderer;
use Mojo::Base -base;

use File::Spec::Functions 'catfile';
use Mojo::Cache;
use Mojo::Command;
use Mojo::Home;
use Mojo::JSON;
use Mojo::Util 'encode';

has cache   => sub { Mojo::Cache->new };
has classes => sub { ['main'] };
has default_format => 'html';
has 'default_handler';
has encoding => 'UTF-8';
has [qw(handlers helpers)] => sub { {} };
has paths => sub { [] };

# "This is not how Xmas is supposed to be.
#  In my day Xmas was about bringing people together,
#  not blowing them apart."
sub new {

  # Add "data" handler
  my $self = shift->SUPER::new(@_)->add_handler(
    data => sub {
      my ($r, $c, $output, $options) = @_;
      $$output = $options->{data};
    }
  );

  # Add "json" handler
  $self->add_handler(
    json => sub {
      my ($r, $c, $output, $options) = @_;
      $$output = Mojo::JSON->new->encode($options->{json});
    }
  );

  # Add "text" handler
  return $self->add_handler(
    text => sub {
      my ($r, $c, $output, $options) = @_;
      $$output = $options->{text};
    }
  );
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

sub get_data_template {
  my ($self, $options, $template) = @_;

  # Index DATA templates
  unless ($self->{index}) {
    my $index = $self->{index} = {};
    for my $class (reverse @{$self->classes}) {
      $index->{$_} = $class for keys %{Mojo::Command->get_all_data($class)};
    }
  }

  # Find template
  return Mojo::Command->get_data($template, $self->{index}{$template});
}

# "Bodies are for hookers and fat people."
sub render {
  my ($self, $c, $args) = @_;
  $args ||= {};

  # Localize extends and layout
  my $partial = $args->{partial};
  my $stash   = $c->stash;
  local $stash->{layout}  = $partial ? undef : $stash->{layout};
  local $stash->{extends} = $partial ? undef : $stash->{extends};

  # Merge stash and arguments
  @{$stash}{keys %$args} = values %$args;

  # Extract important stash values
  my $options = {
    encoding => $self->encoding,
    handler  => $stash->{handler},
    template => delete $stash->{template}
  };
  my $data   = $options->{data}   = delete $stash->{data};
  my $format = $options->{format} = $stash->{format} || $self->default_format;
  my $inline = $options->{inline} = delete $stash->{inline};
  my $json   = $options->{json}   = delete $stash->{json};
  my $text   = $options->{test}   = delete $stash->{text};
  $options->{handler} //= $self->default_handler if defined $inline;

  # Text
  my $output;
  my $content = $stash->{'mojo.content'} ||= {};
  if (defined $text) {
    $self->handlers->{text}->($self, $c, \$output, {text => $text});
    $content->{content} = $output
      if ($c->stash->{extends} || $c->stash->{layout});
  }

  # Data
  elsif (defined $data) {
    $self->handlers->{data}->($self, $c, \$output, {data => $data});
    $content->{content} = $output
      if ($c->stash->{extends} || $c->stash->{layout});
  }

  # JSON
  elsif (defined $json) {
    $self->handlers->{json}->($self, $c, \$output, {json => $json});
    $format = 'json';
    $content->{content} = $output
      if ($c->stash->{extends} || $c->stash->{layout});
  }

  # Template or templateless handler
  else {
    return unless $self->_render_template($c, \$output, $options);
    $content->{content} = $output
      if ($c->stash->{extends} || $c->stash->{layout});
  }

  # Extendable content
  if (!$json && !defined $data) {

    # Extends
    while ((my $extends = $self->_extends($c)) && !defined $inline) {
      $options->{handler}  = $stash->{handler};
      $options->{format}   = $stash->{format} || $self->default_format;
      $options->{template} = $extends;
      $self->_render_template($c, \$output, $options);
      $content->{content} = $output
        if $content->{content} !~ /\S/ && $output =~ /\S/;
    }

    # Encoding
    $output = encode $options->{encoding}, $output
      if !$partial && $options->{encoding} && $output;
  }

  return $output, $c->app->types->type($format) || 'text/plain';
}

sub template_name {
  my ($self, $options) = @_;
  return unless my $template = $options->{template} || '';
  return unless my $format = $options->{format};
  my $handler = $options->{handler};
  return defined $handler ? "$template.$format.$handler" : "$template.$format";
}

sub template_path {
  my $self = shift;

  # Nameless
  return unless my $name = $self->template_name(shift);

  # Search all paths
  for my $path (@{$self->paths}) {
    my $file = catfile($path, split '/', $name);
    return $file if -r $file;
  }

  # Fall back to first path
  return catfile($self->paths->[0], split '/', $name);
}

sub _detect_handler {
  my ($self, $options) = @_;

  # Templates
  return unless my $file = $self->template_name($options);
  unless ($self->{templates}) {
    s/\.(\w+)$// and $self->{templates}{$_} ||= $1
      for map { sort @{Mojo::Home->new($_)->list_files} } @{$self->paths};
  }
  return $self->{templates}{$file} if exists $self->{templates}{$file};

  # DATA templates
  unless ($self->{data}) {
    my @templates
      = map { sort keys %{Mojo::Command->get_all_data($_)} } @{$self->classes};
    s/\.(\w+)$// and $self->{data}{$_} ||= $1 for @templates;
  }
  return $self->{data}{$file} if exists $self->{data}{$file};

  # Nothing
  return;
}

# "Robot 1-X, save my friends! And Zoidberg!"
sub _extends {
  my ($self, $c) = @_;
  my $stash = $c->stash;
  if (my $layout = delete $stash->{layout}) {
    $stash->{extends} ||= 'layouts' . '/' . $layout;
  }
  return delete $stash->{extends};
}

sub _render_template {
  my ($self, $c, $output, $options) = @_;

  # Find handler and render
  my $handler = $options->{handler} || $self->_detect_handler($options);
  $options->{handler} = $handler ||= $self->default_handler;
  if (my $renderer = $self->handlers->{$handler}) {
    return 1 if $renderer->($self, $c, $output, $options);
  }

  # No handler
  else { $c->app->log->error(qq{No handler for "$handler" available.}) }
  return;
}

1;

=head1 NAME

Mojolicious::Renderer - MIME type based renderer

=head1 SYNOPSIS

  use Mojolicious::Renderer;

  my $renderer = Mojolicious::Renderer->new;

=head1 DESCRIPTION

L<Mojolicious::Renderer> is the standard L<Mojolicious> renderer.

See L<Mojolicious::Guides::Rendering> for more.

=head1 ATTRIBUTES

L<Mojolicious::Renderer> implements the following attributes.

=head2 C<cache>

  my $cache = $renderer->cache;
  $renderer = $renderer->cache(Mojo::Cache->new);

Renderer cache, defaults to a L<Mojo::Cache> object.

=head2 C<classes>

  my $classes = $renderer->classes;
  $renderer   = $renderer->classes(['main']);

Classes to use for finding templates in C<DATA> sections, first one has the
highest precedence, defaults to C<main>.

  # Add another class with templates in DATA section
  push @{$renderer->classes}, 'Mojolicious::Plugin::Fun';

=head2 C<default_format>

  my $default = $renderer->default_format;
  $renderer   = $renderer->default_format('html');

The default format to render if C<format> is not set in the stash. The
renderer will use L<Mojolicious/"types"> to look up the content MIME type.

=head2 C<default_handler>

  my $default = $renderer->default_handler;
  $renderer   = $renderer->default_handler('ep');

The default template handler to use for rendering in cases where auto
detection doesn't work, like for C<inline> templates.

=head2 C<encoding>

  my $encoding = $renderer->encoding;
  $renderer    = $renderer->encoding('koi8-r');

Will encode the content if set, defaults to C<UTF-8>.

=head2 C<handlers>

  my $handlers = $renderer->handlers;
  $renderer    = $renderer->handlers({epl => sub {...}});

Registered handlers.

=head2 C<helpers>

  my $helpers = $renderer->helpers;
  $renderer   = $renderer->helpers({url_for => sub {...}});

Registered helpers.

=head2 C<paths>

  my $paths = $renderer->paths;
  $renderer = $renderer->paths(['/home/sri/templates']);

Directories to look for templates in, first one has the highest precedence.

  # Add another "templates" directory
  push @{$renderer->paths}, '/home/sri/templates';

=head1 METHODS

L<Mojolicious::Renderer> inherits all methods from L<Mojo::Base> and
implements the following ones.

=head2 C<new>

  my $renderer = Mojolicious::Renderer->new;

Construct a new renderer and register C<data>, C<json> as well as C<text>
handlers.

=head2 C<add_handler>

  $renderer = $renderer->add_handler(epl => sub {...});

Register a new handler.

=head2 C<add_helper>

  $renderer = $renderer->add_helper(url_for => sub {...});

Register a new helper.

=head2 C<get_data_template>

  my $template = $renderer->get_data_template({
    template       => 'foo/bar',
    format         => 'html',
    handler        => 'epl'
  }, 'foo.html.ep');

Get a DATA template by name, usually used by handlers.

=head2 C<render>

  my ($output, $type) = $renderer->render(Mojolicious::Controller->new);
  my ($output, $type) = $renderer->render(Mojolicious::Controller->new, {
    template => 'foo/bar',
    foo      => 'bar'
  });

Render output through one of the Mojo renderers. This renderer requires some
configuration, at the very least you will need to have a default C<format> and
a default C<handler> as well as a C<template> or C<text>/C<json>. See
L<Mojolicious::Controller/"render"> for a more user-friendly interface.

=head2 C<template_name>

  my $template = $renderer->template_name({
    template => 'foo/bar',
    format   => 'html',
    handler  => 'epl'
  });

Builds a template name based on an options hash reference with C<template>,
C<format> and C<handler>, usually used by handlers.

=head2 C<template_path>

  my $path = $renderer->template_path({
    template => 'foo/bar',
    format   => 'html',
    handler  => 'epl'
  });

Builds a full template path based on an options hash reference with
C<template>, C<format> and C<handler>, usually used by handlers.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
