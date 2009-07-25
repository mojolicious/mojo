# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Lite;

use strict;
use warnings;

use base 'Mojolicious';

use File::Spec;
use FindBin;
use Mojolicious::Scripts;

# Singleton
my $APP;

# It's the future, my parents, my co-workers, my girlfriend,
# I'll never see any of them ever again... YAHOOO!
sub import {
    my $class = shift;

    # Lite apps are strict!
    strict->import;
    warnings->import;

    # Home
    $ENV{MOJO_HOME} ||= File::Spec->catdir(split '/', $FindBin::Bin);

    # Initialize app
    $APP = $class->new;

    # Renderer
    $APP->renderer->default_handler('eplite');

    # Route generator
    my $route = sub {
        my $methods = shift;

        my ($cb, $constraints, $defaults, $name, $pattern);

        # Route information
        for my $arg (@_) {

            # First scalar is the pattern
            if (!ref $arg && !$pattern) { $pattern = $arg }

            # Second scalar is the route name
            elsif (!ref $arg) { $name = $arg }

            # Callback
            elsif (ref $arg eq 'CODE') { $cb = $arg }

            # Constraints
            elsif (ref $arg eq 'ARRAY') { $constraints = $arg }

            # Defaults
            elsif (ref $arg eq 'HASH') { $defaults = $arg }
        }

        # Defaults
        $cb ||= sub {1};
        $constraints ||= [];

        # Merge
        $defaults ||= {};
        $defaults = {%$defaults, callback => $cb};

        # Create route
        $APP->routes->route($pattern, {@$constraints})->via($methods)
          ->to($defaults)->name($name);
    };

    # Prepare exports
    my $caller = caller;
    no strict 'refs';

    # Export
    *{"${caller}::app"}  = sub {$APP};
    *{"${caller}::any"}  = sub { $route->(ref $_[0] ? shift : [], @_) };
    *{"${caller}::get"}  = sub { $route->('get', @_) };
    *{"${caller}::post"} = sub { $route->('post', @_) };

    # Shagadelic!
    *{"${caller}::shagadelic"} = sub {

        # We are the app in a lite environment
        $ENV{MOJO_APP} = 'Mojolicious::Lite';

        # Start script system
        Mojolicious::Scripts->new->run(@_ ? @_ : @ARGV);
    };
}

# Steven Hawking, aren't you that guy who invented gravity?
# Sure, why not.
sub new { $APP || shift->SUPER::new(@_) }

1;
__END__

=head1 NAME

Mojolicious::Lite - Micro Web Framework

