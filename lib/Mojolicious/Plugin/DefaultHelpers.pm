package Mojolicious::Plugin::DefaultHelpers;
use Mojo::Base 'Mojolicious::Plugin';

use Data::Dumper ();
use Mojo::ByteStream;

sub register {
  my ($self, $app) = @_;

  # Controller alias helpers
  for my $name (qw(app flash param stash session url_for)) {
    $app->helper($name => sub { shift->$name(@_) });
  }

  # Stash key shortcuts (should not generate log messages)
  for my $name (qw(extends layout title)) {
    $app->helper(
      $name => sub {
        my $self  = shift;
        my $stash = $self->stash;
        $stash->{$name} = shift if @_;
        $self->stash(@_) if @_;
        return $stash->{$name};
      }
    );
  }

  $app->helper(config => sub { shift->app->config(@_) });

  $app->helper(content       => \&_content);
  $app->helper(content_for   => \&_content_for);
  $app->helper(current_route => \&_current_route);
  $app->helper(dumper        => \&_dumper);
  $app->helper(include       => \&_include);
  $app->helper(url_with      => \&_url_with);
}

sub _content {
  my ($self, $name, $content) = @_;
  $name ||= 'content';

  # Set (first come)
  my $c = $self->stash->{'mojo.content'} ||= {};
  $c->{$name} ||= ref $content eq 'CODE' ? $content->() : $content
    if defined $content;

  # Get
  return Mojo::ByteStream->new($c->{$name} // '');
}

sub _content_for {
  my ($self, $name, $content) = @_;
  return _content($self, $name) unless defined $content;
  my $c = $self->stash->{'mojo.content'} ||= {};
  return $c->{$name} .= ref $content eq 'CODE' ? $content->() : $content;
}

sub _current_route {
  return '' unless my $endpoint = shift->match->endpoint;
  return $endpoint->name unless @_;
  return $endpoint->name eq shift;
}

sub _dumper {
  my $self = shift;
  return Data::Dumper->new([@_])->Indent(1)->Sortkeys(1)->Terse(1)->Dump;
}

sub _include {
  my $self     = shift;
  my $template = @_ % 2 ? shift : undef;
  my $args     = {@_};
  $args->{template} = $template if defined $template;

  # "layout" and "extends" can't be localized
  my $layout  = delete $args->{layout};
  my $extends = delete $args->{extends};

  # Localize arguments
  my @keys = keys %$args;
  local @{$self->stash}{@keys} = @{$args}{@keys};

  return $self->render(partial => 1, layout => $layout, extend => $extends);
}

sub _url_with {
  my $self = shift;
  return $self->url_for(@_)->query($self->req->url->query->clone);
}

1;

=head1 NAME

Mojolicious::Plugin::DefaultHelpers - Default helpers plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('DefaultHelpers');

  # Mojolicious::Lite
  plugin 'DefaultHelpers';

=head1 DESCRIPTION

L<Mojolicious::Plugin::DefaultHelpers> is a collection of renderer helpers for
L<Mojolicious>.

This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins, you're welcome to fork it.

=head1 HELPERS

L<Mojolicious::Plugin::DefaultHelpers> implements the following helpers.

=head2 app

  %= app->secret

Alias for L<Mojolicious::Controller/"app">.

=head2 config

  %= config 'something'

Alias for L<Mojo/"config">.

=head2 content

  %= content foo => begin
    test
  % end
  %= content bar => 'Hello World!'
  %= content 'foo'
  %= content 'bar'
  %= content

Store partial rendered content in named buffer and retrieve it.

=head2 content_for

  % content_for foo => begin
    test
  % end
  %= content_for 'foo'

Append partial rendered content to named buffer and retrieve it.

  % content_for message => begin
    Hello
  % end
  % content_for message => begin
    world!
  % end
  %= content_for 'message'

=head2 current_route

  % if (current_route 'login') {
    Welcome to Mojolicious!
  % }
  %= current_route

Check or get name of current route.

=head2 dumper

  %= dumper {some => 'data'}

Dump a Perl data structure with L<Data::Dumper>.

=head2 extends

  % extends 'blue';
  % extends 'blue', title => 'Blue!';

Extend a template. All additional values get merged into the C<stash>.

=head2 flash

  %= flash 'foo'

Alias for L<Mojolicious::Controller/"flash">.

=head2 include

  %= include 'menubar'
  %= include 'menubar', format => 'txt'

Include a partial template, all arguments get localized automatically and are
only available in the partial template.

=head2 layout

  % layout 'green';
  % layout 'green', title => 'Green!';

Render this template with a layout. All additional values get merged into the
C<stash>.

=head2 param

  %= param 'foo'

Alias for L<Mojolicious::Controller/"param">.

=head2 session

  %= session 'foo'

Alias for L<Mojolicious::Controller/"session">.

=head2 stash

  %= stash 'foo'
  % stash foo => 'bar';

Alias for L<Mojolicious::Controller/"stash">.

  %= stash 'name' // 'Somebody'

=head2 title

  % title 'Welcome!';
  % title 'Welcome!', foo => 'bar';
  %= title

Page title. All additional values get merged into the C<stash>.

=head2 url_for

  %= url_for 'named', controller => 'bar', action => 'baz'

Alias for L<Mojolicious::Controller/"url_for">.

=head2 url_with

  %= url_with 'named', controller => 'bar', action => 'baz'

Does the same as C<url_for>, but inherits query parameters from the current
request.

  %= url_with->query([page => 2])

=head1 METHODS

L<Mojolicious::Plugin::DefaultHelpers> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
