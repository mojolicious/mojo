# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugin::I18n;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use I18N::LangTags;

# Core module since Perl 5.8.5
use constant DETECT => eval { require I18N::LangTags::Detect; 1 };

# Can we have Bender burgers again?
# No, the cat shelter’s onto me.
sub register {
    my ($self, $app, $conf) = @_;

    # Config
    $conf ||= {};

    # Namespace
    my $namespace = $conf->{namespace} || ((ref $app) . "::I18N");

    # Initialize
    eval "package $namespace; use base 'Locale::Maketext'; 1;";
    die qq/Couldn't initialize I18N class "$namespace": $@/ if $@;

    # Start timer
    $app->plugins->add_hook(
        before_dispatch => sub {
            my ($self, $c) = @_;

            # Languages
            my @languages = ('en');

            # Header detection
            @languages = I18N::LangTags::implicate_supers(
                I18N::LangTags::Detect->http_accept_langs(
                    scalar $c->req->headers->accept_language
                )
            ) if DETECT;

            # Handler
            $c->stash->{i18n} =
              Mojolicious::Plugin::I18n::_Handler->new(
                _namespace => $namespace);

            # Languages
            $c->stash->{i18n}->languages(@languages);
        }
    );

    # Add "languages" helper
    $app->renderer->add_helper(
        languages => sub { shift->stash->{i18n}->languages(@_) });

    # Add "l" helper
    $app->renderer->add_helper(l => sub { shift->stash->{i18n}->localize(@_) }
    );
}

# Container
package Mojolicious::Plugin::I18n::_Handler;

use base 'Mojo::Base';

__PACKAGE__->attr([qw/_handle _language _namespace/]);

sub languages {
    my ($self, @languages) = @_;

    # Shortcut
    return $self->_language unless @languages;

    # Namespace
    my $namespace = $self->_namespace;

    # Handle
    if (my $handle = $namespace->get_handle(@languages)) {
        $self->_handle($handle);
        $self->_language($handle->language_tag);
    }
    else { $self->_language('en') }

    return $self;
}

sub localize {
    my $self = shift;

    # Localize
    my $handle = $self->_handle;
    return $handle->maketext(@_) if $handle;

    # Pass through
    return join '', @_;
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

=head1 METHODS

L<Mojolicious::Plugin::I18n> inherits all methods from L<Mojolicious::Plugin>
and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register plugin hooks and helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
