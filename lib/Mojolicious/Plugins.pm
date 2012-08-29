package Mojolicious::Plugins;
use Mojo::Base 'Mojo::EventEmitter';

# "Bender: Yeah, well... I'm gonna go build my own theme park, with blackjack
#          and hookers! In fact, forget the park!"
use Mojo::Util 'camelize';

has namespaces => sub { ['Mojolicious::Plugin'] };

sub emit_hook {
  my $self = shift;
  $_->(@_) for @{$self->subscribers(shift)};
  return $self;
}

sub emit_chain {
  my ($self, $name, @args) = @_;

  my $wrapper;
  for my $cb (reverse @{$self->subscribers($name)}) {
    my $next = $wrapper;
    $wrapper = sub { $cb->($next, @args) };
  }
  $wrapper->();

  return $self;
}

sub emit_hook_reverse {
  my $self = shift;
  $_->(@_) for reverse @{$self->subscribers(shift)};
  return $self;
}

sub load_plugin {
  my ($self, $name) = @_;

  # Try all namspaces
  my $class = $name =~ /^[a-z]/ ? camelize($name) : $name;
  for my $namespace (@{$self->namespaces}) {
    my $module = "${namespace}::$class";
    return $module->new if $self->_load($module);
  }

  # Full module name
  return $name->new if $self->_load($name);

  # Not found
  die qq{Plugin "$name" missing, maybe you need to install it?\n};
}

sub register_plugin {
  shift->load_plugin(shift)->register(shift, ref $_[0] ? $_[0] : {@_});
}

sub _load {
  my ($self, $module) = @_;

  # Load
  if (my $e = Mojo::Loader->new->load($module)) { ref $e ? die $e : return }

  # Module is a plugin
  return $module->isa('Mojolicious::Plugin') ? 1 : undef;
}

1;

=head1 NAME

Mojolicious::Plugins - Plugin manager

=head1 SYNOPSIS

  use Mojolicious::Plugins;

  my $plugins = Mojolicious::Plugin->new;
  push @{$plugins->namespaces}, 'MyApp::Plugin';

=head1 DESCRIPTION

L<Mojolicious::Plugins> is the plugin manager of L<Mojolicious>.

=head1 ATTRIBUTES

L<Mojolicious::Plugins> implements the following attributes.

=head2 C<namespaces>

  my $namespaces = $plugins->namespaces;
  $plugins       = $plugins->namespaces(['Mojolicious::Plugin']);

Namespaces to load plugins from, defaults to L<Mojolicious::Plugin>.

  # Add another namespace to load plugins from
  push @{$plugins->namespaces}, 'MyApp::Plugin';

=head1 METHODS

L<Mojolicious::Plugins> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<emit_chain>

  $plugins = $plugins->emit_chain('foo');
  $plugins = $plugins->emit_chain(foo => 123);

Emit events as chained hooks.

=head2 C<emit_hook>

  $plugins = $plugins->emit_hook('foo');
  $plugins = $plugins->emit_hook(foo => 123);

Emit events as hooks.

=head2 C<emit_hook_reverse>

  $plugins = $plugins->emit_hook_reverse('foo');
  $plugins = $plugins->emit_hook_reverse(foo => 123);

Emit events as hooks in reverse order.

=head2 C<load_plugin>

  my $plugin = $plugins->load_plugin('some_thing');
  my $plugin = $plugins->load_plugin('SomeThing');
  my $plugin = $plugins->load_plugin('MyApp::Plugin::SomeThing');

Load a plugin from the configured namespaces or by full module name.

=head2 C<register_plugin>

  $plugins->register_plugin('some_thing', Mojolicious->new);
  $plugins->register_plugin('some_thing', Mojolicious->new, foo => 23);
  $plugins->register_plugin('some_thing', Mojolicious->new, {foo => 23});
  $plugins->register_plugin('SomeThing', Mojolicious->new);
  $plugins->register_plugin('SomeThing', Mojolicious->new, foo => 23);
  $plugins->register_plugin('SomeThing', Mojolicious->new, {foo => 23});
  $plugins->register_plugin('MyApp::Plugin::SomeThing', Mojolicious->new);
  $plugins->register_plugin(
    'MyApp::Plugin::SomeThing', Mojolicious->new, foo => 23);
  $plugins->register_plugin(
    'MyApp::Plugin::SomeThing', Mojolicious->new, {foo => 23});

Load a plugin from the configured namespaces or by full module name and run
C<register>, optional arguments are passed through.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
