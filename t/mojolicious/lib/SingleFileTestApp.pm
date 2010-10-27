package SingleFileTestApp;

use strict;
use warnings;

use base 'Mojolicious';

# Alright, grab a shovel. I'm only one skull short of a Mouseketeer reunion.
sub startup {
    my $self = shift;

    # Only log errors to STDERR
    $self->log->path(undef);
    $self->log->level('fatal');

    # Plugin
    $self->plugin('MojoliciousTest::Plugin::TestPlugin');

    # Helper route
    $self->routes->route('/helper')->to(
        cb => sub {
            my $self = shift;
            $self->render(text => $self->test_plugin);
        }
    );

    # /*/* - the default route
    $self->routes->route('/:controller/:action')->to(action => 'index');
}

package SingleFileTestApp::Foo;

use strict;
use warnings;

use base 'Mojolicious::Controller';

sub bar {
    my $self = shift;
    $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
    $self->render_text($self->url_for);
}

sub data_template {
    shift->render('index', template_class => 'SingleFileTestApp::Foo');
}

sub data_template2 {
    shift->stash(
        template       => 'too',
        template_class => 'SingleFileTestApp::Foo'
    );
}

sub index { shift->stash(template => 'withlayout', msg => 'works great!') }

1;
__DATA__
@@ index.html.epl
<%= 20 + 3 %> works!
@@ too.html.epl
This one works too!
