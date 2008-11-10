# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Scripts;

use strict;
use warnings;

use base 'Mojo::Script';

use Mojo::ByteStream;
use Mojo::Loader;

__PACKAGE__->attr([qw/base namespace/],
    chained => 1,
    default => 'Mojo::Script'
);
__PACKAGE__->attr('message', chained => 1, default => <<'EOF');
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
    my ($self, $script, @args) = @_;

    # Namespaces
    my $namespaces = [$self->namespace];
    unshift @$namespaces, "$ENV{MOJO_APP}\::Script" if $ENV{MOJO_APP};

    # Run script
    if ($script) {

        # Default namespace
        my $name = Mojo::ByteStream->new($script)->camelize;

        my $options = [];
        push @$options, "$_\::$name" for @$namespaces;

        for my $option (@$options) {

            # Try
            eval {
                Mojo::Loader->new->base($self->base)->load_build($option)
                  ->run(@args);
            };

            # Show real errors
            if ($@) {
                warn "Script error: $@" unless $@ =~ /Can't locate /i;
            }
            else { return $self }
        }
        print qq/Couldn't find script "$script".\n/;

        return $self;
    }

    # Load scripts
    my @instances;
    for my $namespace (@$namespaces) {
        my $instances =
          Mojo::Loader->new($namespace)->base($self->base)->load->build;
        push @instances, @$instances;
    }

    # Print overview
    print $self->message;

    # List available scripts
    my %names;
    foreach my $instance (@instances) {

        # Generate name
        my $module    = ref $instance;
        my $namespace = $self->namespace;
        $module =~ /.*\:\:([^\:]+)$/;
        my $name = Mojo::ByteStream->new($1)->decamelize;

        next if $names{$name};

        # Print description
        print "$name:\n";
        print $instance->description . "\n";

        $names{$name}++;
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

L<Mojo::Scrips> inherits all attributes from L<Mojo::Script> and implements
the following new ones.

=head2 C<base>

    my $base    = $scripts->base;
    my $scripts = $scripts->base('Mojo::Script');

=head2 C<namespace>

    my $namespace = $scripts->namespace;
    my $scripts   = $scripts->namespace('Mojo::Script');

=head2 C<message>

    my $message = $scripts->message;
    my $scripts = $scripts->message('Hello World!');

=head1 METHODS

L<Mojo::Scrips> inherits all methods from L<Mojo::Script> and implements the
following new ones.

=head2 C<run>

    $scripts = $scripts->run(@ARGV);

=cut
