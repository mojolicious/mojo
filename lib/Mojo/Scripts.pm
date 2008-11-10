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

    # Run script
    if ($script) {
        my $module = $self->namespace . '::'
          . Mojo::ByteStream->new($script)->camelize;
        Mojo::Loader->new
          ->base($self->base)
          ->load_build($module)
          ->run(@args);
        return $self;
    }

    # Load scripts
    my $instances = Mojo::Loader->new($self->namespace)
      ->base($self->base)
      ->load
      ->build;

    # Print overview
    print $self->message;

    # List available scripts
    foreach my $instance (@$instances) {

        # Generate name
        my $module = ref $instance;
        my $namespace = $self->namespace;
        $module =~ s/^$namespace\:\://;
        my $name = Mojo::ByteStream->new($module)->decamelize;

        # Print description
        print "$name:\n";
        print $instance->description . "\n";
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