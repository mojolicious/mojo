package Mojo::Log;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Fcntl ':flock';

# "Would you kindly shut your noise-hole?"
has handle => sub {
  my $self = shift;

  # File
  if (my $path = $self->path) {
    croak qq{Can't open log file "$path": $!}
      unless open my $file, '>>:utf8', $path;
    return $file;
  }

  # STDERR
  binmode STDERR, ':utf8';
  return \*STDERR;
};
has level => 'debug';
has 'path';

# Supported log level
my $LEVEL = {debug => 1, info => 2, warn => 3, error => 4, fatal => 5};

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(message => \&_message);
  return $self;
}

# "Yes, I got the most! I win X-Mas!"
sub debug { shift->log(debug => @_) }
sub error { shift->log(error => @_) }
sub fatal { shift->log(fatal => @_) }

sub format {
  my ($self, $level, @msgs) = @_;
  return '[' . localtime(time) . "] [$level] " . join("\n", @msgs) . "\n";
}

sub info { shift->log(info => @_) }

sub is_debug { shift->is_level('debug') }
sub is_error { shift->is_level('error') }
sub is_fatal { shift->is_level('fatal') }
sub is_info  { shift->is_level('info') }

sub is_level {
  my $self  = shift;
  my $level = lc shift;
  return $LEVEL->{$level} >= $LEVEL->{$ENV{MOJO_LOG_LEVEL} || $self->level};
}

sub is_warn { shift->is_level('warn') }

# "If The Flintstones has taught us anything,
#  it's that pelicans can be used to mix cement."
sub log {
  my $self  = shift;
  my $level = lc shift;
  return $self unless $self->is_level($level);
  return $self->emit(message => $level => @_);
}

sub warn { shift->log(warn => @_) }

sub _message {
  my $self = shift;
  return unless my $handle = $self->handle;
  flock $handle, LOCK_EX;
  croak "Can't write to log: $!"
    unless defined $handle->syswrite($self->format(@_));
  flock $handle, LOCK_UN;
}

1;

=head1 NAME

Mojo::Log - Simple logger

=head1 SYNOPSIS

  use Mojo::Log;

  # Log to STDERR
  my $log = Mojo::Log->new;

  # Customize log file location and minimum log level
  my $log = Mojo::Log->new(path => '/var/log/mojo.log', level => 'warn');

  # Log messages
  $log->debug('Why is this not working?');
  $log->info('FYI: it happened again.');
  $log->warn('This might be a problem.');
  $log->error('Garden variety error.');
  $log->fatal('Boom!');

=head1 DESCRIPTION

L<Mojo::Log> is a simple logger for L<Mojo> projects.

=head1 EVENTS

L<Mojo::Log> can emit the following events.

=head2 C<message>

  $log->on(message => sub {
    my ($log, $level, @messages) = @_;
    ...
  });

Emitted when a new message gets logged.

  $log->unsubscribe('message');
  $log->on(message => sub {
    my ($log, $level, @messages) = @_;
    say "$level: ", @messages;
  });

=head1 ATTRIBUTES

L<Mojo::Log> implements the following attributes.

=head2 C<handle>

  my $handle = $log->handle;
  $log       = $log->handle(IO::Handle->new);

Log file handle used by default C<message> event, defaults to opening C<path>
or C<STDERR>.

=head2 C<level>

  my $level = $log->level;
  $log      = $log->level('debug');

Active log level, defaults to the value of the C<MOJO_LOG_LEVEL> environment
variable or C<debug>.

These levels are currently available:

=over 2

=item C<debug>

=item C<info>

=item C<warn>

=item C<error>

=item C<fatal>

=back

=head2 C<path>

  my $path = $log->path
  $log     = $log->path('/var/log/mojo.log');

Log file path used by C<handle>.

=head1 METHODS

L<Mojo::Log> inherits all methods from L<Mojo::EventEmitter> and implements
the following new ones.

=head2 C<new>

  my $log = Mojo::Log->new;

Construct a new L<Mojo::Log> object and subscribe to C<message> event with
default logger.

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

=head2 C<info>

  $log = $log->info('You are bad, but you prolly know already');

Log info message.

=head2 C<is_level>

  my $success = $log->is_level('debug');

Check log level.

=head2 C<is_debug>

  my $success = $log->is_debug;

Check for debug log level.

=head2 C<is_error>

  my $success = $log->is_error;

Check for error log level.

=head2 C<is_fatal>

  my $success = $log->is_fatal;

Check for fatal log level.

=head2 C<is_info>

  my $success = $log->is_info;

Check for info log level.

=head2 C<is_warn>

  my $success = $log->is_warn;

Check for warn log level.

=head2 C<log>

  $log = $log->log(debug => 'This should work');

Emit C<message> event.

=head2 C<warn>

  $log = $log->warn('Dont do that Dave...');

Log warn message.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
