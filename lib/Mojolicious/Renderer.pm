package Mojolicious::Renderer;
use Mojo::Base -base;

use File::Spec::Functions 'catfile';
use Mojo::Cache;
use Mojo::JSON 'encode_json';
use Mojo::Home;
use Mojo::Loader 'data_section';
use Mojo::Util qw(decamelize encode md5_sum monkey_patch slurp);

has cache   => sub { Mojo::Cache->new };
has classes => sub { ['main'] };
has default_format => 'html';
has 'default_handler';
has encoding => 'UTF-8';
has [qw(handlers helpers)] => sub { {} };
has paths => sub { [] };

# Bundled templates
my $TEMPLATES = Mojo::Home->new(Mojo::Home->new->mojo_lib_dir)
  ->rel_dir('Mojolicious/resources/templates');

sub DESTROY { Mojo::Util::_teardown($_) for @{shift->{namespaces}} }

sub accepts {
  my ($self, $c) = (shift, shift);

  # List representations
  my $req = $c->req;
  my @exts = @{$c->app->types->detect($req->headers->accept, $req->is_xhr)};
  if (!@exts && (my $format = $c->stash->{format} || $req->param('format'))) {
    push @exts, $format;
  }
  return \@exts unless @_;

  # Find best representation
  for my $ext (@exts) { $ext eq $_ and return $ext for @_ }
  return @exts ? undef : shift;
}

sub add_handler { $_[0]->handlers->{$_[1]} = $_[2] and return $_[0] }

sub add_helper {
  my ($self, $name, $cb) = @_;
  $self->helpers->{$name} = $cb;
  delete $self->{proxy};
  return $self;
}

sub get_data_template {
  my ($self, $options) = @_;
  return undef unless my $template = $self->template_name($options);
  return data_section $self->{index}{$template}, $template;
}

sub get_helper {
  my ($self, $name) = @_;

  if (my $h = $self->{proxy}{$name} || $self->helpers->{$name}) { return $h }

  my $found;
  my $class = 'Mojolicious::Renderer::Helpers::' . md5_sum "$name:$self";
  my $re = length $name ? qr/^(\Q$name\E\.([^.]+))/ : qr/^(([^.]+))/;
  for my $key (keys %{$self->helpers}) {
    $key =~ $re ? ($found, my $method) = (1, $2) : next;
    my $sub = $self->get_helper($1);
    monkey_patch $class, $method => sub { ${shift()}->$sub(@_) };
  }

  $found ? push @{$self->{namespaces}}, $class : return undef;
  return $self->{proxy}{$name} = sub { bless \(my $dummy = shift), $class };
}

sub render {
  my ($self, $c, $args) = @_;

  # Localize "extends" and "layout" to allow argument overrides
  my $stash = $c->stash;
  local $stash->{layout}  = $stash->{layout}  if exists $stash->{layout};
  local $stash->{extends} = $stash->{extends} if exists $stash->{extends};

  # Rendering to string
  local @{$stash}{keys %$args} if my $string = delete $args->{'mojo.string'};
  delete @{$stash}{qw(layout extends)} if $string;

  # All other arguments just become part of the stash
  @$stash{keys %$args} = values %$args;

  my $options = {
    encoding => $self->encoding,
    handler  => $stash->{handler},
    template => delete $stash->{template},
    variant  => $stash->{variant}
  };
  my $inline = $options->{inline} = delete $stash->{inline};
  $options->{handler} //= $self->default_handler if defined $inline;
  $options->{format} = $stash->{format} || $self->default_format;

  # Data
  return delete $stash->{data}, $options->{format} if defined $stash->{data};

  # Text
  return _maybe($options->{encoding}, delete $stash->{text}), $options->{format}
    if defined $stash->{text};

  # JSON
  return encode_json(delete $stash->{json}), 'json' if exists $stash->{json};

  # Template or templateless handler
  $options->{template} //= $self->template_for($c);
  return () unless $self->_render_template($c, \my $output, $options);

  # Inheritance
  my $content = $stash->{'mojo.content'} ||= {};
  local $content->{content} = $output =~ /\S/ ? $output : undef
    if $stash->{extends} || $stash->{layout};
  while ((my $next = _next($stash)) && !defined $inline) {
    @$options{qw(handler template)} = ($stash->{handler}, $next);
    $options->{format} = $stash->{format} || $self->default_format;
    if ($self->_render_template($c, \my $tmp, $options)) { $output = $tmp }
    $content->{content} //= $output if $output =~ /\S/;
  }

  return $string ? $output : _maybe($options->{encoding}, $output),
    $options->{format};
}

