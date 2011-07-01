package Mojo::Loader;
use Mojo::Base -base;

# "Don't let Krusty's death get you down, boy.
#  People die all the time, just like that.
#  Why, you could wake up dead tomorrow! Well, good night."
use Carp 'carp';
use File::Basename;
use File::Spec;
use Mojo::Command;
use Mojo::Exception;

# "Homer no function beer well without."
sub load {
  my ($self, $module) = @_;

  # Check module name
  return 1 if !$module || $module !~ /^[\w\:\']+$/;

  # Already loaded
  return if $module->can('new');

  # Load
  unless (eval "require $module; 1") {

    # Exists
    my $path = Mojo::Command->class_to_path($module);
    return 1 if $@ =~ /^Can't locate $path in \@INC/;

    # Real error
    return Mojo::Exception->new($@);
  }

  return;
}

# "This is the worst thing you've ever done.
#  You say that so often that it lost its meaning."
sub search {
  my ($self, $namespace) = @_;

  # Scan
  my $modules = [];
  my %found;
  foreach my $directory (exists $INC{'blib.pm'} ? grep {/blib/} @INC : @INC) {
    my $path = File::Spec->catdir($directory, (split /::/, $namespace));
    next unless (-e $path && -d $path);

    # Get files
    opendir(my $dir, $path);
    my @files = grep /\.pm$/, readdir($dir);
    closedir($dir);

    # Check files
    for my $file (@files) {
      next if -d File::Spec->catfile(File::Spec->splitdir($path), $file);

      # Module found
      my $name = File::Basename::fileparse($file, qr/\.pm/);
      my $class = "$namespace\::$name";
      push @$modules, $class unless $found{$class};
      $found{$class} ||= 1;
    }
  }

  return unless @$modules;
  return $modules;
}

1;
__END__

=head1 NAME

Mojo::Loader - Loader

=head1 SYNOPSIS

  use Mojo::Loader;

  my $loader = Mojo::Loader->new;
  my $modules = $loader->search('Some::Namespace');
  $loader->load($modules->[0]);

=head1 DESCRIPTION

L<Mojo::Loader> is a class loader and plugin framework.

=head1 METHODS

L<Mojo::Loader> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<load>

  my $e = $loader->load('Foo::Bar');

Load a class and catch exceptions.
Note that classes are checked for a C<new> method to see if they are already
loaded.

  if (my $e = $loader->load('Foo::Bar')) {
    die "Exception: $e" if ref $e;
  }

=head2 C<search>

  my $modules = $loader->search('MyApp::Namespace');

Search for modules in a namespace non-recursively.

  $loader->load($_) for @{$loader->search('MyApp::Namespace')};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
