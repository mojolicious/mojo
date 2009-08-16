# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Scripts;

use strict;
use warnings;

use base 'Mojo::Script';

use Mojo::ByteStream 'b';
use Mojo::Loader;

__PACKAGE__->attr(hint => <<"EOF");

See '$0 help SCRIPT' for more information on a specific script.
EOF
__PACKAGE__->attr(message => <<"EOF");
usage: $0 SCRIPT [OPTIONS]

These scripts are currently available:
EOF
__PACKAGE__->attr(namespaces => sub { ['Mojo::Script'] });

# Aren't we forgeting the true meaning of Christmas?
# You know, the birth of Santa.
sub run {
    my ($self, $name, @args) = @_;

    # Run script
    if ($name && $name =~ /^\w+$/ && ($name ne 'help' || $args[0])) {

        # Help?
        my $help = $name eq 'help' ? 1 : 0;
        $name = shift @args if $help;

        # Try all namespaces
        my $module;
        for my $namespace (@{$self->namespaces}) {

            # Generate module
            my $try = $namespace . '::' . b($name)->camelize;

            # Load
            if (my $e = Mojo::Loader->load($try)) {

                # Module missing
                next unless ref $e;

                # Real error
                die $e;
            }

            # Found
            $module = $try;
            last;
        }

        # Script missing
        die qq/Script "$name" missing, maybe you need to install it?\n/
          unless $module;

        # Run
        my $script = $module->new;
        $help ? $script->help : $script->run(@args);
        return $self;
    }

    # Try all namspaces
    my $scripts = [];
    my $seen    = {};
    for my $namespace (@{$self->namespaces}) {

        # Search
        my $found = Mojo::Loader->search($namespace);

        for my $module (@$found) {

            # Load
            if (my $e = Mojo::Loader->load($module)) { die $e }

            # Seen?
            my $script = $module;
            $script =~ s/^$namespace\:://;
            push @$scripts, [$script => $module] unless $seen->{$script};
            $seen->{$script} = 1;
        }
    }

    # Print overview
    print $self->message;

    # Make list
    my $list   = [];
    my $length = 0;
    foreach my $script (@$scripts) {

        # Generate name
        my $name = $script->[0];
        $name = b($name)->decamelize;

        # Add to list
        my $l = length $name;
        $length = $l if $l > $length;
        push @$list, [$name, $script->[1]->new->description];
    }

    # Print list
    foreach my $script (@$list) {
        my $name        = $script->[0];
        my $description = $script->[1];
        my $padding     = ' ' x ($length - length $name);
        print "  $name$padding   $description";
    }

    # Hint
    print $self->hint;

    return $self;
}

sub start {
    my $self = shift;

    # Arguments
    my @args = @_ ? @_ : @ARGV;

    # Run
    ref $self ? $self->run(@args) : $self->new->run(@args);
}

1;
__END__

=head1 NAME

Mojo::Scripts - Scripts

=head1 SYNOPSIS

    use Mojo::Scripts;

    my $scripts = Mojo::Scripts->new;
    $scripts->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Scripts> is the interactive script interface to the L<Mojo>
framework.

=head1 ATTRIBUTES

L<Mojo::Scripts> inherits all attributes from L<Mojo::Script> and implements
the following new ones.

=head2 C<message>

    my $message = $scripts->message;
    my $scripts = $scripts->message('Hello World!');

=head2 C<namespaces>

    my $namespaces = $scripts->namespaces;
    my $scripts    = $scripts->namespaces(['Mojo::Script']);

=head1 METHODS

L<Mojo::Scripts> inherits all methods from L<Mojo::Script> and implements the
following new ones.

=head2 C<run>

    $scripts = $scripts->run;
    $scripts = $scripts->run(@ARGV);

=head2 C<start>

    Mojo::Scripts->start;
    Mojo::Scripts->start(@ARGV);

=cut
