package Mojo::Loader;
use Mojo::Base -strict;

use Exporter 'import';
use File::Basename 'fileparse';
use File::Spec::Functions qw(catdir catfile splitdir);
use Mojo::Exception;
use Mojo::Util qw(b64_decode class_to_path);

our @EXPORT_OK
  = qw(data_section file_is_binary find_modules find_packages load_class);

my (%BIN, %CACHE);

sub data_section { $_[0] ? $_[1] ? _all($_[0])->{$_[1]} : _all($_[0]) : undef }

sub file_is_binary { keys %{_all($_[0])} ? !!$BIN{$_[0]}{$_[1]} : undef }

sub find_modules {
  my $ns = shift;

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

  return sort keys %modules;
}

sub find_packages {
  my $ns = shift;
  no strict 'refs';
  return sort map { /^(.+)::$/ ? "${ns}::$1" : () } keys %{"${ns}::"};
}

sub load_class {
  my $class = shift;

  # Invalid class name
  return 1 if ($class || '') !~ /^\w(?:[\w:']*\w)?$/;

  # Already loaded
  return undef if $class->can('new');

  # Success
  eval "require $class; 1" ? return undef : Mojo::Util::_teardown($class);

  # Does not exist
  return 1 if $@ =~ /^Can't locate \Q@{[class_to_path $class]}\E in \@INC/;

  # Real error
  return Mojo::Exception->new($@)->inspect;
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
      && ++$BIN{$class}{$name} ? b64_decode $data : $data;
  }

  return $all;
}

1;

=encoding utf8

=head1 NAME

Mojo::Loader - Load all kinds of things

=head1 SYNOPSIS

  use Mojo::Loader qw(data_section find_modules load_class);

  # Find modules in a namespace
  for my $module (find_modules 'Some::Namespace') {

    # Load them safely
    my $e = load_class $module;
    warn qq{Loading "$module" failed: $e} and next if ref $e;

    # And extract files from the DATA section
    say data_section($module, 'some_file.txt');
  }

=head1 DESCRIPTION

L<Mojo::Loader> is a class loader and plugin framework. Aside from finding
modules and loading classes, it allows multiple files to be stored in the
C<DATA> section of a class, which can then be accessed individually.

  package Foo;

  1;
  __DATA__

  @@ test.txt
  This is the first file.

  @@ test2.html (base64)
  VGhpcyBpcyB0aGUgc2Vjb25kIGZpbGUu

  @@ test
  This is the
  third file.

Each file has a header starting with C<@@>, followed by the file name and
optional instructions for decoding its content. Currently only the Base64
encoding is supported, which can be quite convenient for the storage of binary
data.

=head1 FUNCTIONS

L<Mojo::Loader> implements the following functions, which can be imported
individually.

=head2 data_section

  my $all   = data_section 'Foo::Bar';
  my $index = data_section 'Foo::Bar', 'index.html';

Extract embedded file from the C<DATA> section of a class, all files will be
cached once they have been accessed for the first time.

  # List embedded files
  say for keys %{data_section 'Foo::Bar'};

=head2 file_is_binary

  my $bool = file_is_binary 'Foo::Bar', 'test.png';

Check if embedded file from the C<DATA> section of a class was Base64 encoded.

=head2 find_packages

  my @pkgs = find_packages 'MyApp::Namespace';

Search for packages in a namespace non-recursively.

=head2 find_modules

  my @modules = find_modules 'MyApp::Namespace';

Search for modules in a namespace non-recursively.

=head2 load_class

  my $e = load_class 'Foo::Bar';

Load a class and catch exceptions, returns a false value if loading was
successful, a true value if the class has already been loaded, or a
L<Mojo::Exception> object if loading failed. Note that classes are checked for a
C<new> method to see if they are already loaded.

  # Handle exceptions
  if (my $e = load_class 'Foo::Bar') {
    die ref $e ? "Exception: $e" : 'Not found!';
  }

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