sub template_for {
  my ($self, $c) = @_;

  # Normal default template
  my $stash = $c->stash;
  my ($controller, $action) = @$stash{qw(controller action)};
  return join '/', split('-', decamelize $controller), $action
    if $controller && $action;

  # Try the route name if we don't have controller and action
  return undef unless my $route = $c->match->endpoint;
  return $route->name;
}

sub template_handler {
  my ($self, $options) = @_;
  return undef unless my $file = $self->template_name($options);
  return $self->default_handler unless my $handlers = $self->{templates}{$file};
  return $handlers->[0];
}

sub template_name {
  my ($self, $options) = @_;

  return undef unless defined(my $template = $options->{template});
  return undef unless my $format = $options->{format};
  $template .= ".$format";

  $self->warmup unless $self->{templates};

  # Variants
  my $handler = $options->{handler};
  if (defined(my $variant = $options->{variant})) {
    $variant = "$template+$variant";
    my $handlers = $self->{templates}{$variant} // [];
    $template = $variant
      if @$handlers && !defined $handler || grep { $_ eq $handler } @$handlers;
  }

  return defined $handler ? "$template.$handler" : $template;
}

sub template_path {
  my ($self, $options) = @_;
  return undef unless my $name = $self->template_name($options);
  my @parts = split '/', $name;
  -r and return $_ for map { catfile $_, @parts } @{$self->paths}, $TEMPLATES;
  return undef;
}

sub warmup {
  my $self = shift;

  my ($index, $templates) = @$self{qw(index templates)} = ({}, {});

  # Handlers for templates
  s/\.(\w+)$// and push @{$templates->{$_}}, $1
    for map { @{Mojo::Home->new($_)->list_files} } @{$self->paths}, $TEMPLATES;

  # Handlers and classes for DATA templates
  for my $class (reverse @{$self->classes}) {
    $index->{$_} = $class for my @keys = sort keys %{data_section $class};
    s/\.(\w+)$// and unshift @{$templates->{$_}}, $1 for reverse @keys;
  }
}

sub _maybe { $_[0] ? encode @_ : $_[1] }

sub _next {
  my $stash = shift;
  return delete $stash->{extends} if $stash->{extends};
  return undef unless my $layout = delete $stash->{layout};
  return join '/', 'layouts', $layout;
}

