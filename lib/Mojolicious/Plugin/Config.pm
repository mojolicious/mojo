package Mojolicious::Plugin::Config;
use Mojo::Base 'Mojolicious::Plugin';

use File::Basename 'basename';
use File::Spec::Functions 'file_name_is_absolute';
use Mojo::Util 'decamelize';

# "Who are you, my warranty?!"
sub load {
  my ($self, $file, $conf, $app) = @_;
  $app->log->debug(qq/Reading config file "$file"./);

  # Slurp UTF-8 file
  open my $handle, "<:encoding(UTF-8)", $file
    or die qq/Couldn't open config file "$file": $!/;
  my $content = do { local $/; <$handle> };

  # Process
  return $self->parse($content, $file, $conf, $app);
}

sub parse {
  my ($self, $content, $file, $conf, $app) = @_;

  # Run Perl code
  no warnings;
  die qq/Couldn't parse config file "$file": $@/
    unless my $config = eval "sub app { \$app }; $content";
  die qq/Config file "$file" did not return a hash reference.\n/
    unless ref $config eq 'HASH';

  return $config;
}

sub register {
  my ($self, $app, $conf) = @_;
  $conf ||= {};

  # Config file
  my $file = $conf->{file} || $ENV{MOJO_CONFIG};
  unless ($file) {
    $file = $ENV{MOJO_APP};

    # Class
    if ($file && !ref $file) { $file = decamelize $file }

    # File
    else { $file = basename($ENV{MOJO_EXE} || $0) }

    # Remove .pl and .t extentions
    $file =~ s/\.(?:pl|t)$//i;

    # Default extension
    $file .= '.' . ($conf->{ext} || 'conf');
  }

  # Mode specific config file
  my $mode;
  if ($file =~ /^(.*)\.([^\.]+)$/) { $mode = join '.', $1, $app->mode, $2 }

  # Absolute path
  $file = $app->home->rel_file($file) unless file_name_is_absolute $file;
  $mode = $app->home->rel_file($mode)
    if defined $mode && !file_name_is_absolute $mode;

  # Read config file
  my $config = {};
  if (-e $file) { $config = $self->load($file, $conf, $app) }

  # Check for default
  elsif ($conf->{default}) {
    $app->log->debug(qq/Config file "$file" missing, using default config./);
  }
  else { die qq/Config file "$file" missing, maybe you need to create it?\n/ }

  # Merge everything
  $config = {%$config, %{$self->load($mode, $conf, $app)}}
    if defined $mode && -e $mode;
  $config = {%{$conf->{default}}, %$config} if $conf->{default};
  my $current = $app->config;
  %$current = (%$current, %$config);
  $app->defaults(config => $current);

  return $current;
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::Config - Perl-ish configuration plugin

=head1 SYNOPSIS

  # myapp.conf
  {
    foo       => "bar",
    music_dir => app->home->rel_dir('music')
  };

  # Mojolicious
  my $config = $self->plugin('Config');

  # Mojolicious::Lite
  my $config = plugin 'Config';

  # Reads "myapp.conf" by default
  my $config = app->config;

  # Everything can be customized with options
  my $config = plugin Config => {file => '/etc/myapp.stuff'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::Config> is a Perl-ish configuration plugin. The
application object can be accessed via C<$app> or the C<app> function. You can
extend the normal configuration file C<myapp.conf> with C<mode> specific ones
like C<myapp.$mode.conf>. The code of this plugin is a good example for
learning to build new plugins.

=head1 OPTIONS

L<Mojolicious::Plugin::Config> supports the following options.

=head2 C<default>

  # Mojolicious::Lite
  plugin Config => {default => {foo => 'bar'}};

Default configuration, making configuration files optional.

=head2 C<ext>

  # Mojolicious::Lite
  plugin Config => {ext => 'stuff'};

File extension for generated configuration file names, defaults to C<conf>.

=head2 C<file>

  # Mojolicious::Lite
  plugin Config => {file => 'myapp.conf'};
  plugin Config => {file => '/etc/foo.stuff'};

Full path to configuration file, defaults to the value of the C<MOJO_CONFIG>
environment variable or C<myapp.conf> in the application home directory.

=head1 METHODS

L<Mojolicious::Plugin::Config> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<load>

  $plugin->load($file, $conf, $app);

Loads configuration file and passes the content to C<parse>.

  sub load {
    my ($self, $file, $conf, $app) = @_;
    ...
    return $self->parse($content, $file, $conf, $app);
  }

=head2 C<parse>

  $plugin->parse($content, $file, $conf, $app);

Parse configuration file.

  sub parse {
    my ($self, $content, $file, $conf, $app) = @_;
    ...
    return $hash;
  }

=head2 C<register>

  $plugin->register;

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
