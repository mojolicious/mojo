# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command::Generate::Psgi;

use strict;
use warnings;

use base 'Mojo::Command';

__PACKAGE__->attr(description => <<'EOF');
Generate .psgi file.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 generate psgi
EOF

# Don't let Krusty's death get you down, boy.
# People die all the time, just like that.
# Why, you could wake up dead tomorrow! Well, good night.
sub run {
    my $self = shift;

    my $class = $ENV{MOJO_APP} || 'MyApp';
    my $name = $self->class_to_file($class);

    $self->render_to_rel_file('psgi', "$name.psgi", $class);
    $self->chmod_file("$name.psgi", 0744);
}

1;
__DATA__
@@ psgi
% my $class = shift;
use FindBin;

use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use Mojo::Server::PSGI;

my $psgi = Mojo::Server::PSGI->new(app_class => '<%= $class %>');
my $app  = sub { $psgi->run(@_) };
__END__
=head1 NAME

Mojo::Command::Generate::Psgi - PSGI Generator Command

=head1 SYNOPSIS

    use Mojo::Command::Generate::Psgi;

    my $psgi = Mojo::Command::Generate::Psgi->new;
    $psgi->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Generate::Psgi> is a PSGI file generator.

=head1 ATTRIBUTES

L<Mojo::Command::Generate::Psgi> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

    my $description = $psgi->description;
    $psgi           = $psgi->description('Foo!');

=head2 C<usage>

    my $usage = $psgi->usage;
    $psgi     = $psgi->usage('Foo!');

=head1 METHODS

L<Mojo::Command::Generate::Psgi> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

    $psgi = $psgi->run(@ARGV);

=cut
