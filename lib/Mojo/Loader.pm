# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Loader;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp qw/carp croak/;
use File::Basename;
use File::Spec;
use Mojo::Loader::Exception;
use Mojo::Script;

use constant DEBUG => $ENV{MOJO_LOADER_DEBUG} || 0;

my $STATS = {};

BEGIN {

    # Debugger sub tracking
    $^P |= 0x10;

    # Bug in pre-5.8.7 perl
    # http://rt.perl.org/rt3/Ticket/Display.html?id=35059
    eval 'sub DB::sub' if $] < 5.008007;
}

# Homer no function beer well without.
sub load {
    my ($self, $module) = @_;

    # Shortcut
    return 1 unless $module;

    # Already loaded?
    return 0 if $module->can('isa');

    # Try
    eval "require $module";

    # Catch
    if ($@) {

        # Exists?
        my $path = Mojo::Script->class_to_path($module);
        return 1 if $@ =~ /^Can't locate $path in \@INC/;

        # Real error
        return Mojo::Loader::Exception->new($@);
    }

    return 0;
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

            # Try
            eval { require $key };

            # Catch
            return Mojo::Loader::Exception->new($@) if $@;

            $STATS->{$file} = $mtime;
        }
    }

    return 0;
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
            push @$modules, $class unless $found{$class};
            $found{$class} ||= 1;
        }
    }

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

    # Reload
    Mojo::Loader->reload;

=head1 DESCRIPTION

L<Mojo::Loader> is a class loader and plugin framework.

=head1 METHODS

L<Mojo::Loader> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $loader = Mojo::Loader->new;
    my $loader = Mojo::Loader->new('MyApp::Namespace');

=head2 C<load>

    my $e = $loader->load('Foo::Bar');

=head2 C<reload>

    my $e = Mojo::Loader->reload;

=head2 C<search>

    my $modules = $loader->search('MyApp::Namespace');

=cut
