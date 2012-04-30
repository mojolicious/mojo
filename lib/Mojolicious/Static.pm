package Mojolicious::Static;
use Mojo::Base -base;

use File::Spec::Functions 'catfile';
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Command;
use Mojo::Content::Single;
use Mojo::Home;
use Mojo::Path;

has classes => sub { ['main'] };
has paths   => sub { [] };

# DEPRECATED in Leaf Fluttering In Wind!
sub default_static_class {
  warn <<EOF;
Mojolicious::Static->default_static_class is DEPRECATED in favor of
Mojolicious::Static->classes!
EOF
  my $self = shift;
  return $self->classes->[0] unless @_;
  $self->classes->[0] = shift;
  return $self;
}

# "Valentine's Day's coming? Aw crap! I forgot to get a girlfriend again!"
sub dispatch {
  my ($self, $c) = @_;

  # Already rendered
  return if $c->res->code;

  # Canonical path
  my $stash = $c->stash;
  my $path  = $stash->{path}
    || $c->req->url->path->clone->canonicalize->to_string;

  # Split parts
  my @parts = @{Mojo::Path->new->parse($path)->parts};
  return unless @parts;

  # Prevent directory traversal
  return if $parts[0] eq '..';

  # Serve static file
  return unless $self->serve($c, join('/', @parts));
  $stash->{'mojo.static'}++;
  return $c->rendered;
}

# DEPRECATED in Leaf Fluttering In Wind!
sub root {
  warn <<EOF;
Mojolicious::Static->root is DEPRECATED in favor of
Mojolicious::Static->paths!
EOF
  my $self = shift;
  return $self->paths->[0] unless @_;
  $self->paths->[0] = shift;
  return $self;
}

sub serve {
  my ($self, $c, $rel) = @_;

  # Search all paths
  my $asset;
  my $size     = 0;
  my $modified = $self->{modified} ||= time;
  my $res      = $c->res;
  for my $path (@{$self->paths}) {
    next unless my $data = $self->_get_file(catfile $path, split('/', $rel));

    # Exists
    last if ($asset, $size, $modified) = @$data;

    # Forbidded
    $c->app->log->debug(qq/File "$rel" is forbidden./);
    $res->code(403) and return;
  }

  # Search DATA
  if (!$asset && defined(my $data = $self->_get_data_file($c, $rel))) {
    $size  = length $data;
    $asset = Mojo::Asset::Memory->new->add_chunk($data);
  }

  # Search bundled files
  elsif (!$asset) {
    my $b = $self->{bundled} ||= Mojo::Home->new(Mojo::Home->mojo_lib_dir)
      ->rel_dir('Mojolicious/public');
    my $data = $self->_get_file(catfile($b, split('/', $rel)));
    ($asset, $size, $modified) = @$data if $data && @$data;
  }

  # Not a static file
  return unless $asset;

  # If modified since
  my $req_headers = $c->req->headers;
  my $res_headers = $res->headers;
  if (my $date = $req_headers->if_modified_since) {

    # Not modified
    my $since = Mojo::Date->new($date)->epoch;
    if (defined $since && $since == $modified) {
      $res_headers->remove('Content-Type')->remove('Content-Length')
        ->remove('Content-Disposition');
      return $res->code(304);
    }
  }

  # Range
  my $start = 0;
  my $end = $size - 1 >= 0 ? $size - 1 : 0;
  if (my $range = $req_headers->range) {
    if ($range =~ m/^bytes=(\d+)\-(\d+)?/ && $1 <= $end) {
      $start = $1;
      $end = $2 if defined $2 && $2 <= $end;
      $res->code(206);
      $res_headers->content_length($end - $start + 1);
      $res_headers->content_range("bytes $start-$end/$size");
    }

    # Not satisfiable
    else { return $res->code(416) }
  }
  $asset->start_range($start)->end_range($end);

  # Serve file
  $res->code(200) unless $res->code;
  $res->content->asset($asset);
  $rel =~ /\.(\w+)$/;
  return $res_headers->content_type($c->app->types->type($1) || 'text/plain')
    ->accept_ranges('bytes')->last_modified(Mojo::Date->new($modified));
}

# "I like being a women.
#  Now when I say something stupid, everyone laughs and buys me things."
sub _get_data_file {
  my ($self, $c, $rel) = @_;

  # Protect templates
  return if $rel =~ /\.\w+\.\w+$/;

  # Index DATA files
  unless ($self->{index}) {
    my $index = $self->{index} = {};
    for my $class (reverse @{$self->classes}) {
      $index->{$_} = $class for keys %{Mojo::Command->get_all_data($class)};
    }
  }

  # Find file
  return Mojo::Command->get_data($rel, $self->{index}{$rel});
}

sub _get_file {
  my ($self, $path, $rel) = @_;
  no warnings 'newline';
  return unless -f $path;
  return [] unless -r $path;
  return [Mojo::Asset::File->new(path => $path), (stat $path)[7, 9]];
}

1;

=head1 NAME

Mojolicious::Static - Serve static files

=head1 SYNOPSIS

  use Mojolicious::Static;

  my $static = Mojolicious::Static->new;

=head1 DESCRIPTION

L<Mojolicious::Static> is a dispatcher for static files with C<Range> and
C<If-Modified-Since> support.

=head1 ATTRIBUTES

L<Mojolicious::Static> implements the following attributes.

=head2 C<classes>

  my $classes = $static->classes;
  $static     = $static->classes(['main']);

Classes to use for finding files in C<DATA> sections, first one has the
highest precedence, defaults to C<main>.

  # Add another class with static files in DATA section
  push @{$static->classes}, 'Mojolicious::Plugin::Fun';

=head2 C<paths>

  my $paths = $static->paths;
  $static   = $static->paths(['/home/sri/public']);

Directories to serve static files from, first one has the highest precedence.

  # Add another "public" directory
  push @{$static->paths}, '/home/sri/public';

=head1 METHODS

L<Mojolicious::Static> inherits all methods from L<Mojo::Base> and implements
the following ones.

=head2 C<dispatch>

  my $success = $static->dispatch(Mojolicious::Controller->new);

Serve static file for L<Mojolicious::Controller> object.

=head2 C<serve>

  my $success = $static->serve(Mojolicious::Controller->new, 'foo/bar.html');

Serve a specific file, relative to C<paths> or from C<classes>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