sub _render_template {
  my ($self, $c, $output, $options) = @_;

  my $handler = $options->{handler} ||= $self->template_handler($options);
  return undef unless $handler;
  $c->app->log->error(qq{No handler for "$handler" available}) and return undef
    unless my $renderer = $self->handlers->{$handler};

  $renderer->($self, $c, $output, $options);
  return 1 if defined $$output;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Renderer - Generate dynamic content

=head1 SYNOPSIS

  use Mojolicious::Renderer;

  my $renderer = Mojolicious::Renderer->new;
  push @{$renderer->classes}, 'MyApp::Controller::Foo';
  push @{$renderer->paths}, '/home/sri/templates';

=head1 DESCRIPTION

L<Mojolicious::Renderer> is the standard L<Mojolicious> renderer.

See L<Mojolicious::Guides::Rendering> for more.

=head1 ATTRIBUTES

L<Mojolicious::Renderer> implements the following attributes.

=head2 cache

  my $cache = $renderer->cache;
  $renderer = $renderer->cache(Mojo::Cache->new);

Renderer cache, defaults to a L<Mojo::Cache> object.

=head2 classes

  my $classes = $renderer->classes;
  $renderer   = $renderer->classes(['main']);

Classes to use for finding templates in C<DATA> sections with L<Mojo::Loader>,
first one has the highest precedence, defaults to C<main>. Only files with
exactly two extensions will be used, like C<index.html.ep>. Note that for
templates to be detected, these classes need to have already been loaded and
added before L</"warmup"> is called, which usually happens automatically during
application startup.

  # Add another class with templates in DATA section
  push @{$renderer->classes}, 'Mojolicious::Plugin::Fun';

  # Add another class with templates in DATA section and higher precedence
  unshift @{$renderer->classes}, 'Mojolicious::Plugin::MoreFun';

=head2 default_format

  my $default = $renderer->default_format;
  $renderer   = $renderer->default_format('html');

The default format to render if C<format> is not set in the stash, defaults to
C<html>.

=head2 default_handler

  my $default = $renderer->default_handler;
  $renderer   = $renderer->default_handler('ep');

The default template handler to use for rendering in cases where auto-detection
doesn't work, like for C<inline> templates.

=head2 encoding

  my $encoding = $renderer->encoding;
  $renderer    = $renderer->encoding('koi8-r');

Will encode generated content if set, defaults to C<UTF-8>. Note that many
renderers such as L<Mojolicious::Plugin::EPRenderer> also use this value to
determine if template files should be decoded before processing.

=head2 handlers

  my $handlers = $renderer->handlers;
  $renderer    = $renderer->handlers({epl => sub {...}});

Registered handlers.

=head2 helpers

  my $helpers = $renderer->helpers;
  $renderer   = $renderer->helpers({url_for => sub {...}});

Registered helpers.

=head2 paths

  my $paths = $renderer->paths;
  $renderer = $renderer->paths(['/home/sri/templates']);

Directories to look for templates in, first one has the highest precedence.

  # Add another "templates" directory
  push @{$renderer->paths}, '/home/sri/templates';

  # Add another "templates" directory with higher precedence
  unshift @{$renderer->paths}, '/home/sri/themes/blue/templates';

=head1 METHODS

L<Mojolicious::Renderer> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 accepts

  my $all  = $renderer->accepts(Mojolicious::Controller->new);
  my $best = $renderer->accepts(Mojolicious::Controller->new, 'html', 'json');

Select best possible representation for L<Mojolicious::Controller> object from
C<Accept> request header, C<format> stash value or C<format> C<GET>/C<POST>
parameter, defaults to returning the first extension if no preference could be
detected. Since browsers often don't really know what they actually want,
unspecific C<Accept> request headers with more than one MIME type will be
ignored, unless the C<X-Requested-With> header is set to the value
C<XMLHttpRequest>.

=head2 add_handler

  $renderer = $renderer->add_handler(epl => sub {...});

Register a handler.

  $renderer->add_handler(foo => sub {
    my ($renderer, $c, $output, $options) = @_;
    ...
    $$output = 'Hello World!';
  });

=head2 add_helper

  $renderer = $renderer->add_helper(url_for => sub {...});

Register a helper.

  $renderer->add_helper(foo => sub {
    my ($c, @args) = @_;
    ...
  });

=head2 get_data_template

  my $template = $renderer->get_data_template({
    template       => 'foo/bar',
    format         => 'html',
    handler        => 'epl'
  });

Return a C<DATA> section template from L</"classes"> for an options hash
reference with C<template>, C<format>, C<variant> and C<handler> values, or
C<undef> if no template could be found, usually used by handlers.

=head2 get_helper

  my $helper = $renderer->get_helper('url_for');

Get a helper by full name, generate a helper dynamically for a prefix, or return
C<undef> if no helper or prefix could be found. Generated helpers return a
proxy object containing the current controller object and on which nested
helpers can be called.

=head2 render

  my ($output, $format) = $renderer->render(Mojolicious::Controller->new, {
    template => 'foo/bar',
    foo      => 'bar'
  });

Render output through one of the renderers. See
L<Mojolicious::Controller/"render"> for a more user-friendly interface.

=head2 template_for

  my $name = $renderer->template_for(Mojolicious::Controller->new);

Return default template name for L<Mojolicious::Controller> object, or C<undef>
if no name could be generated.

=head2 template_handler

  my $handler = $renderer->template_handler({
    template => 'foo/bar',
    format   => 'html'
  });

Return handler for an options hash reference with C<template>, C<format> and
C<variant> values, or C<undef> if no handler could be found.

=head2 template_name

  my $template = $renderer->template_name({
    template => 'foo/bar',
    format   => 'html',
    handler  => 'epl'
  });

Return a template name for an options hash reference with C<template>,
C<format>, C<variant> and C<handler> values, or C<undef> if no template could be
found, usually used by handlers.

=head2 template_path

  my $path = $renderer->template_path({
    template => 'foo/bar',
    format   => 'html',
    handler  => 'epl'
  });

Return the full template path for an options hash reference with C<template>,
C<format>, C<variant> and C<handler> values, or C<undef> if the file does not
exist in L</"paths">, usually used by handlers.

=head2 warmup

  $renderer->warmup;

Prepare templates from L</"classes"> for future use.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
