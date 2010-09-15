package Mojolicious::Plugin::TagHelpers;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::ByteStream;

# Is today's hectic lifestyle making you tense and impatient?
# Shut up and get to the point!
sub register {
    my ($self, $app) = @_;

    # Add "form_for" helper
    $app->helper(
        form_for => sub {
            my $c    = shift;
            my $name = shift;

            # Captures
            my $captures = ref $_[0] eq 'HASH' ? shift : {};

            $self->_tag('form', action => $c->url_for($name, $captures), @_);
        }
    );

    # Add "img" helper
    $app->helper(img => sub { shift; $self->_tag('img', src => shift, @_) });

    # Add "input" helper
    $app->helper(
        input => sub {
            my $c    = shift;
            my $name = shift;

            # Value
            if (defined(my $p = $c->param($name))) {

                # Attributes
                my %attrs = @_;

                # Checkbox
                if (($attrs{type} || '') eq 'checkbox') {
                    $attrs{checked} = 'checked';
                }

		# Radiobutton
                elsif (($attrs{type} || '') eq 'radio') {
                    $attrs{checked} = 'checked'
		      if (($attrs{value} || '') eq $p);
                }

                # Other
                else { $attrs{value} = $p }

                return $self->_tag('input', name => $name, %attrs);
            }

            # Empty tag
            $self->_tag('input', name => $name, @_);
        }
    );

    # Add "label" helper
    $app->helper(
        label => sub { shift; $self->_tag('label', for => shift, @_) });

    # Add "link_to" helper
    $app->helper(
        link_to => sub {
            my $c    = shift;
            my $name = shift;

            # Captures
            my $captures = ref $_[0] eq 'HASH' ? shift : {};

            # Default content
            push @_, sub { ucfirst $name }
              unless defined $_[-1] && ref $_[-1] eq 'CODE';

            $self->_tag('a', href => $c->url_for($name, $captures), @_);
        }
    );

    # Add "script" helper
    $app->helper(
        script => sub {
            my $c = shift;

            # Path
            if (@_ % 2 ? ref $_[-1] ne 'CODE' : ref $_[-1] eq 'CODE') {
                return $self->_tag(
                    'script',
                    src  => shift,
                    type => 'text/javascript',
                    @_
                );
            }

            # Block
            $self->_tag('script', type => 'text/javascript', @_);
        }
    );

    # Add "tag" helper
    $app->helper(tag => sub { shift; $self->_tag(@_) });
}

sub _tag {
    my $self = shift;
    my $name = shift;

    # Callback
    my $cb = defined $_[-1] && ref($_[-1]) eq 'CODE' ? pop @_ : undef;
    pop if @_ % 2;

    # Tag
    my $tag = "<$name";

    # Attributes
    my %attrs = @_;
    for my $key (sort keys %attrs) {
        my $value = $attrs{$key};
        $tag .= qq/ $key="$value"/;
    }

    # Block
    if ($cb) {
        $tag .= '>';
        $tag .= $cb->();
        $tag .= "<\/$name>";
    }

    # Empty element
    else { $tag .= ' />' }

    # Prevent escaping
    return Mojo::ByteStream->new($tag);
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::TagHelpers - Tag Helpers Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('tag_helpers');

    # Mojolicious::Lite
    plugin 'tag_helpers';

=head1 DESCRIPTION

L<Mojolicous::Plugin::TagHelpers> is a collection of HTML5 tag helpers for
L<Mojolicious>.
Note that this module is EXPERIMENTAL and might change without warning!

=head2 Helpers

=over 4

=item form_for

    <%= form_for login => (method => 'post') => begin %>
        <%= input 'first_name' %>
    <% end %>
    <%= form_for login => {foo => 'bar'} => (method => 'post') => begin %>
        <%= input 'first_name' %>
    <% end %>
    <%= form_for '/login' => (method => 'post') => begin %>
        <%= input 'first_name' %>
    <% end %>
    <%= form_for 'http://kraih.com/login' => (method => 'post') => begin %>
        <%= input 'first_name' %>
    <% end %>

Generate form for route, path or URL.

=item img

    <%= img '/foo.jpg' %>
    <%= img '/foo.jpg', alt => 'Image' %>

Generate image tag.

=item input

    <%= input 'first_name' %>
    <%= input 'first_name', value => 'Default name' %>
    <%= input 'employed', type => 'checkbox'%>

Generate form input element. By default, type => 'text' is assumed.

Input elements, including checkbox and radio button groups,
automatically preserve the current value as set in the request's
parameters.

Generate form input element.

=item label

    <%= label first_name => begin %>First name<% end %>

Generate form label.

=item link_to

    <%= link_to index %>
    <%= link_to index => begin %>Home<% end %>
    <%= link_to index => {foo => 'bar'} => (class => 'links') => begin %>
        Home
    <% end %>
    <%= link_to '/path/to/file' => begin %>File<% end %>
    <%= link_to 'http://mojolicious.org' => begin %>Mojolicious<% end %>
    <%= link_to url_for('search')->query(query => $self->param('query') => begin %>Search again<% end %>

Generate link to route, path or URL. Uses the capitalized link target
for default content.

=item script

    <%= script '/script.js' %>
    <%= script begin %>
        var a = 'b';
    <% end %>

Generate script tag.

=item tag

    <%= tag 'div' %>
    <%= tag 'div', id => 'foo' %>
    <%= tag div => begin %>Content<% end %>

HTML5 tag generator.

=back

=head1 METHODS

L<Mojolicious::Plugin::TagHelpers> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
