package Mojo::Loader;
use Mojo::Base -base;

use Carp 'carp';
use File::Basename;
use File::Spec;
use Mojo::Command;
use Mojo::Exception;

use constant DEBUG => $ENV{MOJO_LOADER_DEBUG} || 0;

my $STATS = {};

BEGIN {

  # Debugger sub tracking
  $^P |= 0x10;
}

# "Homer no function beer well without."
sub load {
  my ($self, $module) = @_;

  # Check module name
  return 1 if !$module || $module !~ /^[\w\:\']+$/;

  # Forced reload
  if ($ENV{MOJO_RELOAD}) {

    # Unload
    my $key = $module;
    $key =~ s/\:\:/\//g;
    $key .= '.pm';
    _unload($key);
  }

  # Already loaded
  else { return if $module->can('new') }

  # Load
  eval "require $module";

  # Catch
  if ($@) {

    # Exists
    my $path = Mojo::Command->class_to_path($module);
    return 1 if $@ =~ /^Can't locate $path in \@INC/;

    # Real error
    return Mojo::Exception->new($@);
  }

  return;
}

sub reload {

  # Cleanup script
  delete $INC{$0};
  $STATS->{$0} = 1;

  # Reload
  while (my ($key, $file) = each %INC) {

    # Modified time
    next unless $file;
    my $mtime = (stat $file)[9];

    # Startup time as default
    $STATS->{$file} = $^T unless defined $STATS->{$file};

    # Modified
    if ($mtime > $STATS->{$file}) {

      # Reload
      if (my $e = _reload($key)) { return $e }

      # Reloaded
      $STATS->{$file} = $mtime;
    }
  }

  # Force script reloading
  return _reload($0);
}

sub search {
  my ($self, $namespace) = @_;

  # Directories
  my @directories = exists $INC{'blib.pm'} ? grep {/blib/} @INC : @INC;

  # Scan
  my $modules = [];
  my %found;
  foreach my $directory (@directories) {
    my $path = File::Spec->catdir($directory, (split /::/, $namespace));
    next unless (-e $path && -d $path);

    # Get files
    opendir(my $dir, $path);
    my @files = grep /\.pm$/, readdir($dir);
    closedir($dir);

    # Check files
    for my $file (@files) {
      my $full = File::Spec->catfile(File::Spec->splitdir($path), $file);

      # Directory
      next if -d $full;

      # Found
      my $name = File::Basename::fileparse($file, qr/\.pm/);
      my $class = "$namespace\::$name";
      push @$modules, $class unless $found{$class};
      $found{$class} ||= 1;
    }
  }

  return unless @$modules;
  return $modules;
}

sub _reload {
  my $key = shift;

  # Debug
  warn "$key modified, reloading!\n" if DEBUG;

  # Unload
  _unload($key);

  # Failed
  return Mojo::Exception->new($@) unless eval { require $key; 1 };

  # Success
  return;
}

sub _unload {
  my $key = shift;

  # Unload
  my $file = $INC{$key};
  delete $INC{$key};
  return unless $file;
  my @subs = grep { index($DB::sub{$_}, "$file:") == 0 }
    keys %DB::sub;
  for my $sub (@subs) {
    eval { undef &$sub };
    carp "Can't unload sub '$sub' in '$file': $@" if $@;
    delete $DB::sub{$sub};
  }
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

  # Reload
  Mojo::Loader->reload;

=head1 DESCRIPTION

L<Mojo::Loader> is a class loader and plugin framework.

=head1 METHODS

L<Mojo::Loader> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<load>

  my $e = $loader->load('Foo::Bar');

Load a class, note that classes are checked for a C<new> method to see if
they are already loaded.

=head2 C<reload>

  my $e = Mojo::Loader->reload;

Reload all Perl files with changes.

=head2 C<search>

  my $modules = $loader->search('MyApp::Namespace');

Search modules in a namespace.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
