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
    $app->renderer->add_helper(
        form_for => sub {
            my $c    = shift;
            my $name = shift;

            # Captures
            my $captures = ref $_[0] eq 'HASH' ? shift : {};

            $self->_tag('form', action => $c->url_for($name, $captures), @_);
        }
    );

    # Add "img" helper
    $app->renderer->add_helper(
        img => sub { shift; $self->_tag('img', src => shift, @_) });

    # Add "input" helper
    $app->renderer->add_helper(
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

                # Other
                else { $attrs{value} = $p }

                return $self->_tag('input', name => $name, %attrs);
            }

            # Empty tag
            $self->_tag('input', name => $name, @_);
        }
    );

    # Add "label" helper
    $app->renderer->add_helper(
        label => sub { shift; $self->_tag('label', for => shift, @_) });

    # Add "link_to" helper
    $app->renderer->add_helper(
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
    $app->renderer->add_helper(
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
    $app->renderer->add_helper(tag => sub { shift; $self->_tag(@_) });
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

    <%= form_for login => (method => 'post') => {%>
        <%= input 'first_name' %>
    <%}%>
    <%= form_for login => {foo => 'bar'} => (method => 'post') => {%>
        <%= input 'first_name' %>
    <%}%>
    <%= form_for '/login' => (method => 'post') => {%>
        <%= input 'first_name' %>
    <%}%>
    <%= form_for 'http://mojolicious.org/login' => (method => 'post') => {%>
        <%= input 'first_name' %>
    <%}%>

Generate form for route, path or URL.

=item img

    <%= img '/foo.jpg' %>
    <%= img '/foo.jpg', alt => 'Image' %>

Generate image tag.

=item input

    <%= input 'first_name' %>
    <%= input 'first_name', value => 'Default name' %>

Generate form input element.

=item label

    <%= label first_name => {%>First name<%}%>

Generate form label.

=item link_to

    <%= link_to index => {%>Home<%}%>
    <%= link_to index => {foo => 'bar'} => (class => 'links') => {%>Home<%}%>
    <%= link_to '/path/to/file' => {%>File<%}%>
    <%= link_to 'http://mojolicious.org' => {%>Mojolicious<%}%>

Generate link to route, path or URL.

=item script

    <%= script '/script.js' %>
    <%= script {%>
        var a = 'b';
    <%}%>

Generate script tag.

=item tag

    <%= tag 'div' %>
    <%= tag 'div', id => 'foo' %>
    <%= tag div => {%>Content<%}%>

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
