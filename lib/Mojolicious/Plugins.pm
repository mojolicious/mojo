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

# Also you have a rectangular object in your colon.
# That's a calculator. I ate it to gain its power.
sub load_plugin {
    my ($self, $name) = @_;

    # Module
    if ($name =~ /^[A-Z]+/) { return $name->new if $self->_load($name) }

    # Search plugin by name
    else {

        # Class
        my $class = b($name)->camelize->to_string;

        # Try all namspaces
        for my $namespace (@{$self->namespaces}) {

            # Module
            my $module = "${namespace}::$class";

            # Load and register
            return $module->new if $self->_load($module);
        }
    }

    # Not found
    die qq/Plugin "$name" missing, maybe you need to install it?\n/;
}

# Let's see how crazy I am now, Nixon. The correct answer is very.
sub register_plugin {
    my $self = shift;
    my $name = shift;
    my $app  = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Register
    return $self->load_plugin($name)->register($app, $args);
}

sub run_hook {
    my $self = shift;

    # Shortcut
    my $name = shift;
    return $self unless $name;
    return unless $self->hooks->{$name};

    # DEPRECATED in Hot Beverage! (passing $self)
    for my $hook (@{$self->hooks->{$name}}) { $self->$hook(@_) }

    return $self;
}

# Everybody's a jerk. You, me, this jerk.
sub run_hook_reverse {
    my $self = shift;

    # Shortcut
    my $name = shift;
    return $self unless $name;
    return unless $self->hooks->{$name};

    # DEPRECATED in Hot Beverage! (passing $self)
    for my $hook (reverse @{$self->hooks->{$name}}) { $self->$hook(@_) }

    return $self;
}

sub _load {
    my ($self, $module) = @_;

    # Load
    my $e = Mojo::Loader->load($module);
    if (ref $e) { die $e }
    return if $e;

    # Module is a plugin
    return unless $module->can('new') && $module->can('register');
    return 1;
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

=head1 ATTRIBUTES

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
You can also add custom events by calling C<run_hook> and C<run_hook_reverse>
from your application.

=head2 C<load_plugin>

    my $plugin = $plugins->load_plugin('something');
    my $plugin = $plugins->load_plugin('Foo::Bar');

Load a plugin from the configured namespaces or by full module name.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<register_plugin>

    $plugins->register_plugin('something', $app);
    $plugins->register_plugin('something', $app, foo => 23);
    $plugins->register_plugin('something', $app, {foo => 23});
    $plugins->register_plugin('Foo::Bar', $app);
    $plugins->register_plugin('Foo::Bar', $app, foo => 23);
    $plugins->register_plugin('Foo::Bar', $app, {foo => 23});

Load a plugin from the configured namespaces or by full module name and run
C<register>.
Optional arguments are passed to register.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<run_hook>

    $plugins = $plugins->run_hook('foo');
    $plugins = $plugins->run_hook(foo => 123);

Runs a hook.

=head2 C<run_hook_reverse>

    $plugins = $plugins->run_hook_reverse('foo');
    $plugins = $plugins->run_hook_reverse(foo => 123);

Runs a hook in reverse order.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
