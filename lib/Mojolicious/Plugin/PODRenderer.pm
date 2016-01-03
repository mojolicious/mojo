package Mojolicious::Plugin::PODRenderer;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Asset::File;
use Mojo::ByteStream;
use Mojo::DOM;
use Mojo::URL;
use Mojo::Util 'slurp';
use Pod::Simple::XHTML;
use Pod::Simple::Search;

sub register {
  my ($self, $app, $conf) = @_;

  my $preprocess = $conf->{preprocess} || 'ep';
  $app->renderer->add_handler(
    $conf->{name} || 'pod' => sub {
      my ($renderer, $c, $output, $options) = @_;
      $renderer->handlers->{$preprocess}($renderer, $c, $output, $options);
      $$output = _pod_to_html($$output) if defined $$output;
    }
  );

  $app->helper(
    pod_to_html => sub { shift; Mojo::ByteStream->new(_pod_to_html(@_)) });

  # Perldoc browser
  return undef if $conf->{no_perldoc};
  my $defaults = {module => 'Mojolicious/Guides', format => 'html'};
  return $app->routes->any(
    '/perldoc/:module' => $defaults => [module => qr/[^.]+/] => \&_perldoc);
}

sub _indentation {
  (sort map {/^(\s+)/} @{shift()})[0];
}

sub _html {
  my ($c, $src) = @_;

  # Rewrite links
  my $dom     = Mojo::DOM->new(_pod_to_html($src));
  my $perldoc = $c->url_for('/perldoc/');
  $_->{href} =~ s!^https://metacpan\.org/pod/!$perldoc!
    and $_->{href} =~ s!::!/!gi
    for $dom->find('a[href]')->map('attr')->each;

  # Rewrite code blocks for syntax highlighting and correct indentation
  for my $e ($dom->find('pre > code')->each) {
    my $str = $e->content;
    next if $str =~ /^\s*(?:\$|Usage:)\s+/m || $str !~ /[\$\@\%]\w|-&gt;\w/m;
    my $attrs = $e->attr;
    my $class = $attrs->{class};
    $attrs->{class} = defined $class ? "$class prettyprint" : 'prettyprint';
  }

  # Rewrite headers
  my $toc = Mojo::URL->new->fragment('toc');
  my @parts;
  for my $e ($dom->find('h1, h2, h3, h4')->each) {

    push @parts, [] if $e->tag eq 'h1' || !@parts;
    my $link = Mojo::URL->new->fragment($e->{id});
    push @{$parts[-1]}, my $text = $e->all_text, $link;
    my $permalink = $c->link_to('#' => $link, class => 'permalink');
    $e->content($permalink . $c->link_to($text => $toc));
  }

  # Try to find a title
  my $title = 'Perldoc';
  $dom->find('h1 + p')->first(sub { $title = shift->text });

  # Combine everything to a proper response
  $c->content_for(perldoc => "$dom");
  $c->render('mojo/perldoc', title => $title, parts => \@parts);
}

sub _perldoc {
  my $c = shift;

  # Find module or redirect to CPAN
  my $module = join '::', split('/', $c->param('module'));
  my $path
    = Pod::Simple::Search->new->find($module, map { $_, "$_/pods" } @INC);
  return $c->redirect_to("https://metacpan.org/pod/$module")
    unless $path && -r $path;

  my $src = slurp $path;
  $c->respond_to(txt => {data => $src}, html => sub { _html($c, $src) });
}

sub _pod_to_html {
  return '' unless defined(my $pod = ref $_[0] eq 'CODE' ? shift->() : shift);

  my $parser = Pod::Simple::XHTML->new;
  $parser->perldoc_url_prefix('https://metacpan.org/pod/');
  $parser->$_('') for qw(html_header html_footer);
  $parser->strip_verbatim_indent(\&_indentation);
  $parser->output_string(\(my $output));
  return $@ unless eval { $parser->parse_string_document("$pod"); 1 };

  return $output;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::PODRenderer - POD renderer plugin

=head1 SYNOPSIS

  # Mojolicious (with documentation browser under "/perldoc")
  my $route = $app->plugin('PODRenderer');
  my $route = $app->plugin(PODRenderer => {name => 'foo'});
  my $route = $app->plugin(PODRenderer => {preprocess => 'epl'});

  # Mojolicious::Lite (with documentation browser under "/perldoc")
  my $route = plugin 'PODRenderer';
  my $route = plugin PODRenderer => {name => 'foo'};
  my $route = plugin PODRenderer => {preprocess => 'epl'};

  # Without documentation browser
  plugin PODRenderer => {no_perldoc => 1};

  # foo.html.ep
  %= pod_to_html "=head1 TEST\n\nC<123>"

  # foo.html.pod
  =head1 <%= uc 'test' %>

=head1 DESCRIPTION

L<Mojolicious::Plugin::PODRenderer> is a renderer for true Perl hackers, rawr!

The code of this plugin is a good example for learning to build new plugins,
you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available
by default.

=head1 OPTIONS

L<Mojolicious::Plugin::PODRenderer> supports the following options.

=head2 name

  # Mojolicious::Lite
  plugin PODRenderer => {name => 'foo'};

Handler name, defaults to C<pod>.

=head2 no_perldoc

  # Mojolicious::Lite
  plugin PODRenderer => {no_perldoc => 1};

Disable L<Mojolicious::Guides> documentation browser that will otherwise be
available under C</perldoc>.

=head2 preprocess

  # Mojolicious::Lite
  plugin PODRenderer => {preprocess => 'epl'};

Name of handler used to preprocess POD, defaults to C<ep>.

=head1 HELPERS

L<Mojolicious::Plugin::PODRenderer> implements the following helpers.

=head2 pod_to_html

  %= pod_to_html '=head2 lalala'
  <%= pod_to_html begin %>=head2 lalala<% end %>

Render POD to HTML without preprocessing.

=head1 METHODS

L<Mojolicious::Plugin::PODRenderer> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  my $route = $plugin->register(Mojolicious->new);
  my $route = $plugin->register(Mojolicious->new, {name => 'foo'});

Register renderer and helper in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
