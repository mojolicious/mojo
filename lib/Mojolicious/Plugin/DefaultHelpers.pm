package Mojolicious::Plugin::DefaultHelpers;
use Mojo::Base 'Mojolicious::Plugin';

require Data::Dumper;

# "You're watching Futurama,
#  the show that doesn't condone the cool crime of robbery."
sub register {
  my ($self, $app) = @_;

  # Add "app" helper
  $app->helper(app => sub { shift->app });

  # Add "content" helper
  $app->helper(content => sub { shift->render_content(@_) });

  # Add "content_for" helper
  $app->helper(
    content_for => sub {
      my $self = shift;
      my $name = shift;
      $self->render_content($name, $self->render_content($name), @_);
    }
  );

  # Add "dumper" helper
  $app->helper(
    dumper => sub {
      shift;
      Data::Dumper->new([@_])->Maxdepth(2)->Indent(1)->Terse(1)->Dump;
    }
  );

  # Add "extends" helper
  $app->helper(
    extends => sub {
      my $self  = shift;
      my $stash = $self->stash;
      $stash->{extends} = shift if @_;
      $self->stash(@_) if @_;
      $stash->{extends};
    }
  );

  # Add "flash" helper
  $app->helper(flash => sub { shift->flash(@_) });

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
      my @keys  = keys %$args;
      my $i     = 0;
      my $stash = $self->stash;
    START:
      local $stash->{$keys[$i]} = $args->{$keys[$i]};
      $i++;
      goto START unless $i >= @keys;

      $self->render_partial(layout => $layout, extend => $extends);
    }
  );

  # Add "layout" helper
  $app->helper(
    layout => sub {
      my $self  = shift;
      my $stash = $self->stash;
      $stash->{layout} = shift if @_;
      $self->stash(@_) if @_;
      $stash->{layout};
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

  # Add "param" helper
  $app->helper(
    param => sub { wantarray ? (shift->param(@_)) : scalar shift->param(@_); }
  );

  # Add "session" helper
  $app->helper(session => sub { shift->session(@_) });

  # Add "stash" helper
  $app->helper(stash => sub { shift->stash(@_) });

  # Add "title" helper
  $app->helper(
    title => sub {
      my $self  = shift;
      my $stash = $self->stash;
      $stash->{title} = shift if @_;
      $self->stash(@_) if @_;
      $stash->{title};
    }
  );

  # Add "url_for" helper
  $app->helper(url_for => sub { shift->url_for(@_) });
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::DefaultHelpers - Default Helpers Plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('default_helpers');

  # Mojolicious::Lite
  plugin 'default_helpers';

=head1 DESCRIPTION

L<Mojolicious::Plugin::DefaultHelpers> is a collection of renderer helpers
for L<Mojolicious>.
This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins.

=head1 HELPERS

=head2 C<content>

  <%= content %>

Insert content into a layout template.

=head2 C<content_for>

  <% content_for foo => begin %>
    test
  <% end %>
  <%= content_for 'foo' %>

Append content to named buffer and retrieve it.

  <% content_for message => begin %>
    Hello
  <% end %>
  <% content_for message => begin %>
    world!
  <% end %>
  <%= content_for 'message' %>

=head2 C<dumper>

  <%= dumper $foo %>

Dump a Perl data structure using L<Data::Dumper>.

=head2 C<extends>

  <% extends 'foo'; %>

Extend a template.

=head2 C<flash>

  <%= flash 'foo' %>

Access flash values.

=head2 C<include>

  <%= include 'menubar' %>
  <%= include 'menubar', format => 'txt' %>

Include a partial template, all arguments get localized automatically and are
only available in the partial template.

=head2 C<layout>

  <% layout 'green'; %>

Render this template with a layout.

=head2 C<memorize>

  <%= memorize begin %>
    <%= time %>
  <% end %>
  <%= memorize {expires => time + 1} => begin %>
    <%= time %>
  <% end %>
  <%= memorize foo => begin %>
    <%= time %>
  <% end %>
  <%= memorize foo => {expires => time + 1} => begin %>
    <%= time %>
  <% end %>

Memorize block result in memory and prevent future execution.

=head2 C<param>

  <%= param 'foo' %>

Access GET/POST parameters and route captures.

=head2 C<session>

  <%= session 'foo' %>

Access session values.

=head2 C<stash>

  <%= stash 'foo' %>
  <% stash foo => 'bar'; %>

Access stash values.

=head2 C<title>

  <% title 'Welcome!'; %>
  <%= title %>

Page title.

=head2 C<url_for>

  <%= url_for %>
  <%= url_for controller => 'bar', action => 'baz' %>
  <%= url_for 'named', controller => 'bar', action => 'baz' %>
  <%= url_for '/perldoc' %>
  <%= url_for 'http://mojolicio.us/perldoc' %>

Generate a portable L<Mojo::URL> object with base for a route, path or URL.

=head1 METHODS

L<Mojolicious::Plugin::DefaultHelpers> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register;

Register helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
