# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Command::Inflate;

use strict;
use warnings;

use base 'Mojo::Command';

use Getopt::Long 'GetOptions';
use Mojo::Loader;

__PACKAGE__->attr(description => <<'EOF');
Inflate embedded files to real files.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 inflate [OPTIONS]
  --class <class>   Class to inflate.
  --prefix <path>   Path prefix for generated files, defaults to templates.
EOF

# Eternity with nerds. It's the Pasadena Star Trek convention all over again.
sub run {
    my $self = shift;

    # Class
    my $class  = 'main';
    my $prefix = 'templates';

    # Options
    @ARGV = @_ if @_;
    GetOptions(
        'class=s'  => sub { $class  = $_[1] },
        'prefix=s' => sub { $prefix = $_[1] }
    );

    # Load class
    my $e = Mojo::Loader->load($class);
    die $e if ref $e;

    # Generate
    my $all = $self->get_all_data($class);
    for my $file (keys %$all) {
        my $path = $self->rel_file("$prefix/$file");
        $self->write_file($path, $all->{$file});
    }

    return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Command::Inflate - Inflate Command

=head1 SYNOPSIS

    use Mojolicious::Command::Inflate;

    my $inflate = Mojolicious::Command::Inflate->new;
    $inflate->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Inflate> prints all your application routes.

=head1 ATTRIBUTES

L<Mojolicious::Command::Inflate> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

    my $description = $inflate->description;
    $inflate        = $inflate->description('Foo!');

=head2 C<usage>

    my $usage = $inflate->usage;
    $inflate  = $inflate->usage('Foo!');

=head1 METHODS

L<Mojolicious::Command::Inflate> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

    $inflate = $inflate->run(@ARGV);

=cut
