# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Script::Generate::App;

use strict;
use warnings;

use base 'Mojo::Script';

__PACKAGE__->attr('description', chained => 1, default => <<'EOF');
* Generate application directory structure. *
Takes a name as option, by default MyMojoApp will be used.
    generate app TestApp
EOF

# Okay folks, show's over. Nothing to see here, show's... Oh my god!
# A horrible plane crash! Hey everybody, get a load of this flaming wreckage!
# Come on, crowd around, crowd around!
sub run {
    my ($self, $class) = @_;
    $class ||= 'MyMojoApp';

    my $name = $self->class_to_file($class);

    # Script
    $self->render_to_rel_file('mojo', "$name/bin/$name", $class);
    $self->chmod_file("$name/bin/$name", 0744);

    # Appclass
    my $path = $self->class_to_path($class);
    $self->render_to_rel_file('appclass', "$name/lib/$path", $class);

    # Test
    $self->render_to_rel_file('test', "$name/t/basic.t", $class);
}

1;

=head1 NAME

Mojo::Script::Generate::App - Application Generator Script

=head1 SYNOPSIS

    use Mojo::Script::Generate::App;

    my $app = Mojo::Script::Generate::App->new;
    $app->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Script::Generate::App> is a application generator.

=head1 ATTRIBUTES

L<Mojo::Script::Generate::App> inherits all attributes from L<Mojo::Scripts>
and implements the following new ones.

=head2 C<description>

    my $description = $app->description;
    $app            = $app->description('Foo!');

=head1 METHODS

L<Mojo::Script::Generate::App> inherits all methods from L<Mojo::Script> and
implements the following new ones.

=head2 C<run>

    $app = $app->run(@ARGV);

=cut

__DATA__
__mojo__
% my $class = shift;
#!<%= $^X %>

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use FindBin;

use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";

$ENV{MOJO_APP} = '<%= $class %>';

# Check if Mojo is installed
eval 'use Mojo::Scripts';
if ($@) {
    print <<EOF;
It looks like you don't have the Mojo Framework installed.
Please visit http://mojolicious.org for detailed installation instructions.

EOF
    exit;
}

# Start the script system
my $scripts = Mojo::Scripts->new;
$scripts->run(@ARGV);
__appclass__
% my $class = shift;
package <%= $class %>;

use strict;
use warnings;

use base 'Mojo';

sub handler {
    my ($self, $tx) = @_;

    # $tx is a Mojo::Transaction instance
    $tx->res->code(200);
    $tx->res->headers->content_type('text/plain');
    $tx->res->body('Hello Mojo!');

    return $tx;
}

1;
__test__
% my $class = shift;
#!perl

use strict;
use warnings;

use Test::More tests => 1;

use_ok('<%= $class %>');