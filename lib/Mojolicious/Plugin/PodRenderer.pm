package Mojolicious::Plugin::PodRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use File::Basename 'dirname';
use File::Spec;
use IO::File;
use Mojo::Asset::File;
use Mojo::ByteStream 'b';
use Mojo::DOM;
use Mojo::Util 'url_escape';

# Core module since Perl 5.9.3, so it might not always be present
BEGIN {
  die <<'EOF' unless eval { require Pod::Simple::HTML; 1 } }
Module "Pod::Simple" not present in this version of Perl.
Please install it manually or upgrade Perl to at least version 5.10.
EOF

use Pod::Simple::Search;

# Paths
our @PATHS = map { $_, "$_/pods" } @INC;

# Template directory
my $T = File::Spec->catdir(dirname(__FILE__), '..', 'templates');

# Mojobar template
our $MOJOBAR =
  Mojo::Asset::File->new(path => File::Spec->catfile($T, 'mojobar.html.ep'))
  ->slurp;

# Perldoc template
our $PERLDOC =
  Mojo::Asset::File->new(path => File::Spec->catfile($T, 'perldoc.html.ep'))
  ->slurp;

# "This is my first visit to the Galaxy of Terror and I'd like it to be a
#  pleasant one."
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
        if $r->handlers->{$preprocess}->($r, $c, $output, $options);
    }
  );

  # Add "pod_to_html" helper
  $app->helper(pod_to_html => sub { shift; b(_pod_to_html(@_)) });

  # Perldoc
  $app->routes->any(
    '/perldoc' => sub {
      my $self = shift;

      # Find module
      my $module = $self->req->url->query->params->[0]
        || 'Mojolicious::Guides';
      $module =~ s/\//\:\:/g;
      my $path = Pod::Simple::Search->new->find($module, @PATHS);

      # Redirect to CPAN
      my $cpan = 'http://search.cpan.org/perldoc';
      return $self->redirect_to("$cpan?$module")
        unless $path && -r $path;

      # Turn POD into HTML
      my $file = IO::File->new;
      $file->open("< $path");
      my $html = _pod_to_html(join '', <$file>);

      # Rewrite links
      my $dom = Mojo::DOM->new("$html");
      $dom->find('a[href]')->each(
        sub {
          my $attrs = shift->attrs;
          if ($attrs->{href} =~ /^$cpan/) {
            $attrs->{href} =~ s/^$cpan/perldoc/;
            $attrs->{href} =~ s/%3A%3A/\//gi;
          }
        }
      );

      # Rewrite code sections for syntax highlighting
      $dom->find('pre')->each(
        sub {
          my $attrs = shift->attrs;
          my $class = $attrs->{class};
          $attrs->{class} =
            defined $class ? "$class prettyprint" : 'prettyprint';
        }
      );

      # Rewrite headers
      my $url = $self->req->url->clone;
      $url =~ s/%2F/\//gi;
      my $sections = [];
      $dom->find('h1, h2, h3')->each(
        sub {
          my $tag    = shift;
          my $text   = $tag->all_text;
          my $anchor = $text;
          $anchor =~ s/\s+/_/g;
          url_escape $anchor, 'A-Za-z0-9_';
          $anchor =~ s/\%//g;
          push @$sections, [] if $tag->type eq 'h1' || !@$sections;
          push @{$sections->[-1]}, $text, "/$url#$anchor";
          $tag->replace_inner(
            $self->link_to(
              $text => "/$url#toc",
              class => 'mojoscroll',
              id    => $anchor
            )
          );
        }
      );

      # Try to find a title
      my $title = 'Perldoc';
      $dom->find('h1 + p')->until(sub { $title = shift->text });

      # Combine everything to a proper response
      $self->content_for(mojobar => $self->include(inline => $MOJOBAR));
      $self->content_for(perldoc => "$dom");
      $self->render(
        inline   => $PERLDOC,
        title    => $title,
        sections => $sections
      );
      $self->res->headers->content_type('text/html;charset="UTF-8"');
    }
  ) unless $conf->{no_perldoc};
}

sub _pod_to_html {
  my $pod = shift;
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

L<Mojolicious::Plugin::PodRenderer> is a renderer for true Perl hackers,
rawr!

=head1 OPTIONS

=head2 C<name>

  # Mojolicious::Lite
  plugin pod_renderer => {name => 'foo'};

Handler name.

=head2 C<no_perldoc>

  # Mojolicious::Lite
  plugin pod_renderer => {no_perldoc => 1};

Disable perldoc browser.
Note that this option is EXPERIMENTAL and might change without warning!

=head2 C<preprocess>

  # Mojolicious::Lite
  plugin pod_renderer => {preprocess => 'epl'};

Handler name of preprocessor.

=head1 HELPERS

=head2 C<pod_to_html>

  <%= pod_to_html '=head2 lalala' %>
  <%= pod_to_html begin %>=head2 lalala<% end %>

Render POD to HTML.

=head1 METHODS

L<Mojolicious::Plugin::PodRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register;

Register renderer in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
