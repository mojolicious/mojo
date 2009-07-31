# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Script::Generate::App;

use strict;
use warnings;

use base 'Mojo::Script';

__PACKAGE__->attr('description', default => <<'EOF');
Generate application directory structure.
EOF
__PACKAGE__->attr('usage', default => <<"EOF");
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

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use FindBin;

use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

# Check if Mojo is installed
eval 'use Mojo';
die <<EOF if $@;
It looks like you don't have the Mojo Framework installed.
Please visit http://mojolicious.org for detailed installation instructions.

EOF

# Start application
use <%= $class %>;
<%= $class %>->start;
@@ appclass
% my $class = shift;
package <%= $class %>;

use strict;
use warnings;

use base 'Mojo';

sub handler {
    my ($self, $tx) = @_;

    # Hello world!
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

=head2 C<usage>

    my $usage = $app->usage;
    $app      = $app->usage('Foo!');

=head1 METHODS

L<Mojo::Script::Generate::App> inherits all methods from L<Mojo::Script> and
implements the following new ones.

=head2 C<run>

    $app = $app->run(@ARGV);

=cut