=head1 SYNOPSIS

    # Using Mojolicious::Lite will enable "strict" and "warnings"
    use Mojolicious::Lite;

    # GET /*/bar (self contained without a template)
    get '/:foo/bar' => sub {
        my $self = shift;
        $self->render(text => 'Yea baby!');
    };

    # Shagadelic will start the Mojolicious script system
    shagadelic;

    # You can use all the normal script options from the command line
    % ./myapp.pl daemon
    Server available at http://127.0.0.1:3000.
    % ./myapp.pl daemon 8080
    Server available at http://127.0.0.1:8080.
    % ./myapp.pl mojo daemon_prefork
    Server available at http://127.0.0.1:3000.
    % ./myapp.pl mojo cgi
    ...CGI output...
    % ./myapp.pl mojo fastcgi
    ...Blocking FastCGI main loop...

    # The shagadelic call can be customized to override normal @ARGV use
    shagadelic(qw/mojo cgi/);

    # POST /foo/* (with name and matching template in the DATA section)
    post '/foo/:bar' => 'index';
    __DATA__
    @@ index.html.eplite
    % my $self = shift;
    Our :bar placeholder matched <%= $self->stash('bar') %>.
    We are <%= $self->url_for %>.

    # GET /with_layout (template and layout)
    get '/with_layout' => sub {
        my $self = shift;
        $self->render(template => 'with_layout', layout => 'green');
    };
    __DATA__
    @@ with_layout.html.eplite
    We've got content!
    @@ layouts/green.html.eplite
    <!html>
        <head><title>Green!</title></head>
        <body><%= $self->render_inner %></body>
    </html>

    # GET /bar (using url_for to generate the url for "index" aka. /foo/:bar)
    get '/bar' => sub {
        my $self = shift;
        $self->render(text => $self->url_for('index', bar => 'something'));
    };

    # /baz (nothing special, just allowing all methods)
    any '/baz' => sub {
        my $self = shift;
        $self->render(text => 'You called /baz with ' . $self->req->method);
    };

    # GET /hello/* (matching everything except "/")
    get '/hello/(.you)' => sub {
        shift->render(template => 'groovy');
    };
    __DATA__
    @@ groovy.html.eplite
    Your name is <%= shift->stash('you') %>.

    # GET /hello/* (matching absolutely everything including "/" and ".")
    get '/hello/(*you)' => sub {
        shift->render(template => 'groovy');
    };
    __DATA__
    @@ groovy.html.eplite
    Your name is <%= shift->stash('you') %>.

    # /:something (with special regex constraint only matching digits)
    any '/:something' => [something => qr/\d+/] => sub {
        my $self = shift;
        $self->render(text => 'Something: ' . $self->stash('something'));
    };

    # GET /hello/* (with default value and template)
    get '/hello/:name' => {name => 'Sebastian'} => sub {
        my $self = shift;
        $self->render(template => 'groovy', format => 'txt');
    };
    __DATA__
    @@ groovy.txt.eplite
    % my $self = shift;
    My name is <%= $self->stash('name') %>.

    # GET|POST /bye (allowing GET and POST)
    any [qw/get post/] => '/bye' => sub {
        my $self = shift;
        $self->render(text => 'Bye!');
    };

    # GET /everything/*?name=* (using a lot of features together)
    get '/everything/:stuff' => [stuff => qr/\d+/] => {stuff => 23} => sub {
        shift->render(template => 'welcome');
    };
    __DATA__
    @@ welcome.html.eplite
    % my $self = shift;
    Stuff is <%= $self->stash('stuff') %>.
    Query param name is <%= $self->req->param('name') %>.

    # GET /detection.html (format detection with multiple templates)
    # GET /detection.txt
    get '/detection' => sub {
        my $self = shift;
        $self->render(template => 'detected');
    };
    __DATA__
    @@ detected.html.eplite
    <!html>
        <head><title>Detected!</title></head>
        <body>HTML was detected.</body>
    </html>
    @@ detected.txt.eplite
    TXT was detected.

    # /external (render external template "templates/foo/bar.html.epl")
    any '/external' => sub {
        my $self = shift;
        $self->render(template => 'foo/bar.html.epl');
    };

    # /something.js (serving external static files, yes it's that simple)
    % mkdir public
    % mv something.js public/something.js

    # To disable debug messages later in a production setup you can change
    # the Mojolicious mode (the default mode will be development)
    % MOJO_MODE=production ./myapp.pl

    # For more control you can also access the Mojolicious instance directly
    app->log->level('error');
    app->routes->route('/foo/:bar')->via('get')->to(callback => sub {
        my $self = shift;
        $self->render(text => 'Hello Mojo!');
    });

=head1 DESCRIPTION

L<Mojolicous::Lite> is a micro web framework built upon L<Mojolicious> and
L<Mojo>.
For userfriendly documentation see L<Mojo::Manual::Mojolicious>.

=head1 ATTRIBUTES

L<Mojolicious::Lite> inherits all attributes from L<Mojolicious>.

=head1 METHODS

L<Mojolicious::Lite> inherits all methods from L<Mojolicious> and implements
the following new ones.

=head2 C<new>

    my $mojo = Mojolicious::Lite->new;

=cut
