package Mojolicious::Static;
use Mojo::Base -base;

use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Date;
use Mojo::File   qw(curfile path);
use Mojo::Loader qw(data_section file_is_binary);
use Mojo::Util   qw(encode md5_sum trim);

# Bundled files
my $PUBLIC = curfile->sibling('resources', 'public');
my %EXTRA  = $PUBLIC->list_tree->map(sub { join('/', @{$_->to_rel($PUBLIC)}), $_->realpath->to_string })->each;

has asset_dir => 'assets';
has classes   => sub { ['main'] };
has extra     => sub { +{%EXTRA} };
has paths     => sub { [] };
has 'prefix';

sub asset_path {
  my ($self, $asset) = @_;
  $asset = "/$asset" unless $asset =~ /^\//;
  my $assets = $self->{assets} //= {};
  return $self->file_path('/' . $self->asset_dir . ($assets->{$asset} // $asset));
}

sub dispatch {
  my ($self, $c) = @_;

  # Method (GET or HEAD)
  my $req    = $c->req;
  my $method = $req->method;
  return undef unless $method eq 'GET' || $method eq 'HEAD';

  # Canonical path
  my $stash = $c->stash;
  my $path  = $req->url->path;
  $path = $stash->{path} ? $path->new($stash->{path}) : $path->clone;
  return undef unless my @parts = @{$path->canonicalize->parts};

  # Serve static file and prevent path traversal
  my $canon_path = join '/', @parts;
  return undef if $canon_path =~ /^\.\.\/|\\/ || !$self->serve($c, $canon_path);
  $stash->{'mojo.static'} = 1;

  # Development assets will be rebuilt a lot, do not let browsers cache them
  $c->res->headers->cache_control('no-cache')
    if $c->app->mode eq 'development' && index($canon_path, $self->asset_dir) == 0;

  return !!$c->rendered;
}

sub file {
  my ($self, $rel) = @_;

  $self->warmup unless $self->{index};

  # Search all paths
  my @parts = split /\//, $rel;
  for my $path (@{$self->paths}) {
    next unless my $asset = _get_file(path($path, @parts)->to_string);
    return $asset;
  }

  # Search DATA
  if (my $asset = $self->_get_data_file($rel)) { return $asset }

  # Search extra files
  my $extra = $self->extra;
  return exists $extra->{$rel} ? _get_file($extra->{$rel}) : undef;
}

sub file_path {
  my ($self, $file) = @_;
  $file = "/$file" unless $file =~ /^\//;
  return $file unless my $prefix = $self->prefix;
  return "$prefix$file";
}

sub is_fresh {
  my ($self, $c, $options) = @_;

  my $res_headers = $c->res->headers;
  my ($last, $etag) = @$options{qw(last_modified etag)};
  $res_headers->last_modified(Mojo::Date->new($last)->to_string)       if $last;
  $res_headers->etag($etag = ($etag =~ m!^W/"! ? $etag : qq{"$etag"})) if $etag;

  # Unconditional
  my $req_headers = $c->req->headers;
  my $match       = $req_headers->if_none_match;
  return undef unless (my $since = $req_headers->if_modified_since) || $match;

  # If-None-Match
  $etag //= $res_headers->etag // '';
  return undef if $match && !grep { $_ eq $etag || "W/$_" eq $etag } map { trim($_) } split /,/, $match;

  # If-Modified-Since
  return !!$match unless ($last //= $res_headers->last_modified) && $since;
  return _epoch($last) <= (_epoch($since) // 0);
}

sub serve {
  my ($self, $c, $rel) = @_;

  # Prefix
  if (my $prefix = $self->prefix) {
    $rel = "/$rel";
    return undef unless $rel =~ s/^\Q$prefix\E\///;
  }

  return undef unless my $asset = $self->file($rel);
  $c->app->types->content_type($c, {file => $rel});
  return !!$self->serve_asset($c, $asset);
}

sub serve_asset {
  my ($self, $c, $asset) = @_;

  # Content-Type
  $c->app->types->content_type($c, {file => $asset->path}) if $asset->is_file;

  # Last-Modified and ETag
  my $res = $c->res;
  $res->code(200)->headers->accept_ranges('bytes');
  my $mtime   = $asset->mtime;
  my $options = {etag => md5_sum($mtime), last_modified => $mtime};
  return $res->code(304) if $self->is_fresh($c, $options);

  # Range
  return $res->content->asset($asset) unless my $range = $c->req->headers->range;

  # Not satisfiable
  return $res->code(416) unless my $size = $asset->size;
  return $res->code(416) unless $range =~ /^bytes=(\d+)?-(\d+)?/;
  my ($start, $end) = ($1 // 0, defined $2 && $2 < $size ? $2 : $size - 1);
  return $res->code(416) if $start > $end;

  # Satisfiable
  $res->code(206)->headers->content_length($end - $start + 1)->content_range("bytes $start-$end/$size");
  return $res->content->asset($asset->start_range($start)->end_range($end));
}

sub warmup {
  my $self = shift;

  # DATA sections
  my $index = $self->{index} = {};
  for my $class (reverse @{$self->classes}) { $index->{$_} = $class for keys %{data_section $class} }

  # Static assets
  my $assets    = $self->{assets} = {};
  my $asset_dir = $self->asset_dir;
  for my $path (@{$self->paths}) {
    my $asset_path = path($path, $asset_dir);
    next unless -d $asset_path;

    for my $asset_file ($asset_path->list_tree({recursive => 1})->each) {
      my $parts    = $asset_file->to_rel($asset_path)->to_array;
      my $filename = pop @$parts;
      my $prefix   = join '/', @$parts;

      next unless $filename =~ /^([^.]+)\.([^.]+)\.(.+)$/;
      my $checksum = $2;
      my $short    = $prefix eq '' ? "/$1.$3" : "/$prefix/$1.$3";
      my $long     = '/' . join('/', @$parts, $filename);

      $assets->{$short} = $long if !exists($assets->{$short}) || $checksum eq 'development';
    }
  }
}

sub _epoch { Mojo::Date->new(shift)->epoch }

sub _get_data_file {
  my ($self, $rel) = @_;

  # Protect files without extensions and templates with two extensions
  return undef if $rel !~ /\.\w+$/ || $rel =~ /\.\w+\.\w+$/;

  # Find file
  my @args = ($self->{index}{$rel}, $rel);
  return undef unless defined(my $data = data_section(@args));
  return Mojo::Asset::Memory->new->add_chunk(file_is_binary(@args) ? $data : encode 'UTF-8', $data);
}

sub _get_file {
  my $path = shift;
  no warnings 'newline';
  return -f $path && -r _ ? Mojo::Asset::File->new(path => $path) : undef;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Static - Serve static files

=head1 SYNOPSIS

  use Mojolicious::Static;

  my $static = Mojolicious::Static->new;
  push @{$static->classes}, 'MyApp::Controller::Foo';
  push @{$static->paths}, '/home/sri/public';

=head1 DESCRIPTION

L<Mojolicious::Static> is a static file server with C<Range>, C<If-Modified-Since> and C<If-None-Match> support, based
on L<RFC 7232|https://tools.ietf.org/html/rfc7232> and L<RFC 7233|https://tools.ietf.org/html/rfc7233>.

=head1 ATTRIBUTES

L<Mojolicious::Static> implements the following attributes.

=head2 asset_dir

  my $dir = $static->asset_dir;
  $static = $static->asset_dir('assets');

Subdirectory used for all static assets, defaults to C<assets>.

=head2 classes

  my $classes = $static->classes;
  $static     = $static->classes(['main']);

Classes to use for finding files in C<DATA> sections with L<Mojo::Loader>, first one has the highest precedence,
defaults to C<main>. Only files with exactly one extension will be used, like C<index.html>. Note that for files to be
detected, these classes need to have already been loaded and added before L</"warmup"> is called, which usually happens
automatically during application startup.

  # Add another class with static files in DATA section
  push @{$static->classes}, 'Mojolicious::Plugin::Fun';

  # Add another class with static files in DATA section and higher precedence
  unshift @{$static->classes}, 'Mojolicious::Plugin::MoreFun';

=head2 extra

  my $extra = $static->extra;
  $static   = $static->extra({'foo/bar.txt' => '/home/sri/myapp/bar.txt'});

Paths for extra files to be served from locations other than L</"paths">, such as the images used by the built-in
exception and not found pages. Note that extra files are only served if no better alternative could be found in
L</"paths"> and L</"classes">.

  # Remove built-in favicon
  delete $static->extra->{'favicon.ico'};

=head2 paths

  my $paths = $static->paths;
  $static   = $static->paths(['/home/sri/public']);

Directories to serve static files from, first one has the highest precedence.

  # Add another "public" directory
  push @{$static->paths}, '/home/sri/public';

  # Add another "public" directory with higher precedence
  unshift @{$static->paths}, '/home/sri/themes/blue/public';

=head2 prefix

  my $prefix = $static->prefix;
  $static    = $static->prefix('/static');

Prefix to use for all static files, defaults to C<undef>. This can be very useful for production deployments where the
reverse proxy server should take over serving static files.

=head1 METHODS

L<Mojolicious::Static> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 asset_path

  my $path = $static->asset_path('/app.js');

Get static asset path.

=head2 dispatch

  my $bool = $static->dispatch(Mojolicious::Controller->new);

Serve static file for L<Mojolicious::Controller> object.

=head2 file

  my $asset = $static->file('images/logo.png');
  my $asset = $static->file('../lib/MyApp.pm');

Build L<Mojo::Asset::File> or L<Mojo::Asset::Memory> object for a file, relative to L</"paths"> or from L</"classes">,
or return C<undef> if it doesn't exist. Note that this method uses a relative path, but does not protect from
traversing to parent directories.

  my $content = $static->file('foo/bar.html')->slurp;

=head2 file_path

  my $path = $static->file_path('/index.html');

Get static file path with L</"prefix"> if it has been configured.

=head2 is_fresh

  my $bool = $static->is_fresh(Mojolicious::Controller->new, {etag => 'abc'});
  my $bool = $static->is_fresh(
    Mojolicious::Controller->new, {etag => 'W/"def"'});

Check freshness of request by comparing the C<If-None-Match> and C<If-Modified-Since> request headers to the C<ETag>
and C<Last-Modified> response headers.

These options are currently available:

=over 2

=item etag

  etag => 'abc'
  etag => 'W/"abc"'

Add C<ETag> header before comparing.

=item last_modified

  last_modified => $epoch

Add C<Last-Modified> header before comparing.

=back

=head2 serve

  my $bool = $static->serve(Mojolicious::Controller->new, 'images/logo.png');
  my $bool = $static->serve(Mojolicious::Controller->new, '../lib/MyApp.pm');

Serve a specific file, relative to L</"paths"> or from L</"classes">. Note that this method uses a relative path, but
does not protect from traversing to parent directories.

=head2 serve_asset

  $static->serve_asset(Mojolicious::Controller->new, Mojo::Asset::File->new);

Serve a L<Mojo::Asset::File> or L<Mojo::Asset::Memory> object with C<Range>, C<If-Modified-Since> and C<If-None-Match>
support.

=head2 warmup

  $static->warmup();

Prepare static files from L</"classes"> and static assets for future use.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
