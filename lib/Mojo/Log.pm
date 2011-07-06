package Mojo::Log;
use Mojo::Base -base;

use Carp 'croak';
use Fcntl ':flock';
use IO::File;

has handle => sub {
  my $self = shift;

  # Need a log file
  unless ($self->path) {
    binmode STDERR, ':utf8';
    return \*STDERR;
  }

  # Append to file
  my $path = $self->path;
  croak qq/Can't open log file "$path": $!/
    unless my $file = IO::File->new(">> $path");
  binmode $file, ':utf8';

  return $file;
};
has level => 'debug';
has 'path';

# Supported log level
my $LEVEL = {debug => 1, info => 2, warn => 3, error => 4, fatal => 5};

# "Yes, I got the most! I win X-Mas!"
sub debug { shift->log('debug', @_) }
sub error { shift->log('error', @_) }
sub fatal { shift->log('fatal', @_) }

sub format {
  my ($self, $level, @msgs) = @_;
  my $msgs = join "\n",
    map { utf8::decode $_ unless utf8::is_utf8 $_; $_ } @msgs;
  return '[' . localtime(time) . "] [$level] $msgs\n";
}

sub info { shift->log('info', @_) }

sub is_debug { shift->is_level('debug') }
sub is_error { shift->is_level('error') }
sub is_fatal { shift->is_level('fatal') }
sub is_info  { shift->is_level('info') }

sub is_level {
  my ($self, $level) = @_;
  return unless $level;
  $level = lc $level;
  my $current = $ENV{MOJO_LOG_LEVEL} || $self->level;
  return $LEVEL->{$level} >= $LEVEL->{$current};
}

sub is_warn { shift->is_level('warn') }

# "If The Flintstones has taught us anything,
#  it's that pelicans can be used to mix cement."
sub log {
  my ($self, $level, @msgs) = @_;

  # Check log level
  $level = lc $level;
  return $self unless $level && $self->is_level($level);

  # Lock
  my $handle = $self->handle;
  flock $handle, LOCK_EX;

  # Format and log messages
  $handle->syswrite($self->format($level, @msgs));

  # Unlock
  flock $handle, LOCK_UN;

  return $self;
}

sub warn { shift->log('warn', @_) }

1;
__END__

=head1 NAME

Mojo::Log - Simple Logger For Mojo

=head1 SYNOPSIS

  use Mojo::Log;

  # Create a logging object that will log to STDERR by default
  my $log = Mojo::Log->new;

  # Customize the log location and minimum log level
  my $log = Mojo::Log->new(
    path  => '/var/log/mojo.log',
    level => 'warn',
  );

  $log->debug("Why isn't this working?");
  $log->info("FYI: it happened again");
  $log->warn("This might be a problem");
  $log->error("Garden variety error");
  $log->fatal("Boom!");

=head1 DESCRIPTION

L<Mojo::Log> is a simple logger for L<Mojo> projects.

=head1 ATTRIBUTES

L<Mojo::Log> implements the following attributes.

=head2 C<handle>

  my $handle = $log->handle;
  $log       = $log->handle(IO::File->new);

Logfile handle.

=head2 C<level>

  my $level = $log->level;
  $log      = $log->level('debug');

Log level.

=head2 C<path>

  my $path = $log->path
  $log     = $log->path('/var/log/mojo.log');

Logfile path.

=head1 METHODS

L<Mojo::Log> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<debug>

  $log = $log->debug('You screwed up, but that is ok');

Log debug message.

=head2 C<error>

  $log = $log->error('You really screwed up this time');

Log error message.

=head2 C<fatal>

  $log = $log->fatal('Its over...');

Log fatal message.

=head2 C<format>

  my $message = $log->format('debug', 'Hi there!');
  my $message = $log->format('debug', 'Hi', 'there!');

Format log message.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<info>

  $log = $log->info('You are bad, but you prolly know already');

Log info message.

=head2 C<is_level>

  my $is = $log->is_level('debug');

Check log level.

=head2 C<is_debug>

  my $is = $log->is_debug;

Check for debug log level.

=head2 C<is_error>

  my $is = $log->is_error;

Check for error log level.

=head2 C<is_fatal>

  my $is = $log->is_fatal;

Check for fatal log level.

=head2 C<is_info>

  my $is = $log->is_info;

Check for info log level.

=head2 C<is_warn>

  my $is = $log->is_warn;

Check for warn log level.

=head2 C<log>

  $log = $log->log(debug => 'This should work');

Log a message.

=head2 C<warn>

  $log = $log->warn('Dont do that Dave...');

Log warn message.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
