package Mojo::Loader;
use Mojo::Base -base;

use File::Basename 'fileparse';
use File::Spec::Functions qw(catdir catfile splitdir);
use Mojo::Exception;
use Mojo::Util qw(b64_decode class_to_path);

my (%BIN, %CACHE);

sub data { $_[1] ? $_[2] ? _all($_[1])->{$_[2]} : _all($_[1]) : undef }

sub is_binary { keys %{_all($_[1])} ? !!$BIN{$_[1]}{$_[2]} : undef }

sub load {
  my ($self, $module) = @_;

  # Check module name
  return 1 if !$module || $module !~ /^\w(?:[\w:']*\w)?$/;

  # Load
  return undef if $module->can('new') || eval "require $module; 1";

  # Exists
  return 1 if $@ =~ /^Can't locate \Q@{[class_to_path $module]}\E in \@INC/;

  # Real error
  return Mojo::Exception->new($@);
}

sub search {
  my ($self, $ns) = @_;

  my %modules;
  for my $directory (@INC) {
    next unless -d (my $path = catdir $directory, split(/::|'/, $ns));

    # List "*.pm" files in directory
    opendir(my $dir, $path);
    for my $file (grep /\.pm$/, readdir $dir) {
      next if -d catfile splitdir($path), $file;
      $modules{"${ns}::" . fileparse $file, qr/\.pm/}++;
    }
  }

  return [keys %modules];
}

sub _all {
  my $class = shift;

  return $CACHE{$class} if $CACHE{$class};
  my $handle = do { no strict 'refs'; \*{"${class}::DATA"} };
  return {} unless fileno $handle;
  seek $handle, 0, 0;
  my $data = join '', <$handle>;

  # Ignore everything before __DATA__ (some versions seek to start of file)
  $data =~ s/^.*\n__DATA__\r?\n/\n/s;

  # Ignore everything after __END__
  $data =~ s/\n__END__\r?\n.*$/\n/s;

  # Split files
  (undef, my @files) = split /^@@\s*(.+?)\s*\r?\n/m, $data;

  # Find data
  my $all = $CACHE{$class} = {};
  while (@files) {
    my ($name, $data) = splice @files, 0, 2;
    $all->{$name} = $name =~ s/\s*\(\s*base64\s*\)$//
      && ++$BIN{$class}{$name} ? b64_decode($data) : $data;
  }

  return $all;
}

1;

=encoding utf8

=head1 NAME

Mojo::Loader - Loader

=head1 SYNOPSIS

  use Mojo::Loader;

  # Find modules in a namespace
  my $loader = Mojo::Loader->new;
  for my $module (@{$loader->search('Some::Namespace')}) {

    # Load them safely
    my $e = $loader->load($module);
    warn qq{Loading "$module" failed: $e} and next if ref $e;

    # And extract files from the DATA section
    say $loader->data($module, 'some_file.txt');
  }

=head1 DESCRIPTION

L<Mojo::Loader> is a class loader and plugin framework.

=head1 METHODS

L<Mojo::Loader> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 data

  my $all   = $loader->data('Foo::Bar');
  my $index = $loader->data('Foo::Bar', 'index.html');

Extract embedded file from the C<DATA> section of a class, all files will be
cached once they have been accessed for the first time.

  say for keys %{$loader->data('Foo::Bar')};

=head2 is_binary

  my $bool = $loader->is_binary('Foo::Bar', 'test.png');

Check if embedded file from the C<DATA> section of a class was Base64 encoded.

=head2 load

  my $e = $loader->load('Foo::Bar');

Load a class and catch exceptions. Note that classes are checked for a C<new>
method to see if they are already loaded.

  if (my $e = $loader->load('Foo::Bar')) {
    die ref $e ? "Exception: $e" : 'Not found!';
  }

=head2 search

  my $modules = $loader->search('MyApp::Namespace');

Search for modules in a namespace non-recursively.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
