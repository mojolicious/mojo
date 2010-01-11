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

        # Register
        my $plugin = $module->new->register($app, $args);

        # Done
        return $self;
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
    $self->$_(@_) for @{$self->hooks->{$name}};

    return $self;
}

sub run_hook_reverse {
    my $self = shift;

    # Shortcut
    my $name = shift;
    return $self unless $name;
    return unless $self->hooks->{$name};

    # Run
    $self->$_(@_) for reverse @{$self->hooks->{$name}};

    return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Plugins - Plugins

=head1 SYNOPSIS

    use Mojolicious::Plugins;

=head1 DESCRIPTION

L<Mojolicous::Plugins> is a container for L<Mojolicious> plugins.

=head2 ATTRIBUTES

L<Mojolicious::Plugins> implements the following attributes.

=head2 C<hooks>

    my $hooks = $plugins->hooks;
    $plugins  = $plugins->hooks({foo => [sub {...}]});

=head2 C<namespaces>

    my $namespaces = $plugins->namespaces;
    $plugins       = $plugins->namespaces(['Mojolicious::Plugin']);

=head1 METHODS

L<Mojolicious::Plugins> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<add_hook>

    $plugins = $plugins->add_hook(foo => sub {...});

=head2 C<load_plugin>

    $plugins = $plugins->load_plugin($app, 'something');
    $plugins = $plugins->load_plugin($app, 'something', foo => 23);
    $plugins = $plugins->load_plugin($app, 'something', {foo => 23});

=head2 C<run_hook>

    $plugins = $plugins->run_hook('foo');
    $plugins = $plugins->run_hook(foo => 123);

=head2 C<run_hook_reverse>

    $plugins = $plugins->run_hook_reverse('foo');
    $plugins = $plugins->run_hook_reverse(foo => 123);

=cut
