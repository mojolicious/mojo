package Mojolicious::Plugin::TagHelpers;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::ByteStream;

# Is today's hectic lifestyle making you tense and impatient?
# Shut up and get to the point!
sub register {
    my ($self, $app) = @_;

    # Add "checkbox" helper
    $app->helper(check_box => sub { $self->_input(@_, type => 'checkbox') });

    # Add "file_field" helper
    $app->helper(
        file_field => sub {
            my $c    = shift;
            my $name = shift;
            $self->_tag('input', name => $name, type => 'file', @_);
        }
    );

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

    # Add "hidden_field" helper
    $app->helper(
        hidden_field => sub {
            my $c    = shift;
            my $name = shift;
            $self->_tag('input', name => $name, type => 'hidden', @_);
        }
    );

    # Add "img" helper
    $app->helper(img => sub { shift; $self->_tag('img', src => shift, @_) });

    # Add "input" helper
    $app->helper(input => sub { $self->_input(@_) });

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

    # Add "radio_button" helper
    $app->helper(radio_button => sub { $self->_input(@_, type => 'radio') });

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

    # Add "text_area" helper
    $app->helper(
        text_area => sub {
            my $c    = shift;
            my $name = shift;

            # Value
            my $cb = ref $_[-1] && ref $_[-1] eq 'CODE' ? pop : sub {''};
            if (defined(my $value = $c->param($name))) {
                $cb = sub {$value}
            }

            $self->_tag('textarea', name => $name, @_, $cb);
        }
    );

    # Add "text_field" helper
    $app->helper(text_field => sub { $self->_input(@_) });
}

sub _input {
    my $self  = shift;
    my $c     = shift;
    my $name  = shift;
    my %attrs = @_;

    # Value
    my $p = $c->param($name);
    my $t = $attrs{type} || '';
    if (defined $p && $t ne 'submit') {

        # Checkbox
        if ($t eq 'checkbox') {
            $attrs{checked} = 'checked';
        }

        # Radiobutton
        elsif ($t eq 'radio') {
            my $value = $attrs{value};
            $value = '' unless defined $value;
            $attrs{checked} = 'checked' if $value eq $p;
        }

        # Other
        else { $attrs{value} = $p }

        return $self->_tag('input', name => $name, %attrs);
    }

    # Empty tag
    $self->_tag('input', name => $name, %attrs);
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

=item check_box

    <%= check_box 'employed' %>
    <%= check_box 'employed', id => 'foo' %>

Generate checkbox input element.

=item file_field

    <%= file_field 'avatar' %>
    <%= file_field 'avatar', id => 'foo' %>

Generate file input element.

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

=item hidden_field

    <%= hidden_field 'foo', value => 'bar' %>

Generate hidden input element.

=item img

    <%= img '/foo.jpg' %>
    <%= img '/foo.jpg', alt => 'Image' %>

Generate image tag.

=item input

    <%= input 'first_name' %>
    <%= input 'first_name', value => 'Default name' %>
    <%= input 'employed', type => 'checkbox' %>
    <%= input 'country', type => 'radio', value => 'germany' %>

Generate form input element.

=item label

    <%= label first_name => begin %>First name<% end %>

Generate form label.

=item link_to

    <%= link_to 'index' %>
    <%= link_to index => begin %>Home<% end %>
    <%= link_to index => {foo => 'bar'} => (class => 'links') => begin %>
        Home
    <% end %>
    <%= link_to '/path/to/file' => begin %>File<% end %>
    <%= link_to 'http://mojolicious.org' => begin %>Mojolicious<% end %>
    <%= link_to url_for->query(foo => $foo) => begin %>Retry<% end %>

Generate link to route, path or URL, by default the capitalized link target
will be used as content.

=item radio_button

    <%= radio_button 'country' %>
    <%= radio_button 'country', value => 'germany', id => 'foo' %>

Generate radio input element.

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

=item text_field

    <%= text_field 'first_name' %>
    <%= text_field 'first_name', value => 'Default name' %>

Generate text input element.

=item text_area

    <%= text_area 'foo' %>
    <%= text_area foo => begin %>
        Default!
    <% end %>

Generate textarea element.

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
