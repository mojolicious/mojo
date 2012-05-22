package Mojolicious::Plugin::I18N;
use Mojo::Base 'Mojolicious::Plugin';

use I18N::LangTags;
use I18N::LangTags::Detect;
use Mojo::Loader;

# "Can we have Bender burgers again?
#  No, the cat shelter’s onto me."
sub register {
  my ($self, $app, $conf) = @_;

  # Initialize
  my $namespace = $conf->{namespace} || ((ref $app) . "::I18N");
  my $default   = $conf->{default}   || 'en';
  die qq{Couldn't initialize I18N class "$namespace": $@}
    unless eval "package $namespace; use base 'Locale::Maketext'; 1";
  my $dc = "${namespace}::$default";
  if (my $e = Mojo::Loader->load($dc)) {
    die qq{Couldn't load default lexicon class "$dc": $e} if ref $e;
    die qq{Couldn't initialize default lexicon class "$dc": $@}
      unless eval
        "package $dc; use base '$namespace'; our \%Lexicon = (_AUTO => 1);";
  }

  # Add hook
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
      $self->stash->{i18n}
        = Mojolicious::Plugin::I18N::_Handler->new(namespace => $namespace);

      # Languages
      $self->stash->{i18n}->languages(@languages, $default);
    }
  );

  # Add "languages" helper
  $app->helper(languages => sub { shift->stash->{i18n}->languages(@_) });

  # Add "l" helper
  $app->helper(l => sub { shift->stash->{i18n}->localize(@_) });
}

package Mojolicious::Plugin::I18N::_Handler;
use Mojo::Base -base;

# "Robot 1-X, save my friends! And Zoidberg!"
sub languages {
  my ($self, @languages) = @_;
  return $self->{language} unless @languages;

  # Handle
  my $namespace = $self->{namespace};
  if (my $handle = $namespace->get_handle(@languages)) {
    $handle->fail_with(sub { $_[1] });
    $self->{handle}   = $handle;
    $self->{language} = $handle->language_tag;
  }

  return $self;
}

sub localize {
  my ($self, $key) = (shift, shift);
  return $key unless my $handle = $self->{handle};
  return $handle->maketext($key, @_);
}

1;

=head1 NAME

Mojolicious::Plugin::I18N - Internationalization plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('I18N');
  % languages 'de';
  %=l 'hello'

  # Mojolicious::Lite
  plugin I18N => {namespace => 'MyApp::I18N'};
  %=l 'hello'

  # Lexicon
  package MyApp::I18N::de;
  use Mojo::Base 'MyApp::I18N';

  our %Lexicon = (hello => 'hallo');

  1;

=head1 DESCRIPTION

L<Mojolicious::Plugin::I18N> adds L<Locale::Maketext> support to
L<Mojolicious>. All you have to do besides using this plugin is to add as many
lexicon classes as you need. Languages can usually be detected automatically
from the C<Accept-Languages> request header. The code of this plugin is a good
example for learning to build new plugins, you're welcome to fork it.

This plugin can save a lot of typing, since it will generate the following
code by default.

  # $self->plugin('I18N');
  package MyApp::I18N;
  use base 'Locale::Maketext';
  package MyApp::I18N::en;
  use base 'MyApp::I18N';
  our %Lexicon = (_AUTO => 1);
  1;

Namespace and default language of generated code are affected by their
respective options. The default lexicon class will only be generated if it
doesn't already exist.

=head1 OPTIONS

L<Mojolicious::Plugin::I18N> supports the following options.

=head2 C<default>

  # Mojolicious::Lite
  plugin I18N => {default => 'en'};

Default language, defaults to C<en>.

=head2 C<namespace>

  # Mojolicious::Lite
  plugin I18N => {namespace => 'MyApp::I18N'};

Lexicon namespace, defaults to the application class followed by C<::I18N>.

=head1 HELPERS

L<Mojolicious::Plugin::I18N> implements the following helpers.

=head2 C<l>

  %=l 'hello'
  $self->l('hello');

Translate sentence.

=head2 C<languages>

  % languages 'de';
  $self->languages('de');

Change languages.

=head1 METHODS

L<Mojolicious::Plugin::I18N> inherits all methods from L<Mojolicious::Plugin>
and implements the following new ones.

=head2 C<register>

  $plugin->register($app, $conf);

Register plugin hooks and helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
