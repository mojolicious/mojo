package Mojo::Loader;
use Mojo::Base -base;

use File::Basename 'fileparse';
use File::Spec::Functions qw(catdir catfile splitdir);
use Mojo::Exception;
use Mojo::Util qw(b64_decode class_to_path);

my %CACHE;

sub data {
  my ($self, $class, $data) = @_;
  return $class ? $data ? _all($class)->{$data} : _all($class) : undef;
}

sub load {
  my ($self, $module) = @_;

  # Check module name
  return 1 if !$module || $module !~ /^\w(?:[\w:']*\w)?$/;

  # Load
  return undef if $module->can('new') || eval "require $module; 1";

  # Exists
  my $path = class_to_path $module;
  return 1 if $@ =~ /^Can't locate $path in \@INC/;

  # Real error
  return Mojo::Exception->new($@);
}

sub search {
  my ($self, $namespace) = @_;

  my (@modules, %found);
  for my $directory (@INC) {
    next unless -d (my $path = catdir $directory, split(/::|'/, $namespace));

    # List "*.pm" files in directory
    opendir(my $dir, $path);
    for my $file (grep /\.pm$/, readdir $dir) {
      next if -d catfile splitdir($path), $file;
      my $class = "${namespace}::" . fileparse $file, qr/\.pm/;
      push @modules, $class unless $found{$class}++;
    }
  }

  return \@modules;
}

sub _all {
  my $class = shift;

  # Refresh or use cached data
  my $handle = do { no strict 'refs'; \*{"${class}::DATA"} };
  return $CACHE{$class} || {} unless fileno $handle;
  seek $handle, 0, 0;
  my $content = join '', <$handle>;
  close $handle;

  # Ignore everything before __DATA__ (Windows will seek to start of file)
  $content =~ s/^.*\n__DATA__\r?\n/\n/s;

  # Ignore everything after __END__
  $content =~ s/\n__END__\r?\n.*$/\n/s;

  # Split files
  my @data = split /^@@\s*(.+?)\s*\r?\n/m, $content;
  shift @data;

  # Find data
  my $all = $CACHE{$class} = {};
  while (@data) {
    my ($name, $content) = splice @data, 0, 2;
    $content = b64_decode $content if $name =~ s/\s*\(\s*base64\s*\)$//;
    $all->{$name} = $content;
  }

  return $all;
}

1;

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

Extract embedded file from the C<DATA> section of a class.

  say for keys %{$loader->data('Foo::Bar')};

=head2 load

  my $e = $loader->load('Foo::Bar');

Load a class and catch exceptions. Note that classes are checked for a C<new>
method to see if they are already loaded.

  if (my $e = $loader->load('Foo::Bar')) {
    die ref $e ? "Exception: $e" : 'Already loaded!';
  }

=head2 search

  my $modules = $loader->search('MyApp::Namespace');

Search for modules in a namespace non-recursively.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
