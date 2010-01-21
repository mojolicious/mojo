# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugins;

use strict;
use warnings;

use base 'Mojo::Base';

use Mojo::ByteStream 'b';

__PACKAGE__->attr(hooks      => sub { {} });
__PACKAGE__->attr(namespaces => sub { ['Mojolicious::Plugin'] });

# Who would have thought Hell would really exist?
# And that it would be in New Jersey?
sub add_hook {
    my ($self, $name, $cb) = @_;

    # Shortcut
    return $self unless $name && $cb;

    # Add
    $self->hooks->{$name} ||= [];
    push @{$self->hooks->{$name}}, $cb;

    return $self;
}

sub load_plugin {
    my $self = shift;

    # Application
    my $app = shift;
    return unless $app;

    # Class
    my $name = shift;
    return unless $name;
    my @class;
    for my $part (split /-/, $name) {

        # Junk
        next unless $part;

        # Camelize
        push @class, b($part)->camelize;
    }
    my $class = join '::', @class;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Try all namspaces
    for my $namespace (@{$self->namespaces}) {

        # Module
        my $module = "${namespace}::$class";

        # Load
        my $e = Mojo::Loader->load($module);
        if (ref $e) { die $e }
        next if $e;

        # Module is a plugin?
        next unless $module->can('new') && $module->can('register');

        # Register
        return $module->new->register($app, $args);
    }

    # Not found
    die qq/Plugin "$name" missing, maybe you need to install it?\n/;
}

sub run_hook {
    my $self = shift;

    # Shortcut
    my $name = shift;
    return $self unless $name;
    return unless $self->hooks->{$name};

    # Run
    for my $hook (@{$self->hooks->{$name}}) { $self->$hook(@_) }

    return $self;
}

sub run_hook_reverse {
    my $self = shift;

    # Shortcut
    my $name = shift;
    return $self unless $name;
    return unless $self->hooks->{$name};

    # Run
    for my $hook (reverse @{$self->hooks->{$name}}) { $self->$hook(@_) }

    return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Plugins - Plugins

=head1 SYNOPSIS

    use Mojolicious::Plugins;

=head1 DESCRIPTION

L<Mojolicous::Plugins> is the plugin manager of L<Mojolicious>.
In your application you will usually use it to load plugins.
To implement your own plugins see L<Mojolicious::Plugin> and the C<add_hook>
method below.

=head2 ATTRIBUTES

L<Mojolicious::Plugins> implements the following attributes.

=head2 C<hooks>

    my $hooks = $plugins->hooks;
    $plugins  = $plugins->hooks({foo => [sub {...}]});

Hash reference containing all hooks that have been registered by loaded
plugins.

=head2 C<namespaces>

    my $namespaces = $plugins->namespaces;
    $plugins       = $plugins->namespaces(['Mojolicious::Plugin']);

Namespaces to load plugins from.
You can add more namespaces to load application specific plugins.

=head1 METHODS

L<Mojolicious::Plugins> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<add_hook>

    $plugins = $plugins->add_hook(event => sub {...});

Hook into an event.
The following events are available.
(Note that C<after_*> hooks run in reverse order)

=over 4

=item before_dispatch

Runs before the dispatchers determines what action to run.
(Passed the default controller instance)

    $plugins->add_hook(before_dispatch => sub {
        my ($self, $c) = @_;
    });

=item after_dispatch

Runs after the dispatchers determines what action to run.
(Passed the default controller instance)

    $plugins->add_hook(after_dispatch => sub {
        my ($self, $c) = @_;
    });

=item after_static_dispatch

Runs after the static dispatcher determines if a static file should be
served. (Passed the default controller instance)

    $plugins->add_hook(after_static_dispatch => sub {
        my ($self, $c) = @_;
    })

=item after_build_tx

Runs right after the transaction is built and before the HTTP message gets
parsed.
One usage case would be upload progress bars.
(Passed the transaction instance)

    $plugins->add_hook(after_build_tx => sub {
        my ($self, $tx) = @_;
    })

=back

You could also add custom events by using C<run_hook> and C<run_hook_reverse>
in your application.

=head2 C<load_plugin>

    $plugins = $plugins->load_plugin($app, 'something');
    $plugins = $plugins->load_plugin($app, 'something', foo => 23);
    $plugins = $plugins->load_plugin($app, 'something', {foo => 23});

Load a plugin from the configured namespaces and run C<register>.
Optional arguments are passed to register.

=head2 C<run_hook>

    $plugins = $plugins->run_hook('foo');
    $plugins = $plugins->run_hook(foo => 123);

Runs a hook.

=head2 C<run_hook_reverse>

    $plugins = $plugins->run_hook_reverse('foo');
    $plugins = $plugins->run_hook_reverse(foo => 123);

Runs a hook in reverse order.

=cut
