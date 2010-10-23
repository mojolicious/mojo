package Mojolicious::Plugin::TagHelpers;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::ByteStream 'b';

# Is today's hectic lifestyle making you tense and impatient?
# Shut up and get to the point!
sub register {
    my ($self, $app) = @_;

    # Add "checkbox" helper
    $app->helper(
        check_box => sub {
            $self->_input(
                shift, shift,
                value => shift,
                @_, type => 'checkbox'
            );
        }
    );

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
            my $c   = shift;
            my @url = (shift);

            # Captures
            push @url, shift if ref $_[0] eq 'HASH';

            $self->_tag('form', action => $c->url_for(@url), @_);
        }
    );

    # Add "hidden_field" helper
    $app->helper(
        hidden_field => sub {
            shift;
            $self->_tag(
                'input',
                name  => shift,
                value => shift,
                type  => 'hidden',
                @_
            );
        }
    );

    # Add "input_tag" helper
    $app->helper(input_tag => sub { $self->_input(@_) });

    # Add "javascript" helper
    $app->helper(
        javascript => sub {
            my $c = shift;

            # CDATA
            my $cb;
            my $old = $cb = pop if ref $_[-1] && ref $_[-1] eq 'CODE';
            $cb = sub { '<![CDATA[' . $old->() . ']]>' }
              if $cb;

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
            $self->_tag('script', type => 'text/javascript', @_, $cb);
        }
    );

    # Add "link_to" helper
    $app->helper(
        link_to => sub {
            my $c       = shift;
            my $content = shift;
            my @url     = ($content);

            # Content
            unless (defined $_[-1] && ref $_[-1] eq 'CODE') {
                @url = (shift);
                push @_, sub {$content}
            }

            # Captures
            push @url, shift if ref $_[0] eq 'HASH';

            $self->_tag('a', href => $c->url_for(@url), @_);
        }
    );

    # Add "password_field" helper
    $app->helper(
        password_field => sub {
            my $c    = shift;
            my $name = shift;
            $self->_tag('input', name => $name, type => 'password', @_);
        }
    );

    # Add "radio_button" helper
    $app->helper(
        radio_button => sub {
            $self->_input(shift, shift, value => shift, @_, type => 'radio');
        }
    );

    # Add "select_field" helper
    $app->helper(
        select_field => sub {
            my $c       = shift;
            my $name    = shift;
            my $options = shift;
            my %attrs   = @_;

            # Values
            my %v = map { $_, 1 } $c->param($name);

            # Callback
            my $cb = sub {

                # Pair
                my $pair = shift;
                $pair = [$pair, $pair] unless ref $pair eq 'ARRAY';

                # Attributes
                my %attrs = (value => $pair->[1]);
                $attrs{selected} = 'selected' if exists $v{$pair->[1]};

                # Option tag
                $self->_tag('option', %attrs, sub { $pair->[0] });
            };

            return $self->_tag(
                'select',
                name => $name,
                %attrs,
                sub {

                    # Parts
                    my $parts = '';
                    for my $o (@$options) {

                        # OptGroup
                        if (ref $o eq 'ARRAY' && ref $o->[1] eq 'ARRAY') {
                            $parts .= $self->_tag(
                                'optgroup',
                                label => $o->[0],
                                sub {
                                    join '', map { $cb->($_) } @{$o->[1]};
                                }
                            );
                        }

                        # Option
                        else { $parts .= $cb->($o) }
                    }

                    return $parts;
                }
            );
        }
    );

    # Add "stylesheet" helper
    $app->helper(
        stylesheet => sub {
            my $c = shift;

            # CDATA
            my $cb;
            my $old = $cb = pop if ref $_[-1] && ref $_[-1] eq 'CODE';
            $cb = sub { '<![CDATA[' . $old->() . ']]>' }
              if $cb;

            # Path
            if (@_ % 2 ? ref $_[-1] ne 'CODE' : ref $_[-1] eq 'CODE') {
                return $self->_tag(
                    'link',
                    href  => shift,
                    media => 'screen',
                    rel   => 'stylesheet',
                    type  => 'text/css',
                    @_
                );
            }

            # Block
            $self->_tag('style', type => 'text/css', @_, $cb);
        }
    );

    # Add "submit_button" helper
    $app->helper(
        submit_button => sub {
            my $c     = shift;
            my $value = shift;
            $value = 'Ok' unless defined $value;
            $self->_tag('input', value => $value, type => 'submit', @_);
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
    $p = b($p)->xml_escape if defined $p;

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

# We’ve lost power of the forward Gameboy! Mario not responding!
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
    return b($tag);
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

    <%= check_box employed => 1 %>
    <%= check_box employed => 1, id => 'foo' %>

Generate checkbox input element.

    <input name="employed" type="checkbox" value="1" />
    <input id="foo" name="employed" type="checkbox" value="1" />

=item file_field

    <%= file_field 'avatar' %>
    <%= file_field 'avatar', id => 'foo' %>

Generate file input element.

    <input name="avatar" type="file" />
    <input id="foo" name="avatar" type="file" />

=item form_for

    <%= form_for login => (method => 'post') => begin %>
        <%= text_field 'first_name' %>
        <%= submit_button %>
    <% end %>
    <%= form_for login => {foo => 'bar'} => (method => 'post') => begin %>
        <%= text_field 'first_name' %>
        <%= submit_button %>
    <% end %>
    <%= form_for '/login' => (method => 'post') => begin %>
        <%= text_field 'first_name' %>
        <%= submit_button %>
    <% end %>
    <%= form_for 'http://kraih.com/login' => (method => 'post') => begin %>
        <%= text_field 'first_name' %>
        <%= submit_button %>
    <% end %>

Generate form for route, path or URL.

    <form action="/path/to/login" method="post">
        <input name="first_name" />
        <input value="Ok" type="submit" />
    </form>
    <form action="/path/to/login/bar" method="post">
        <input name="first_name" />
        <input value="Ok" type="submit" />
    </form>
    <form action="/login" method="post">
        <input name="first_name" />
        <input value="Ok" type="submit" />
    </form>
    <form action="http://kraih.com/login" method="post">
        <input name="first_name" />
        <input value="Ok" type="submit" />
    </form>

=item hidden_field

    <%= hidden_field foo => 'bar' %>
    <%= hidden_field foo => 'bar', id => 'bar' %>

Generate hidden input element.

    <input name="foo" type="hidden" value="bar" />
    <input id="bar" name="foo" type="hidden" value="bar" />

=item input_tag

    <%= input_tag 'first_name' %>
    <%= input_tag 'first_name', value => 'Default name' %>
    <%= input_tag 'employed', type => 'checkbox' %>
    <%= input_tag 'country', type => 'radio', value => 'germany' %>

Generate form input element.

    <input name="first_name" />
    <input name="first_name" value="Default name" />
    <input name="employed" type="checkbox" />
    <input name="country" type="radio" value="germany" />

=item javascript

    <%= javascript 'script.js' %>
    <%= javascript begin %>
        var a = 'b';
    <% end %>

Generate script tag for C<Javascript> asset.

    <script src="script.js" type="text/javascript" />
    <script type="text/javascript"><![CDATA[
        var a = 'b';
    ]]></script>

=item link_to

    <%= link_to Home => 'index' %>
    <%= link_to index => begin %>Home<% end %>
    <%= link_to index => {foo => 'bar'} => (class => 'links') => begin %>
        Home
    <% end %>
    <%= link_to '/path/to/file' => begin %>File<% end %>
    <%= link_to 'http://mojolicious.org' => begin %>Mojolicious<% end %>
    <%= link_to url_for->query(foo => $foo) => begin %>Retry<% end %>

Generate link to route, path or URL, by default the capitalized link target
will be used as content.

    <a href="/path/to/index">Home</a>
    <a href="/path/to/index">Home</a>
    <a class="links" href="/path/to/index/bar">Home</a>
    <a href="/path/to/file">File</a>
    <a href="http://mojolicious.org">Mojolicious</a>
    <a href="/current/path?foo=something">Retry</a>

=item password_field

    <%= password_field 'pass' %>
    <%= password_field 'pass', id => 'foo' %>

Generate password input element.

    <input name="pass" type="password" />
    <input id="foo" name="pass" type="password" />

=item radio_button

    <%= radio_button country => 'germany' %>
    <%= radio_button country => 'germany', id => 'foo' %>

Generate radio input element.

    <input name="country" type="radio" value="germany" />
    <input id="foo" name="country" type="radio" value="germany" />

=item select_field

    <%= select_field language => [qw/de en/] %>
    <%= select_field language => [qw/de en/], id => 'lang' %>
    <%= select_field country => [[Germany => 'de'], 'en'] %>
    <%= select_field country => [[Europe => [Germany => 'de']]] %>

Generate select, option and optgroup elements.

    <select name="language">
        <option name="de">de</option>
        <option name="en">en</option>
    </select>
    <select id="lang" name="language">
        <option name="de">de</option>
        <option name="en">en</option>
    </select>
    <select name="country">
        <option name="de">Germany</option>
        <option name="en">en</option>
    </select>
    <select id="lang" name="language">
        <optgroup label="Europe">
            <option name="de">Germany</option>
            <option name="en">en</option>
        </optgroup>
    </select>

=item stylesheet

    <%= stylesheet 'foo.css %>
    <%= stylesheet begin %>
        body {color: #000}
    <% end %>

Generate style or link tag for C<CSS> asset.

    <link href="foo.css" media="screen" rel="stylesheet" type="text/css" />
    <style type="text/css"><![CDATA[
        body {color: #000}
    ]]></style>

=item submit_button

    <%= submit_button %>
    <%= submit_button 'Ok!', id => 'foo' %>

Generate submit input element.

    <input type="submit" value="Ok" />
    <input id="foo" type="submit" value="Ok!" />

=item tag

    <%= tag 'div' %>
    <%= tag 'div', id => 'foo' %>
    <%= tag div => begin %>Content<% end %>

HTML5 tag generator.

    <div />
    <div id="foo" />
    <div>Content</div>

=item text_field

    <%= text_field 'first_name' %>
    <%= text_field 'first_name', value => 'Default name' %>

Generate text input element.

    <input name="first_name" />
    <input name="first_name" value="Default name" />

=item text_area

    <%= text_area 'foo' %>
    <%= text_area foo => begin %>
        Default!
    <% end %>

Generate textarea element.

    <textarea name="foo"></textarea>
    <textarea name="foo">
        Default!
    </textarea>

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
