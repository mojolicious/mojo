package Mojo::Loader;
use Mojo::Base -base;

use File::Basename 'fileparse';
use File::Spec::Functions qw/catdir catfile splitdir/;
use Mojo::Command;
use Mojo::Exception;

# "Homer no function beer well without."
sub load {
  my ($self, $module) = @_;

  # Check module name
  return 1 if !$module || $module !~ /^\w(?:[\w\:\']*\w)?$/;

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
  my (@modules, %found);
  for my $directory (exists $INC{'blib.pm'} ? grep {/blib/} @INC : @INC) {
    next unless -d (my $path = catdir $directory, (split /::/, $namespace));

    # Check files
    opendir(my $dir, $path);
    for my $file (grep /\.pm$/, readdir($dir)) {
      next if -d catfile splitdir($path), $file;

      # Module found
      my $class = "$namespace\::" . fileparse $file, qr/\.pm/;
      push @modules, $class unless $found{$class}++;
    }
    closedir $dir;
  }

  return \@modules;
}

1;

=head1 NAME

Mojo::Loader - Loader

=head1 SYNOPSIS

  use Mojo::Loader;

  # Find modules in a namespace
  my $loader = Mojo::Loader->new;
  for my $module (@{$loader->search('Some::Namespace')}) {

    # And load them safely
    my $e = $loader->load($module);
    warn qq/Loading "$module" failed: $e/ if ref $e;
  }

=head1 DESCRIPTION

L<Mojo::Loader> is a class loader and plugin framework.

=head1 METHODS

L<Mojo::Loader> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<load>

  my $e = $loader->load('Foo::Bar');

Load a class and catch exceptions. Note that classes are checked for a C<new>
method to see if they are already loaded.

  if (my $e = $loader->load('Foo::Bar')) {
    die "Exception: $e" if ref $e;
  }

=head2 C<search>

  my $modules = $loader->search('MyApp::Namespace');

Search for modules in a namespace non-recursively.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
