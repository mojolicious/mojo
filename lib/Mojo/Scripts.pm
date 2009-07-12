# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Scripts;

use strict;
use warnings;

use base 'Mojo::Script';

use Mojo::ByteStream 'b';
use Mojo::Loader;

__PACKAGE__->attr('namespace', default => 'Mojo::Script');
__PACKAGE__->attr('message',   default => <<'EOF');
Welcome to the Mojo Framework!

HINT: In case you don't know what you are doing here try the manual!
    perldoc Mojo::Manual
    perldoc Mojo::Manual::GettingStarted

This is the interactive script interface, the syntax is very simple.
    mojo <script> <options>

Below you will find a list of available scripts with descriptions.

EOF

# Aren't we forgeting the true meaning of Christmas?
# You know, the birth of Santa.
sub run {
    my ($self, $name, @args) = @_;

    # Run script
    if ($name) {

        # Generate module
        my $module = $self->namespace . '::' . b($name)->camelize;

        # Load
        if (my $e = Mojo::Loader->load($module)) {

            # Module missing
            die qq/Script "$name" missing, maybe you need to install it?\n/
              unless ref $e;

            # Real error
            die $e;
        }

        # Run
        $module->new->run(@args);
        return $self;
    }

    # Load scripts
    my $modules = Mojo::Loader->search($self->namespace);
    for my $module (@$modules) {
        if (my $e = Mojo::Loader->load($module)) { die $e }
    }

    # Print overview
    print $self->message;

    # List available scripts
    foreach my $module (@$modules) {

        my $script = $module->new;

        # Generate name
        my $namespace = $self->namespace;
        $module =~ s/^$namespace\:\://;
        my $name = b($module)->decamelize;

        # Print description
        print "$name:\n";
        print $script->description . "\n";
    }

    return $self;
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

=head2 C<namespace>

    my $namespace = $scripts->namespace;
    my $scripts   = $scripts->namespace('Mojo::Script');

=head2 C<message>

    my $message = $scripts->message;
    my $scripts = $scripts->message('Hello World!');

=head1 METHODS

L<Mojo::Scripts> inherits all methods from L<Mojo::Script> and implements the
following new ones.

=head2 C<run>

    $scripts = $scripts->run(@ARGV);

=cut
