package Mojolicious::Plugin::DefaultHelpers;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

require Data::Dumper;

# You're watching Futurama,
# the show that doesn't condone the cool crime of robbery.
sub register {
    my ($self, $app) = @_;

    # Add "app" helper
    $app->renderer->add_helper(app => sub { shift->app });

    # Add "cache" helper
    my $cache = {};
    $app->renderer->add_helper(
        cache => sub {
            shift;

            # Callback
            my $cb = pop;
            return '' unless ref $cb && ref $cb eq 'CODE';

            # Name
            my $name = pop || join '', map { $_ || '' } caller(1);

            # Cached
            return $cache->{$name} if exists $cache->{$name};

            # Cache
            $cache->{$name} = $cb->();
        }
    );

    # Add "content" helper
    $app->renderer->add_helper(content => sub { shift->render_inner(@_) });

    # Add "dumper" helper
    $app->renderer->add_helper(
        dumper => sub {
            shift;
            Data::Dumper->new([@_])->Maxdepth(2)->Indent(1)->Terse(1)->Dump;
        }
    );

    # Add "extends" helper
    $app->renderer->add_helper(
        extends => sub {
            my $self  = shift;
            my $stash = $self->stash;
            $stash->{extends} = shift if @_;
            $self->stash(@_) if @_;
            return $stash->{extends};
        }
    );

    # Add "flash" helper
    $app->renderer->add_helper(flash => sub { shift->flash(@_) });

    # Add "include" helper
    $app->renderer->add_helper(include => sub { shift->render_partial(@_) });

    # Add "layout" helper
    $app->renderer->add_helper(
        layout => sub {
            my $self  = shift;
            my $stash = $self->stash;
            $stash->{layout} = shift if @_;
            $self->stash(@_) if @_;
            return $stash->{layout};
        }
    );

    # Add "param" helper
    $app->renderer->add_helper(param =>
          sub { wantarray ? (shift->param(@_)) : scalar shift->param(@_); });

    # Add "session" helper
    $app->renderer->add_helper(session => sub { shift->session(@_) });

    # Add "stash" helper
    $app->renderer->add_helper(stash => sub { shift->stash(@_) });

    # Add "url_for" helper
    $app->renderer->add_helper(url_for => sub { shift->url_for(@_) });
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

L<Mojolicous::Plugin::DefaultHelpers> is a collection of renderer helpers for
L<Mojolicious>.

=head2 Helpers

=over 4

=item cache

    <%= cache begin %>
        <%= time %>
    <% end %>
    <%= cache foo => begin %>
        <%= time %>
    <% end %>

Cache block result in memory and prevent future execution.
Note that this helper is EXPERIMENTAL and might change without warning!

=item content

    <%= content %>

Insert content into a layout template.

=item dumper

    <%= dumper $foo %>

Dump a Perl data structure using L<Data::Dumper>.

=item extends

    <% extends 'foo'; %>

Extend a template.

=item flash

    <%= flash 'foo' %>

Access flash values.

=item include

    <%= include 'menubar' %>
    <%= include 'menubar', format => 'txt' %>

Include a partial template.

=item layout

    <% layout 'green'; %>

Render this template with a layout.

=item param

    <%= param 'foo' %>

Access request parameters and routes captures.

=item session

    <%= session 'foo' %>

Access session values.

=item stash

    <%= stash 'foo' %>
    <% stash foo => 'bar'; %>

Access stash values.

=item url_for

    <%= url_for %>
    <%= url_for 'index' %>
    <%= url_for 'index', foo => 'bar' %>

Generate URLs.

=back

=head1 METHODS

L<Mojolicious::Plugin::DefaultHelpers> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
