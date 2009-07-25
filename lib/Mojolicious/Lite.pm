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

    use Mojolicious::Lite;

    get '/:foo/bar' => sub {
        my $self = shift;
        $self->res->code(200);
        $self->res->body('Yea baby!');
    };

    shagadelic;

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
