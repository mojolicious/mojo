package Mojolicious::Plugin::I18n;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use I18N::LangTags;
use I18N::LangTags::Detect;

# Can we have Bender burgers again?
# No, the cat shelter’s onto me.
sub register {
    my ($self, $app, $conf) = @_;

    # Config
    $conf ||= {};

    # Namespace
    my $namespace = $conf->{namespace} || ((ref $app) . "::I18N");

    # Default
    my $default = $conf->{default} || 'en';

    # Initialize
    eval "package $namespace; use base 'Locale::Maketext'; 1;";
    eval "package ${namespace}::$default; use base '$namespace';"
      . 'our %Lexicon = (_AUTO => 1); 1;';
    die qq/Couldn't initialize I18N class "$namespace": $@/ if $@;

    # Start timer
    $app->hook(
        before_dispatch => sub {
            my $self = shift;

            # Header detection
            my @languages = I18N::LangTags::implicate_supers(
                I18N::LangTags::Detect->http_accept_langs(
                    $self->req->headers->accept_language
                )
            );

            # Handler
            $self->stash->{i18n} =
              Mojolicious::Plugin::I18n::_Handler->new(
                _namespace => $namespace);

            # Languages
            $self->stash->{i18n}->languages(@languages, $default);
        }
    );

    # Add "languages" helper
    $app->helper(languages => sub { shift->stash->{i18n}->languages(@_) });

    # Add "l" helper
    $app->helper(l => sub { shift->stash->{i18n}->localize(@_) });
}

# Container
package Mojolicious::Plugin::I18n::_Handler;

use base 'Mojo::Base';

sub languages {
    my ($self, @languages) = @_;

    # Shortcut
    return $self->{_language} unless @languages;

    # Namespace
    my $namespace = $self->{_namespace};

    # Handle
    if (my $handle = $namespace->get_handle(@languages)) {
        $handle->fail_with(sub { $_[1] });
        $self->{_handle}   = $handle;
        $self->{_language} = $handle->language_tag;
    }

    return $self;
}

sub localize {
    my $self = shift;
    my $key  = shift;

    # Localize
    return $key unless my $handle = $self->{_handle};
    return $handle->maketext($key, @_);
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::I18n - Intenationalization Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('i18n');
    % languages 'de';
    <%=l 'hello' %>

    # Mojolicious::Lite
    plugin 'i18n' => {namespace => 'MyApp::I18N'};
    <%=l 'hello' %>

    # Lexicon
    package MyApp::I18N::de;
    use base 'MyApp::I18N';

    our %Lexicon = (hello => 'hallo');

    1;

=head1 DESCRIPTION

L<Mojolicous::Plugin::I18n> adds L<Locale::Maketext> support to
L<Mojolicious>.
All you have to do besides using this plugin is to add as many lexicon
classes as you need.
Languages can usually be detected automatically from the C<Accept-Languages>
request header.

=head2 Options

=over 4

=item default

    # Mojolicious::Lite
    plugin i18n => {default => 'en'};

=item namespace

    # Mojolicious::Lite
    plugin i18n => {namespace => 'MyApp::I18N'};

=back

=head2 Helpers

=over 4

=item l

    <%=l 'hello' %>

Translate sentence.

=item languages

    <% languages 'de'; %>

Change languages.

=back

=head1 METHODS

L<Mojolicious::Plugin::I18n> inherits all methods from L<Mojolicious::Plugin>
and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register plugin hooks and helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
