# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Loader;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp qw/carp croak/;
use File::Basename;
use File::Spec;
use Mojo::Loader::Exception;

use constant DEBUG => $ENV{MOJO_LOADER_DEBUG} || 0;

__PACKAGE__->attr([qw/base namespace/] => (chained => 1));
__PACKAGE__->attr(modules => (chained => 1, default => sub { [] }));

my $STATS = {};

BEGIN {

    # Debugger sub tracking
    $^P |= 0x10;

    # Bug in pre-5.8.7 perl
    # http://rt.perl.org/rt3/Ticket/Display.html?id=35059
    eval 'sub DB::sub' if $] < 5.008007;
}

# Homer no function beer well without.
sub new {
    my ($class, $namespace) = @_;
    my $self = $class->SUPER::new();
    $self->namespace($namespace);
    $self->search if $namespace;
    return $self;
}

sub build {
    my $self = shift;

    # Load and instantiate
    my @instances;
    foreach my $module (@{$self->modules}) {

        eval {
            if (my $base = $self->base)
            {
                die "SHORTCUT\n" unless $module->isa($base);
            }
            my $instance = $module->new(@_);
            push @instances, $instance;
        };
        return Mojo::Loader::Exception->new($@) if $@ && $@ ne "SHORTCUT\n";
    }

    return \@instances;
}

sub load {
    my ($self, @modules) = @_;

    $self->modules(\@modules) if @modules;

    for my $module (@{$self->modules}) {

        # Shortcut
        next if $module->can('isa');

        # Load
        eval "require $module";
        return Mojo::Loader::Exception->new($@) if $@;
    }

    return 0;
}

sub load_build {
    my $self = shift;

    # Instantiate self
    $self = $self->new unless ref $self;

    # Load
    my $e = $self->load(shift);
    return $e if $e;

    # Build
    $e = $self->build(@_);
    return ref $e eq 'Mojo::Loader::Exception' ? $e : $e->[0];
}

sub reload {
    while (my ($key, $file) = each %INC) {

        # Modified time
        next unless $file;
        my $mtime = (stat $file)[9];

        # Startup time as default
        $STATS->{$file} = $^T unless defined $STATS->{$file};

        # Modified?
        if ($mtime > $STATS->{$file}) {

            warn "\n$key -> $file modified, reloading!\n" if DEBUG;

            # Unload
            delete $INC{$key};
            my @subs = grep { index($DB::sub{$_}, "$file:") == 0 }
              keys %DB::sub;
            for my $sub (@subs) {
                eval { undef &$sub };
                carp "Can't unload sub '$sub' in '$file': $@" if $@;
                delete $DB::sub{$sub};
            }

            # Reload
            eval { require $key };
            return Mojo::Loader::Exception->new($@) if $@;

            $STATS->{$file} = $mtime;
        }
    }

    return 0;
}

sub search {
    my ($self, $namespace) = @_;

    $namespace ||= $self->namespace;
    $self->namespace($namespace);

    # Directories
    my @directories = exists $INC{'blib.pm'} ? grep {/blib/} @INC : @INC;

    # Scan
    my %found;
    foreach my $directory (@directories) {
        my $path = File::Spec->catdir($directory, (split /::/, $namespace));
        next unless (-e $path && -d $path);

        # Find
        opendir(my $dir, $path);
        my @files = grep /\.pm$/, readdir($dir);
        closedir($dir);
        for my $file (@files) {
            my $full =
              File::Spec->catfile(File::Spec->splitdir($path), $file);
            next if -d $full;
            my $name = File::Basename::fileparse($file, qr/\.pm/);
            my $class = "$namespace\::$name";
            push @{$self->{modules}}, $class unless $found{$class};
            $found{$class} ||= 1;
        }
    }

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Loader - Loader

=head1 SYNOPSIS

    use Mojo::Loader;

    # Long
    my @instances = Mojo::Loader->new
      ->namespace('Some::Namespace')
      ->search
      ->load
      ->base('Some::Module')
      ->build;

    # Short
    my $something = Mojo::Loader->load_build('Some::Namespace');

    # Reload
    Mojo::Loader->reload;

=head1 DESCRIPTION

L<Mojo::Loader> is a class loader and plugin framework.

=head1 ATTRIBUTES

=head2 C<base>

    my $base = $loader->base;
    $loader  = $loader->base('MyApp::Base');

=head2 C<modules>

    my $modules = $loader->modules;
    $loader     = $loader->modules([qw/MyApp::Foo MyApp::Bar/]);

=head2 C<namespace>

    my $namespace = $loader->namespace;
    $loader       = $loader->namespace('MyApp::Namespace');

=head1 METHODS

L<Mojo::Loader> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $loader = Mojo::Loader->new;
    my $loader = Mojo::Loader->new('MyApp::Namespace');

=head2 C<build>

    my $instances = $loader->build;
    my $instances = $loader->build(qw/foo bar baz/);
    my $exception = $loader->build;
    my $exception = $loader->build(qw/foo bar baz/);

=head2 C<load>

    my $exception = $loader->load;

=head2 C<load_build>

    my $instance  = Mojo::Loader->load_build('MyApp');
    my $instance  = $loader->load_build('MyApp');
    my $instance  = Mojo::Loader->load_build('MyApp', qw/some args/);
    my $instance  = $loader->load_build('MyApp', qw/some args/);
    my $exception = Mojo::Loader->load_build('MyApp');
    my $exception = $loader->load_build('MyApp');
    my $exception = Mojo::Loader->load_build('MyApp', qw/some args/);
    my $exception = $loader->load_build('MyApp', qw/some args/);

=head2 C<reload>

    my $exception = Mojo::Loader->reload;

=head2 C<search>

    $loader = $loader->search;
    $loader = $loader->search('MyApp::Namespace');

=cut
