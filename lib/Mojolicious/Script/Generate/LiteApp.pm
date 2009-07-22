# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Script::Generate::LiteApp;

use strict;
use warnings;

use base 'Mojo::Script';

__PACKAGE__->attr('description', default => <<'EOF');
* Generate a minimalistic single file example application. *
Takes a name as option, by default MyMojoliciousApp will be used.
    generate lite_app TestApp
EOF

# If for any reason you're not completely satisfied, I hate you.
sub run {
    my ($self, $class) = @_;
    $class ||= 'MyMojoliciousApp';

    my $name = $self->class_to_file($class);

    # App
    $self->renderer->line_start('%%');
    $self->renderer->tag_start('<%%');
    $self->renderer->tag_end('%%>');
    $self->render_to_rel_file('liteapp', "$name.pl", $class);
    $self->chmod_file("$name.pl", 0744);
}

1;

=head1 NAME

Mojolicious::Script::Generate::LiteApp - Lite App Generator Script

=head1 SYNOPSIS

    use Mojo::Script::Generate::LiteApp;

    my $app = Mojo::Script::Generate::LiteApp->new;
    $app->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Script::Generate::LiteApp> is a application generator.

=head1 ATTRIBUTES

L<Mojolicious::Script::Generate::LiteApp> inherits all attributes from
L<Mojo::Script>.

=head1 METHODS

L<Mojolicious::Script::Generate::LiteApp> inherits all methods from
L<Mojo::Script> and implements the following new ones.

=head2 C<run>

    $app->run(@ARGV);

=cut

__DATA__
__liteapp__
%% my $class = shift;
#!/usr/bin/env perl

# The application class
package <%%= $class %%>;

use strict;
use warnings;

use base 'Mojolicious';

# This method will run once at startup time
sub startup {
    my $self = shift;
    my $r    = $self->routes;

    # In lite applications we default to eplite templates
    $self->renderer->default_handler('eplite');

    # The default route /*/*
    $r->route('/(controller)/(action)')
      ->to(controller => 'foo', action => 'index');
}

# Our very first controller class!
package <%%= $class %%>::Foo;

use strict;
use warnings;

use base 'Mojolicious::Controller';

sub index {
    my $self = shift;

    # Put a friendly message into the stash for the template
    $self->stash(greeting => 'Hello Mojo!');
}

# The main package, used mostly for the script system
package main;

use strict;
use warnings;

# Check if Mojo is installed
eval 'use Mojolicious::Scripts';
die <<EOF if $@;
It looks like you don't have the Mojo Framework installed.
Please visit http://mojolicious.org for detailed installation instructions.

EOF

$ENV{MOJO_APP} = '<%%= $class %%>';

# Start the script system and our application
Mojolicious::Scripts->new->run(@ARGV);

1;
# The templates live in the data section
<%%= '__DATA__' %%>
<%%= '__foo/index.html.eplite__' %%>
%# Our very first template!
% my $self = shift;
%# We want to use the default layout
% $self->stash(layout => 'default');
%# Now we just display the message we put into the stash earlier
<%= $self->stash('greeting') %>

<%%= '__layouts/default.html.eplite__' %%>
%# A minimalistic HTML 5 layout
% my $self = shift;
<!html>
    <head><title><%= $self->stash('title') || 'Welcome!' %></title></head>
    <body>
%# Here we insert the normal template content
%= $self->render_inner
    </body>
</html>
