# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Commands;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::ByteStream 'b';
use Mojo::Loader;

__PACKAGE__->attr(hint => <<"EOF");

See '$0 help COMMAND' for more information on a specific command.
EOF
__PACKAGE__->attr(message => <<"EOF");
usage: $0 COMMAND [OPTIONS]

These commands are currently available:
EOF
__PACKAGE__->attr(namespaces => sub { ['Mojo::Command'] });

# Aren't we forgeting the true meaning of Christmas?
# You know, the birth of Santa.
sub run {
    my ($self, $name, @args) = @_;

    # Run command
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

        # Command missing
        die qq/Command "$name" missing, maybe you need to install it?\n/
          unless $module;

        # Run
        my $command = $module->new;
        $help ? $command->help : $command->run(@args);
        return $self;
    }

    # Try all namspaces
    my $commands = [];
    my $seen     = {};
    for my $namespace (@{$self->namespaces}) {

        # Search
        my $found = Mojo::Loader->search($namespace);

        for my $module (@$found) {

            # Load
            if (my $e = Mojo::Loader->load($module)) { die $e }

            # Seen?
            my $command = $module;
            $command =~ s/^$namespace\:://;
            push @$commands, [$command => $module] unless $seen->{$command};
            $seen->{$command} = 1;
        }
    }

    # Print overview
    print $self->message;

    # Make list
    my $list   = [];
    my $length = 0;
    foreach my $command (@$commands) {

        # Generate name
        my $name = $command->[0];
        $name = b($name)->decamelize;

        # Add to list
        my $l = length $name;
        $length = $l if $l > $length;
        push @$list, [$name, $command->[1]->new->description];
    }

    # Print list
    foreach my $command (@$list) {
        my $name        = $command->[0];
        my $description = $command->[1];
        my $padding     = ' ' x ($length - length $name);
        print "  $name$padding   $description";
    }

    # Hint
    print $self->hint;

    return $self;
}

sub start {
    my $self = shift;

    # Don't run commands if we are reloading
    return $self if $ENV{MOJO_COMMANDS_DONE};
    $ENV{MOJO_COMMANDS_DONE} ||= 1;

    # Arguments
    my @args = @_ ? @_ : @ARGV;

    # Run
    ref $self ? $self->run(@args) : $self->new->run(@args);
}

1;
__END__

=head1 NAME

Mojo::Commands - Commands

=head1 SYNOPSIS

    use Mojo::Commands;

    my $commands = Mojo::Commands->new;
    $commands->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Commands> is the interactive command interface to the L<Mojo>
framework.

=head1 ATTRIBUTES

L<Mojo::Commands> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<message>

    my $message  = $commands->message;
    $commands    = $commands->message('Hello World!');

=head2 C<namespaces>

    my $namespaces = $commands->namespaces;
    $commands      = $commands->namespaces(['Mojo::Command']);

=head1 METHODS

L<Mojo::Commands> inherits all methods from L<Mojo::Command> and implements
the following new ones.

=head2 C<run>

    $commands = $commands->run;
    $commands = $commands->run(@ARGV);

=head2 C<start>

    Mojo::Commands->start;
    Mojo::Commands->start(@ARGV);

=cut
