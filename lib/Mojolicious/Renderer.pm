package Mojolicious::Renderer;
use Mojo::Base -base;

use File::Spec::Functions 'catfile';
use Mojo::Cache;
use Mojo::JSON;
use Mojo::Home;
use Mojo::Loader;
use Mojo::Util 'encode';

has cache   => sub { Mojo::Cache->new };
has classes => sub { ['main'] };
has default_format => 'html';
has 'default_handler';
has encoding => 'UTF-8';
has [qw(handlers helpers)] => sub { {} };
has paths => sub { [] };

# Bundled templates
my $HOME = Mojo::Home->new;
$HOME->parse(
  $HOME->parse($HOME->mojo_lib_dir)->rel_dir('Mojolicious/templates'));
my %TEMPLATES = map { $_ => $HOME->slurp_rel_file($_) } @{$HOME->list_files};

sub new {
  my $self = shift->SUPER::new(@_)->add_handler(json => \&_json);
  return $self->add_handler(data => \&_data)->add_handler(text => \&_text);
}

sub add_handler { shift->_add(handlers => @_) }
sub add_helper  { shift->_add(helpers  => @_) }

sub get_data_template {
  my ($self, $options) = @_;

  # Index DATA templates
  my $loader = Mojo::Loader->new;
  unless ($self->{index}) {
    my $index = $self->{index} = {};
    for my $class (reverse @{$self->classes}) {
      $index->{$_} = $class for keys %{$loader->data($class)};
    }
  }

  # Find template
  my $template = $self->template_name($options);
  return $loader->data($self->{index}{$template}, $template);
}

sub render {
  my ($self, $c, $args) = @_;
  $args ||= {};

  # Localize "extends" and "layout"
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
  my $data   = delete $stash->{data};
  my $format = $options->{format} = $stash->{format} || $self->default_format;
  my $inline = $options->{inline} = delete $stash->{inline};
  my $json   = delete $stash->{json};
  my $text   = delete $stash->{text};
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
    return undef unless $self->_render_template($c, \$output, $options);
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

  return $output, $format;
}

sub template_name {
  my ($self, $options) = @_;
  return undef unless my $template = $options->{template};
  return undef unless my $format   = $options->{format};
  my $handler = $options->{handler};
  return defined $handler ? "$template.$format.$handler" : "$template.$format";
}

sub template_path {
  my $self = shift;

  # Nameless
  return undef unless my $name = $self->template_name(shift);

  # Search all paths
  for my $path (@{$self->paths}) {
    my $file = catfile($path, split '/', $name);
    return $file if -r $file;
  }

  # Fall back to first path
  return catfile($self->paths->[0], split '/', $name);
}

sub _add {
  my ($self, $attr, $name, $cb) = @_;
  $self->$attr->{$name} = $cb;
  return $self;
}

sub _bundled { $TEMPLATES{"@{[pop]}.html.ep"} }

sub _data {
  my ($self, $c, $output, $options) = @_;
  $$output = $options->{data};
}

sub _detect_handler {
  my ($self, $options) = @_;

  # Templates
  return undef unless my $file = $self->template_name($options);
  unless ($self->{templates}) {
    s/\.(\w+)$// and $self->{templates}{$_} ||= $1
      for map { sort @{Mojo::Home->new($_)->list_files} } @{$self->paths};
  }
  return $self->{templates}{$file} if exists $self->{templates}{$file};

  # DATA templates
  unless ($self->{data}) {
    my $loader = Mojo::Loader->new;
    my @templates = map { sort keys %{$loader->data($_)} } @{$self->classes};
    s/\.(\w+)$// and $self->{data}{$_} ||= $1 for @templates;
  }
  return $self->{data}{$file} if exists $self->{data}{$file};

  # Nothing
  return undef;
}

sub _extends {
  my ($self, $c) = @_;
  my $stash  = $c->stash;
  my $layout = delete $stash->{layout};
  $stash->{extends} ||= join('/', 'layouts', $layout) if $layout;
  return delete $stash->{extends};
}

sub _json {
  my ($self, $c, $output, $options) = @_;
  $$output = Mojo::JSON->new->encode($options->{json});
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
  return undef;
}

sub _text {
  my ($self, $c, $output, $options) = @_;
  $$output = $options->{text};
}

1;

=head1 NAME

Mojolicious::Renderer - Generate dynamic content

=head1 SYNOPSIS

  use Mojolicious::Renderer;

  my $renderer = Mojolicious::Renderer->new;
  push @{$renderer->classes}, 'MyApp::Foo';
  push @{renderer->paths}, '/home/sri/templates';

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

The default format to render if C<format> is not set in the stash.

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
implements the following new ones.

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
  });

Get a C<DATA> section template by name, usually used by handlers.

=head2 C<render>

  my ($output, $format) = $renderer->render(Mojolicious::Controller->new);
  my ($output, $format) = $renderer->render(Mojolicious::Controller->new, {
    template => 'foo/bar',
    foo      => 'bar'
  });

Render output through one of the renderers. See
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
