package Mojolicious::Plugin::PodRenderer;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use IO::File;
use Mojo::ByteStream 'b';
use Mojo::Command;
use Mojo::DOM;

# Core module since Perl 5.9.3, so it might not always be present
BEGIN {
    die <<'EOF' unless eval { require Pod::Simple::HTML; 1 } }
Module "Pod::Simple" not present in this version of Perl.
Please install it manually or upgrade Perl to at least version 5.10.
EOF

use Pod::Simple::Search;

# Perldoc template
our $PERLDOC = Mojo::Command->new->get_data('perldoc.html.ep', __PACKAGE__);

# This is my first visit to the Galaxy of Terror and I'd like it to be a
# pleasant one.
sub register {
    my ($self, $app, $conf) = @_;

    # Config
    $conf ||= {};
    my $name       = $conf->{name}       || 'pod';
    my $preprocess = $conf->{preprocess} || 'ep';
    my $prefix     = $conf->{prefix}     || 'perldoc';

    # Add "pod" handler
    $app->renderer->add_handler(
        $name => sub {
            my ($r, $c, $output, $options) = @_;

            # Preprocess with ep and then render
            $$output = $self->_pod_to_html($$output)
              if $r->handler->{$preprocess}->($r, $c, $output, $options);
        }
    );

    # Add "pod_to_html" helper
    $app->helper(pod_to_html => sub { shift; b($self->_pod_to_html(@_)) });

    # Perldoc
    $app->routes->any(
        $prefix => sub {
            my $self = shift;

            # Module
            my $module = $self->req->url->query->params->[0]
              || 'Mojolicious::Guides';

            # Path
            my $path = Pod::Simple::Search->new->find($module);

            # Redirect to CPAN
            my $cpan = 'http://search.cpan.org/perldoc';
            return $self->redirect_to(
                "$cpan?" . $self->req->url->query->to_string)
              unless $path && -r $path;

            # POD
            my $file = IO::File->new;
            $file->open("< $path");
            my $dom =
              Mojo::DOM->new->parse($self->pod_to_html(join '', <$file>));
            $dom->find('a[href]')->each(
                sub {
                    my $attrs = shift->attrs;
                    if ($attrs->{href} =~ /^$cpan/) {
                        my $url = $self->url_for("/$prefix");
                        $attrs->{href} =~ s/^$cpan/$url/;
                    }
                }
            );
            $dom->find('pre')->each(
                sub {
                    my $attrs = shift->attrs;
                    my $class = $attrs->{class};
                    $attrs->{class} =
                      defined $class ? "$class prettyprint" : 'prettyprint';
                }
            );

            # Title
            my $title = 'Perldoc';
            $dom->find('h1 + p')->until(sub { $title = shift->text });

            # Render
            $self->render(
                inline  => $PERLDOC,
                perldoc => "$dom",
                title   => $title
            );
        }
    ) if $prefix;
}

sub _pod_to_html {
    my ($self, $pod) = @_;

    # Shortcut
    return unless defined $pod;

    # Block
    $pod = $pod->() if ref $pod eq 'CODE';

    # Parser
    my $parser = Pod::Simple::HTML->new;
    $parser->force_title('');
    $parser->html_header_before_title('');
    $parser->html_header_after_title('');
    $parser->html_footer('');

    # Parse
    my $output;
    $parser->output_string(\$output);
    eval { $parser->parse_string_document($pod) };
    return $@ if $@;

    # Filter
    $output =~ s/<a name='___top' class='dummyTopAnchor'\s*?><\/a>\n//g;
    $output =~ s/<a class='u'.*?name=".*?"\s*>(.*?)<\/a>/$1/sg;

    return $output;
}

1;
__DATA__

@@ perldoc.html.ep
<!doctype html><html>
    <head>
        <title><%= $title %></title>
        %= stylesheet 'css/prettify-mojo.css'
        %= javascript 'js/prettify.js'
        <style type="text/css">
            a { color: inherit; }
            body {
                background-color: #f5f6f8;
                color: #333;
                font: 0.9em Verdana, sans-serif;
                margin-left: 5em;
                margin-right: 5em;
                margin-top: 0;
                text-shadow: #ddd 0 1px 0;
            }
            footer {
                padding-top: 1em;
                text-align: center;
            }
            h1, h2, h3 {
                font: 1.5em Georgia, Times, serif;
                margin: 0;
            }
            pre {
                background-color: #1a1a1a;
                -moz-border-radius: 5px;
                border-radius: 5px;
                color: #eee;
                font-family: 'Menlo', 'Monaco', Courier, monospace !important;
                text-align: left;
                text-shadow: #333 0 1px 0;
                padding-bottom: 1.5em;
                padding-top: 1.5em;
            }
            #perldoc {
                background-color: #fff;
                -moz-border-radius-bottomleft: 5px;
                border-bottom-left-radius: 5px;
                -moz-border-radius-bottomright: 5px;
                border-bottom-right-radius: 5px;
                -moz-box-shadow: 0px 0px 2px #ccc;
                -webkit-box-shadow: 0px 0px 2px #ccc;
                box-shadow: 0px 0px 2px #ccc;
                padding: 3em;
            }
        </style>
    </head>
    <body onload="prettyPrint()">
        <section id="perldoc"><%== $perldoc %></section>
        <footer>
            %= link_to 'http://mojolicio.us' => begin
                <img src="mojolicious-black.png" alt="Mojolicious logo">
            % end
        </footer>
    </body>
</html>

__END__

=head1 NAME

Mojolicious::Plugin::PodRenderer - POD Renderer Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('pod_renderer');
    $self->plugin(pod_renderer => {name => 'foo'});
    $self->plugin(pod_renderer => {preprocess => 'epl'});
    $self->render('some_template', handler => 'pod');
    <%= pod_to_html "=head1 TEST\n\nC<123>" %>

    # Mojolicious::Lite
    plugin 'pod_renderer';
    plugin pod_renderer => {name => 'foo'};
    plugin pod_renderer => {preprocess => 'epl'};
    $self->render('some_template', handler => 'pod');
    <%= pod_to_html "=head1 TEST\n\nC<123>" %>

=head1 DESCRIPTION

L<Mojolicous::Plugin::PodRenderer> is a renderer for true Perl hackers, rawr!

=head2 Options

=over 4

=item name

    # Mojolicious::Lite
    plugin pod_renderer => {name => 'foo'};

=item preprocess

    # Mojolicious::Lite
    plugin pod_renderer => {preprocess => 'epl'};

=back

=head2 Helpers

=over 4

=item pod_to_html

    <%= pod_to_html '=head2 lalala' %>
    <%= pod_to_html begin %>=head2 lalala<% end %>

Render POD to HTML.

=back

=head1 METHODS

L<Mojolicious::Plugin::PodRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
