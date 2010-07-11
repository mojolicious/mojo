# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command::Generate::App;

use strict;
use warnings;

use base 'Mojo::Command';

__PACKAGE__->attr(description => <<'EOF');
Generate application directory structure.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 generate app [NAME]
EOF

# Okay folks, show's over. Nothing to see here, show's... Oh my god!
# A horrible plane crash! Hey everybody, get a load of this flaming wreckage!
# Come on, crowd around, crowd around!
sub run {
    my ($self, $class) = @_;
    $class ||= 'MyMojoApp';

    my $name = $self->class_to_file($class);

    # Script
    $self->render_to_rel_file('mojo', "$name/script/$name", $class);
    $self->chmod_file("$name/script/$name", 0744);

    # Appclass
    my $path = $self->class_to_path($class);
    $self->render_to_rel_file('appclass', "$name/lib/$path", $class);

    # Test
    $self->render_to_rel_file('test', "$name/t/basic.t", $class);

    # Log
    $self->create_rel_dir("$name/log");
}

1;
__DATA__
@@ mojo
% my $class = shift;
#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename 'dirname';
use File::Spec;

use lib join '/', File::Spec->splitdir(dirname(__FILE__)), 'lib';
use lib join '/', File::Spec->splitdir(dirname(__FILE__)), '..', 'lib';

# Check if Mojo is installed
eval 'use Mojo::Commands';
die <<EOF if $@;
It looks like you don't have the Mojo Framework installed.
Please visit http://mojolicious.org for detailed installation instructions.

EOF

# Application
$ENV{MOJO_APP} ||= '<%= $class %>';

# Start commands
Mojo::Commands->start;
@@ appclass
% my $class = shift;
package <%= $class %>;

use strict;
use warnings;

use base 'Mojo';

sub handler {
    my ($self, $tx) = @_;

    # Hello world!
    $tx->res->code(200);
    $tx->res->headers->content_type('text/plain');
    $tx->res->body('Hello Mojo!');
}

1;
@@ test
% my $class = shift;
#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;

use_ok('<%= $class %>');
__END__
=head1 NAME

Mojo::Command::Generate::App - Application Generator Command

=head1 SYNOPSIS

    use Mojo::Command::Generate::App;

    my $app = Mojo::Command::Generate::App->new;
    $app->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Generate::App> is an application generator.

=head1 ATTRIBUTES

L<Mojo::Command::Generate::App> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

    my $description = $app->description;
    $app            = $app->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $app->usage;
    $app      = $app->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojo::Command::Generate::App> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

    $app = $app->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
