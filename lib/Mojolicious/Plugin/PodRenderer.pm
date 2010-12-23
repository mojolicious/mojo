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

# Paths
our @PATHS = map { $_, "$_/pods" } @INC;

# Mojobar template
our $MOJOBAR = Mojo::Command->new->get_data('mojobar.html.ep', __PACKAGE__);

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

    # Add "pod" handler
    $app->renderer->add_handler(
        $name => sub {
            my ($r, $c, $output, $options) = @_;

            # Preprocess with ep and then render
            $$output = _pod_to_html($$output)
              if $r->handler->{$preprocess}->($r, $c, $output, $options);
        }
    );

    # Add "pod_to_html" helper
    $app->helper(pod_to_html => sub { shift; b(_pod_to_html(@_)) });

    # Perldoc
    $app->routes->any(
        '/perldoc' => sub {
            my $self = shift;

            # Module
            my $module = $self->req->url->query->params->[0]
              || 'Mojolicious::Guides';
            $module =~ s/\//\:\:/g;

            # Path
            my $path = Pod::Simple::Search->new->find($module, @PATHS);

            # Redirect to CPAN
            my $cpan = 'http://search.cpan.org/perldoc';
            return $self->redirect_to("$cpan?$module")
              unless $path && -r $path;

            # POD
            my $file = IO::File->new;
            $file->open("< $path");
            my $html = _pod_to_html(join '', <$file>);
            my $dom = Mojo::DOM->new->parse("$html");
            $dom->find('a[href]')->each(
                sub {
                    my $attrs = shift->attrs;
                    if ($attrs->{href} =~ /^$cpan/) {
                        $attrs->{href} =~ s/^$cpan/perldoc/;
                        $attrs->{href} =~ s/%3A%3A/\//gi;
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
            my $url = $self->req->url->clone;
            $url =~ s/%2F/\//gi;
            $dom->find('h1, h2, h3')->each(
                sub {
                    my $tag    = shift;
                    my $text   = $tag->all_text;
                    my $anchor = $text;
                    $anchor =~ s/[^\w\-]/_/g;
                    $anchor =~ s/^_+//;
                    $anchor =~ s/_+$//;
                    $tag->replace_inner(
                        qq/<a href="$url#$anchor" name="$anchor">$text<\/a>/);
                }
            );

            # Title
            my $title = 'Perldoc';
            $dom->find('h1 + p')->until(sub { $title = shift->text });

            # Render
            $self->content_for(mojobar => $self->include(inline => $MOJOBAR));
            $self->content_for(perldoc => "$dom");
            $self->render(
                inline => $PERLDOC,
                title  => $title
            );
            $self->res->headers->content_type('text/html;charset="UTF-8"');
        }
    ) unless $conf->{no_perldoc};
}

sub _pod_to_html {
    my $pod = shift;

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

@@ mojobar.html.ep
% content_for header => begin
    %= javascript 'js/jquery.js'
    %= stylesheet begin
        #mojobar {
            background-color: #1a1a1a;
            background: -webkit-gradient(
                linear,
                0% 0%,
                0% 100%,
                color-stop(0%, #2a2a2a),
                color-stop(100%, #000)
            );
            background: -moz-linear-gradient(
                top,
                #2a2a2a 0%,
                #000 100%
            );
            background: linear-gradient(top, #2a2a2a 0%, #000 100%);
            -moz-box-shadow: 0px 2px 5px rgba(0, 0, 0, 0.6);
            -webkit-box-shadow: 0px 2px 5px rgba(0, 0, 0, 0.6);
            box-shadow: 0px 2px 5px rgba(0, 0, 0, 0.6);
            color: #eee;
            height: 60px;
            overflow: hidden;
            position: absolute;
            text-align: right;
            text-shadow: 0;
            vertical-align: middle;
            width: 100%;
            z-index: 1000;
        }
        #mojobar-logo {
            float: left;
            margin-left: 5em;
            padding-top: 2px;
        }
        #mojobar-links {
            display:table-cell;
            float: right;
            height: 60px;
            margin-right: 5em;
            margin-top: 1.5em;
        }
        #mojobar-links a {
            color: #ccc;
            font: 1.1em Georgia, Times, serif;
            margin-left: 0.5em;
            padding-bottom: 1em;
            padding-top: 1em;
            text-decoration: none;
            text-shadow: 0px -1px 0px #555;
        }
        #mojobar-links a:hover { color: #fff; }
    % end
% end
<div id="mojobar">
    <div id="mojobar-logo">
        %= link_to 'http://mojolicio.us' => begin
            <img src="mojolicious-white.png" alt="Mojolicious logo">
        % end
    </div>
    <div id="mojobar-links">
        %= link_to Documentation => 'http://mojolicio.us/perldoc'
        %= link_to Wiki => 'https://github.com/kraih/mojo/wiki'
        %= link_to GitHub => 'https://github.com/kraih/mojo'
        %= link_to CPAN => 'http://search.cpan.org/dist/Mojolicious'
        %= link_to MailingList => 'http://groups.google.com/group/mojolicious'
        %= link_to Blog => 'http://blog.kraih.com'
        %= link_to Twitter => 'http://twitter.com/kraih'
    </div>
</div>
%= javascript begin
    $(window).load(function () {
        var mojobar = $('#mojobar');
        var start = mojobar.offset().top;
        var fixed;
        $(window).scroll(function () {
            if (!fixed && (mojobar.offset().top - $(window).scrollTop() < 0)) {
                mojobar.css('top', 0);
                mojobar.css('position', 'fixed');
                fixed = true;
            } else if (fixed && $(window).scrollTop() <= start) {
                mojobar.css('position', 'absolute');
                mojobar.css('top', start + 'px');
                fixed = false;
            }
        });
    });
% end

@@ perldoc.html.ep
<!doctype html><html>
    <head>
        <title><%= $title %></title>
        %= base_tag
        %= stylesheet 'css/prettify-mojo.css'
        %= javascript 'js/prettify.js'
        %= content_for 'header'
        %= stylesheet begin
            a { color: inherit; }
            a img { border: 0; }
            body {
                background-color: #f5f6f8;
                color: #333;
                font: 0.9em Verdana, sans-serif;
                margin: 0;
                text-shadow: #ddd 0 1px 0;
            }
            h1, h2, h3 {
                font: 1.5em Georgia, Times, serif;
                margin: 0;
            }
            h1 a, h2 a, h3 a { text-decoration: none; }
            pre {
                background-color: #1a1a1a;
                background: url("mojolicious-pinstripe.gif") fixed;
                -moz-border-radius: 5px;
                border-radius: 5px;
                color: #eee;
                font-family: 'Menlo', 'Monaco', Courier, monospace !important;
                text-align: left;
                text-shadow: #333 0 1px 0;
                padding-bottom: 1.5em;
                padding-top: 1.5em;
                white-space: pre-wrap;
            }
            #footer {
                padding-top: 1em;
                text-align: center;
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
                margin-left: 5em;
                margin-right: 5em;
                padding: 3em;
                padding-top: 7em;
            }
        % end
    </head>
    <body onload="prettyPrint()">
        %= content_for 'mojobar'
        <div id="perldoc"><%= content_for 'perldoc' %></div>
        <div id="footer">
            %= link_to 'http://mojolicio.us' => begin
                <img src="mojolicious-black.png" alt="Mojolicious logo">
            % end
        </div>
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

=item no_perldoc

    # Mojolicious::Lite
    plugin pod_renderer => {no_perldoc => 1};

Note that this option is EXPERIMENTAL and might change without warning!

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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
