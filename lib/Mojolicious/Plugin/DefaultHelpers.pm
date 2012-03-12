package Mojolicious::Plugin::DefaultHelpers;
use Mojo::Base 'Mojolicious::Plugin';

require Data::Dumper;

# "You're watching Futurama,
#  the show that doesn't condone the cool crime of robbery."
sub register {
  my ($self, $app) = @_;

  # Controller alias helpers
  for my $name (qw/app flash param stash session url_for/) {
    $app->helper($name => sub { shift->$name(@_) });
  }

  # Stash key shortcuts
  for my $name (qw/extends layout title/) {
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

  # Add "config" helper
  $app->helper(config => sub { shift->app->config(@_) });

  # Add "content" helper
  $app->helper(content => sub { shift->render_content(@_) });

  # Add "content_for" helper
  $app->helper(
    content_for => sub {
      my ($self, $name) = (shift, shift);
      $self->render_content($name, $self->render_content($name), @_);
    }
  );

  # Add "current_route" helper
  $app->helper(
    current_route => sub {
      my $self = shift;
      return '' unless my $endpoint = $self->match->endpoint;
      return $endpoint->name unless @_;
      return $endpoint->name eq shift;
    }
  );

  # Add "dumper" helper
  $app->helper(
    dumper => sub {
      shift;
      Data::Dumper->new([@_])->Indent(1)->Terse(1)->Dump;
    }
  );

  # Add "include" helper
  $app->helper(
    include => sub {
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

      return $self->render_partial(layout => $layout, extend => $extends);
    }
  );

  # Add "memorize" helper
  my $memorize = {};
  $app->helper(
    memorize => sub {
      shift;
      my $cb = pop;
      return '' unless ref $cb && ref $cb eq 'CODE';
      my $name = shift;
      my $args;
      if (ref $name && ref $name eq 'HASH') {
        $args = $name;
        $name = undef;
      }
      else { $args = shift || {} }

      # Default name
      $name ||= join '', map { $_ || '' } (caller(1))[0 .. 3];

      # Expire
      my $expires = $args->{expires} || 0;
      delete $memorize->{$name}
        if exists $memorize->{$name}
          && $expires > 0
          && $memorize->{$name}->{expires} < time;

      # Memorized
      return $memorize->{$name}->{content} if exists $memorize->{$name};

      # Memorize
      $memorize->{$name}->{expires} = $expires;
      $memorize->{$name}->{content} = $cb->();
    }
  );

  # Add "url_with" helper
  $app->helper(
    url_with => sub {
      my $self = shift;
      return $self->url_for(@_)->query($self->req->url->query->clone);
    }
  );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::DefaultHelpers - Default helpers plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('DefaultHelpers');

  # Mojolicious::Lite
  plugin 'DefaultHelpers';

=head1 DESCRIPTION

L<Mojolicious::Plugin::DefaultHelpers> is a collection of renderer helpers
for L<Mojolicious>. This is a core plugin, that means it is always enabled
and its code a good example for learning to build new plugins.

=head1 HELPERS

L<Mojolicious::Plugin::DefaultHelpers> implements the following helpers.

=head2 C<app>

  %= app->secret

Alias for L<Mojolicious::Controller/"app">.

=head2 C<config>

  %= config 'something'

Alias for L<Mojo/"config">.

=head2 C<content>

  %= content

Insert content into a layout template.

=head2 C<content_for>

  % content_for foo => begin
    test
  % end
  %= content_for 'foo'

Append content to named buffer and retrieve it.

  % content_for message => begin
    Hello
  % end
  % content_for message => begin
    world!
  % end
  %= content_for 'message'

=head2 C<current_route>

  % if (current_route 'hello') {
    Hello World!
  % }
  %= current_route

Check or return name of current route. Note that this helper is EXPERIMENTAL
and might change without warning!

=head2 C<dumper>

  %= dumper $foo

Dump a Perl data structure using L<Data::Dumper>.

=head2 C<extends>

  % extends 'foo';

Extend a template.

=head2 C<flash>

  %= flash 'foo'

Alias for L<Mojolicious::Controller/"flash">.

=head2 C<include>

  %= include 'menubar'
  %= include 'menubar', format => 'txt'

Include a partial template, all arguments get localized automatically and are
only available in the partial template.

=head2 C<layout>

  % layout 'green';

Render this template with a layout.

=head2 C<memorize>

  %= memorize begin
    %= time
  % end
  %= memorize {expires => time + 1} => begin
    %= time
  % end
  %= memorize foo => begin
    %= time
  % end
  %= memorize foo => {expires => time + 1} => begin
    %= time
  % end

Memorize block result in memory and prevent future execution.

=head2 C<param>

  %= param 'foo'

Alias for L<Mojolicious::Controller/"param">.

=head2 C<session>

  %= session 'foo'

Alias for L<Mojolicious::Controller/"session">.

=head2 C<stash>

  %= stash 'foo'
  % stash foo => 'bar';

Alias for L<Mojolicious::Controller/"stash">.

=head2 C<title>

  % title 'Welcome!';
  %= title

Page title.

=head2 C<url_for>

  %= url_for 'named', controller => 'bar', action => 'baz'

Alias for L<Mojolicious::Controller/"url_for">.

=head2 C<url_with>

  %= url_with 'named', controller => 'bar', action => 'baz'

Does the same as C<url_for>, but inherits query parameters from the current
request. Note that this helper is EXPERIMENTAL and might change without
warning!

  %= url_with->query([page => 2])

=head1 METHODS

L<Mojolicious::Plugin::DefaultHelpers> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register;

Register helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
