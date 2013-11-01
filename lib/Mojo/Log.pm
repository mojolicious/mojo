package Mojo::Log;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Fcntl ':flock';
use Mojo::Util 'encode';

has handle => sub {

  # File
  if (my $path = shift->path) {
    croak qq{Can't open log file "$path": $!}
      unless open my $file, '>>', $path;
    return $file;
  }

  # STDERR
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

sub debug { shift->log(debug => @_) }
sub error { shift->log(error => @_) }
sub fatal { shift->log(fatal => @_) }

sub format {
  my ($self, $level, @lines) = @_;
  return encode 'UTF-8',
    '[' . localtime(time) . "] [$level] " . join("\n", @lines, '');
}

sub info { shift->log(info => @_) }

sub is_debug { shift->is_level('debug') }
sub is_error { shift->is_level('error') }
sub is_fatal { shift->is_level('fatal') }
sub is_info  { shift->is_level('info') }

sub is_level {
  my ($self, $level) = @_;
  return $LEVEL->{lc $level} >= $LEVEL->{$ENV{MOJO_LOG_LEVEL} || $self->level};
}

sub is_warn { shift->is_level('warn') }

sub log { shift->emit('message', lc(shift), @_) }

sub warn { shift->log(warn => @_) }

sub _message {
  my ($self, $level) = (shift, shift);

  return unless $self->is_level($level) && (my $handle = $self->handle);

  flock $handle, LOCK_EX;
  $handle->print($self->format($level, @_)) or croak "Can't write to log: $!";
  flock $handle, LOCK_UN;
}

1;

=encoding utf8

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

L<Mojo::Log> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 message

  $log->on(message => sub {
    my ($log, $level, @lines) = @_;
    ...
  });

Emitted when a new message gets logged.

  $log->unsubscribe('message');
  $log->on(message => sub {
    my ($log, $level, @lines) = @_;
    say "$level: ", @lines;
  });

=head1 ATTRIBUTES

L<Mojo::Log> implements the following attributes.

=head2 handle

  my $handle = $log->handle;
  $log       = $log->handle(IO::Handle->new);

Log filehandle used by default L</"message"> event, defaults to opening
L</"path"> or C<STDERR>.

=head2 level

  my $level = $log->level;
  $log      = $log->level('debug');

Active log level, defaults to C<debug>. Available log levels are C<debug>,
C<info>, C<warn>, C<error> and C<fatal>, in that order. Note that the
MOJO_LOG_LEVEL environment variable can override this value.

=head2 path

  my $path = $log->path
  $log     = $log->path('/var/log/mojo.log');

Log file path used by L</"handle">.

=head1 METHODS

L<Mojo::Log> inherits all methods from L<Mojo::EventEmitter> and implements
the following new ones.

=head2 new

  my $log = Mojo::Log->new;

Construct a new L<Mojo::Log> object and subscribe to L</"message"> event with
default logger.

=head2 debug

  $log = $log->debug('You screwed up, but that is ok.');
  $log = $log->debug('All', 'cool!');

Log debug message.

=head2 error

  $log = $log->error('You really screwed up this time.');
  $log = $log->error('Wow', 'seriously!');

Log error message.

=head2 fatal

  $log = $log->fatal('Its over...');
  $log = $log->fatal('Bye', 'bye!');

Log fatal message.

=head2 format

  my $msg = $log->format(debug => 'Hi there!');
  my $msg = $log->format(debug => 'Hi', 'there!');

Format log message.

=head2 info

  $log = $log->info('You are bad, but you prolly know already.');
  $log = $log->info('Ok', 'then!');

Log info message.

=head2 is_level

  my $bool = $log->is_level('debug');

Check log level.

=head2 is_debug

  my $bool = $log->is_debug;

Check for debug log level.

=head2 is_error

  my $bool = $log->is_error;

Check for error log level.

=head2 is_fatal

  my $bool = $log->is_fatal;

Check for fatal log level.

=head2 is_info

  my $bool = $log->is_info;

Check for info log level.

=head2 is_warn

  my $bool = $log->is_warn;

Check for warn log level.

=head2 log

  $log = $log->log(debug => 'This should work.');
  $log = $log->log(debug => 'This', 'too!');

Emit L</"message"> event.

=head2 warn

  $log = $log->warn('Dont do that Dave...');
  $log = $log->warn('No', 'really!');

Log warn message.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
