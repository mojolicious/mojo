package Mojolicious::Plugin::PodRenderer;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::ByteStream 'b';

# Core module since Perl 5.9.3, so it might not always be present
BEGIN {
    die <<'EOF' unless eval { require Pod::Simple::HTML; 1 } }
Module "Pod::Simple::HTML" not present in this version of Perl.
Please install it manually or upgrade Perl to at least version 5.10.
EOF

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
            $$output = $self->_pod_to_html($$output)
              if $r->handler->{$preprocess}->($r, $c, $output, $options);
        }
    );

    # Add "pod_to_html" helper
    $app->helper(pod_to_html => sub { shift; b($self->_pod_to_html(@_)) });
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
    eval { $parser->parse_string_document("=pod\n\n$pod") };
    return $@ if $@;

    # Filter
    $output =~ s/<a name='___top' class='dummyTopAnchor'\s*?><\/a>\n//g;
    $output =~ s/<a class='u'.*?name=".*?"\s*>(.*?)<\/a>/$1/sg;

    return $output;
}

1;
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
