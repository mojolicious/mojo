package Mojolicious::Static;
use Mojo::Base -base;

use File::Spec;
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Command;
use Mojo::Content::Single;
use Mojo::Home;
use Mojo::Path;

has [qw/default_static_class root/];

# "Valentine's Day's coming? Aw crap! I forgot to get a girlfriend again!"
sub dispatch {
  my ($self, $c) = @_;

  # Already rendered
  return 1 if $c->res->code;

  # Canonical path
  my $stash = $c->stash;
  my $path  = $stash->{path};
  $path = $c->req->url->path->clone->canonicalize->to_string
    unless defined $path;

  # Split parts
  my @parts = @{Mojo::Path->new->parse($path)->parts};
  return unless @parts;

  # Prevent directory traversal
  return if $parts[0] eq '..';

  # Serve static file
  if ($self->serve($c, join('/', @parts))) {
    $stash->{'mojo.static'} = 1;
    $c->rendered;
    return 1;
  }

  return 1;
}

sub serve {
  my ($self, $c, $rel, $root) = @_;

  # Append path to root
  $root = $self->root unless defined $root;
  my $path = File::Spec->catfile($root, split('/', $rel));

  # Extension
  $path =~ /\.(\w+)$/;
  my $ext = $1;

  # Root for bundled files
  $self->{bundled} ||= Mojo::Home->new(Mojo::Home->mojo_lib_dir)
    ->rel_dir('Mojolicious/public');

  # Normal file
  my $asset;
  my $modified = $self->{modified} ||= time;
  my $size     = 0;
  my $res      = $c->res;
  if (my $file = $self->_get_file($path)) {
    if (@$file) { ($asset, $size, $modified) = @$file }

    # Exists but is forbidden
    else {
      $c->app->log->debug(qq/File "$rel" is forbidden./);
      $res->code(403) and return;
    }
  }

  # DATA file
  elsif (!$asset && defined(my $data = $self->_get_data_file($c, $rel))) {
    $size  = length $data;
    $asset = Mojo::Asset::Memory->new->add_chunk($data);
  }

  # Bundled file
  else {
    $path = File::Spec->catfile($self->{bundled}, split('/', $rel));
    if (my $bundled = $self->_get_file($path)) {
      ($asset, $size, $modified) = @$bundled if @$bundled;
    }
  }

  # Found
  if ($asset) {

    # If modified since
    my $rqh = $c->req->headers;
    my $rsh = $res->headers;
    if (my $date = $rqh->if_modified_since) {

      # Not modified
      my $since = Mojo::Date->new($date)->epoch;
      if (defined $since && $since == $modified) {
        $res->code(304);
        $rsh->remove('Content-Type');
        $rsh->remove('Content-Length');
        $rsh->remove('Content-Disposition');
        return 1;
      }
    }

    # Range
    my $start = 0;
    my $end = $size - 1 >= 0 ? $size - 1 : 0;
    if (my $range = $rqh->range) {
      if ($range =~ m/^bytes=(\d+)\-(\d+)?/ && $1 <= $end) {
        $start = $1;
        $end = $2 if defined $2 && $2 <= $end;
        $res->code(206);
        $rsh->content_length($end - $start + 1);
        $rsh->content_range("bytes $start-$end/$size");
      }
      else {

        # Not satisfiable
        $res->code(416);
        return 1;
      }
    }
    $asset->start_range($start);
    $asset->end_range($end);

    # Prepare response
    $res->code(200) unless $res->code;
    $res->content->asset($asset);
    $rsh->content_type($c->app->types->type($ext) || 'text/plain');
    $rsh->accept_ranges('bytes');
    $rsh->last_modified(Mojo::Date->new($modified));
    return 1;
  }

  return;
}

sub _get_data_file {
  my ($self, $c, $rel) = @_;

  # Protect templates
  return if $rel =~ /\.\w+\.\w+$/;

  # Detect DATA class
  my $class =
       $c->stash->{static_class}
    || $ENV{MOJO_STATIC_CLASS}
    || $self->default_static_class
    || 'main';

  # Find DATA file
  my $data = $self->{data_files}->{$class}
    ||= [keys %{Mojo::Command->new->get_all_data($class) || {}}];
  for my $path (@$data) {
    return Mojo::Command->new->get_data($path, $class) if $path eq $rel;
  }

  return;
}

sub _get_file {
  my ($self, $path, $rel) = @_;
  return unless -f $path;
  return [] unless -r $path;
  return [Mojo::Asset::File->new(path => $path), (stat $path)[7, 9]];
}

1;
__END__

=head1 NAME

Mojolicious::Static - Serve Static Files

=head1 SYNOPSIS

  use Mojolicious::Static;

=head1 DESCRIPTION

L<Mojolicious::Static> is a dispatcher for static files with C<Range> and
C<If-Modified-Since> support.

=head1 ATTRIBUTES

L<Mojolicious::Static> implements the following attributes.

=head2 C<default_static_class>

  my $class = $static->default_static_class;
  $static   = $static->default_static_class('main');

The dispatcher will use this class to look for files in the C<DATA> section.

=head2 C<root>

  my $root = $static->root;
  $static  = $static->root('/foo/bar/files');

Directory to serve static files from.

=head1 METHODS

L<Mojolicious::Static> inherits all methods from L<Mojo::Base>
and implements the following ones.

=head2 C<dispatch>

  my $success = $static->dispatch($c);

Dispatch a L<Mojolicious::Controller> object.

=head2 C<serve>

  my $success = $static->serve($c, 'foo/bar.html');

Serve a specific file.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
