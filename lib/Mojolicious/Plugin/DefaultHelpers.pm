# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugin::DefaultHelpers;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

require Data::Dumper;

# You're watching Futurama,
# the show that doesn't condone the cool crime of robbery.
sub register {
    my ($self, $app) = @_;

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
    $app->renderer->add_helper(extends => sub { shift->stash(extends => @_) }
    );

    # Add "include" helper
    $app->renderer->add_helper(include => sub { shift->render_partial(@_) });

    # Add "layout" helper
    $app->renderer->add_helper(layout => sub { shift->stash(layout => @_) });

    # Add "param" helper
    $app->renderer->add_helper(param =>
          sub { wantarray ? (shift->param(@_)) : scalar shift->param(@_); });

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

=head2 HELPERS

=over 4

=item content

Insert content into a layout template.

=item dumper

Dump a Perl data structure using L<Data::Dumper>.

=item extends

Extend a template.

=item include

Include a partial template.

=item layout

Render this template with a layout.

=item param

Access request parameters and routes captures.

=item url_for

Generate URLs.

=back

=head1 METHODS

L<Mojolicious::Plugin::DefaultHelpers> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;
    
Register the helpers.

=cut
