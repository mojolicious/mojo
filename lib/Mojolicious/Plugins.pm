package Mojolicious::Plugins;
use Mojo::Base -base;

use Mojo::Util 'camelize';

has hooks      => sub { {} };
has namespaces => sub { ['Mojolicious::Plugin'] };

# "Who would have thought Hell would really exist?
#  And that it would be in New Jersey?"
sub add_hook {
  my ($self, $name, $cb) = @_;
  return $self unless $name && $cb;
  $self->hooks->{$name} ||= [];
  push @{$self->hooks->{$name}}, $cb;
  return $self;
}

# "Also you have a rectangular object in your colon.
#  That's a calculator. I ate it to gain its power."
sub load_plugin {
  my ($self, $name) = @_;

  # DEPRECATED in Smiling Face With Sunglasses!
  my %special = (
    ep_render    => 'EPRenderer',
    epl_renderer => 'EPLRenderer',
    i18n         => 'I18N',
    json_config  => 'JSONConfig',
    pod_renderer => 'PODRenderer'
  );
  if (my $new = $special{$name}) {
    warn qq/Plugin "$name" is DEPRECATED in favor of "$new"!!!\n/;
    $name = $new;
  }

  # Module
  if ($name =~ /^[A-Z]/ && $self->_load($name)) { return $name->new }

  # Search plugin by name
  else {

    # Class
    my $class = $name;
    camelize $class if $class =~ /^[a-z]/;

    # Try all namspaces
    for my $namespace (@{$self->namespaces}) {
      my $module = "${namespace}::$class";
      return $module->new if $self->_load($module);
    }
  }

  # Not found
  die qq/Plugin "$name" missing, maybe you need to install it?\n/;
}

# "Let's see how crazy I am now, Nixon. The correct answer is very."
sub register_plugin {
  my $self = shift;
  my $name = shift;
  my $app  = shift;
  $self->load_plugin($name)->register($app, ref $_[0] ? $_[0] : {@_});
}

sub run_hook {
  my $self = shift;
  return $self unless my $name  = shift;
  return $self unless my $hooks = $self->hooks->{$name};
  for my $hook (@$hooks) { $hook->(@_) }
  return $self;
}

# "Everybody's a jerk. You, me, this jerk."
sub run_hook_reverse {
  my $self = shift;
  return $self unless my $name  = shift;
  return $self unless my $hooks = $self->hooks->{$name};
  for my $hook (reverse @$hooks) { $hook->(@_) }
  return $self;
}

sub _load {
  my ($self, $module) = @_;

  # Load
  if (my $e = Mojo::Loader->load($module)) {
    die $e if ref $e;
    return;
  }

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

L<Mojolicious::Plugins> is the plugin manager of L<Mojolicious>.
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

  my $plugin = $plugins->load_plugin('some_thing');
  my $plugin = $plugins->load_plugin('SomeThing');
  my $plugin = $plugins->load_plugin('MyApp::Plugin::SomeThing');

Load a plugin from the configured namespaces or by full module name.

=head2 C<register_plugin>

  $plugins->register_plugin('some_thing', $app);
  $plugins->register_plugin('some_thing', $app, foo => 23);
  $plugins->register_plugin('some_thing', $app, {foo => 23});
  $plugins->register_plugin('SomeThing', $app);
  $plugins->register_plugin('SomeThing', $app, foo => 23);
  $plugins->register_plugin('SomeThing', $app, {foo => 23});
  $plugins->register_plugin('MyApp::Plugin::SomeThing', $app);
  $plugins->register_plugin('MyApp::Plugin::SomeThing', $app, foo => 23);
  $plugins->register_plugin('MyApp::Plugin::SomeThing', $app, {foo => 23});

Load a plugin from the configured namespaces or by full module name and run
C<register>.
Optional arguments are passed to register.

=head2 C<run_hook>

  $plugins = $plugins->run_hook('foo');
  $plugins = $plugins->run_hook(foo => 123);

Runs a hook.

=head2 C<run_hook_reverse>

  $plugins = $plugins->run_hook_reverse('foo');
  $plugins = $plugins->run_hook_reverse(foo => 123);

Runs a hook in reverse order.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
