package Mojo::Log;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Fcntl ':flock';
use Mojo::Util 'encode';

has format => sub { \&_format };
has handle => sub {

  # STDERR
  return \*STDERR unless my $path = shift->path;

  # File
  croak qq{Can't open log file "$path": $!} unless open my $file, '>>', $path;
  return $file;
};
has history => sub { [] };
has level => 'debug';
has max_history_size => 10;
has 'path';

# Supported log levels
my %LEVEL = (debug => 1, info => 2, warn => 3, error => 4, fatal => 5);

sub append {
  my ($self, $msg) = @_;

  return unless my $handle = $self->handle;
  flock $handle, LOCK_EX;
  $handle->print(encode('UTF-8', $msg)) or croak "Can't write to log: $!";
  flock $handle, LOCK_UN;
}

sub debug { shift->_log(debug => @_) }
sub error { shift->_log(error => @_) }
sub fatal { shift->_log(fatal => @_) }
sub info  { shift->_log(info  => @_) }

sub is_level { $LEVEL{pop()} >= $LEVEL{$ENV{MOJO_LOG_LEVEL} || shift->level} }

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(message => \&_message);
  return $self;
}

sub warn { shift->_log(warn => @_) }

sub _format {
  '[' . localtime(shift) . '] [' . shift() . '] ' . join "\n", @_, '';
}

sub _log { shift->emit('message', shift, @_) }

sub _message {
  my ($self, $level) = (shift, shift);

  return unless $self->is_level($level);

  my $max     = $self->max_history_size;
  my $history = $self->history;
  push @$history, my $msg = [time, $level, @_];
  shift @$history while @$history > $max;

  $self->append($self->format->(@$msg));
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
  $log->debug('Not sure what is happening here');
  $log->info('FYI: it happened again');
  $log->warn('This might be a problem');
  $log->error('Garden variety error');
  $log->fatal('Boom');

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

  $log->unsubscribe('message')->on(message => sub {
    my ($log, $level, @lines) = @_;
    say "$level: ", @lines;
  });

=head1 ATTRIBUTES

L<Mojo::Log> implements the following attributes.

=head2 format

  my $cb = $log->format;
  $log   = $log->format(sub {...});

A callback for formatting log messages.

  $log->format(sub {
    my ($time, $level, @lines) = @_;
    return "[Thu May 15 17:47:04 2014] [info] I ♥ Mojolicious\n";
  });

=head2 handle

  my $handle = $log->handle;
  $log       = $log->handle(IO::Handle->new);

Log filehandle used by default L</"message"> event, defaults to opening
L</"path"> or C<STDERR>.

=head2 history

  my $history = $log->history;
  $log        = $log->history([[time, 'debug', 'That went wrong']]);

The last few logged messages.

=head2 level

  my $level = $log->level;
  $log      = $log->level('debug');

Active log level, defaults to C<debug>. Available log levels are C<debug>,
C<info>, C<warn>, C<error> and C<fatal>, in that order. Note that the
C<MOJO_LOG_LEVEL> environment variable can override this value.

=head2 max_history_size

  my $size = $log->max_history_size;
  $log     = $log->max_history_size(5);

Maximum number of logged messages to store in L</"history">, defaults to C<10>.

=head2 path

  my $path = $log->path
  $log     = $log->path('/var/log/mojo.log');

Log file path used by L</"handle">.

=head1 METHODS

L<Mojo::Log> inherits all methods from L<Mojo::EventEmitter> and implements the
following new ones.

=head2 append

  $log->append("[Thu May 15 17:47:04 2014] [info] I ♥ Mojolicious\n");

Append message to L</"handle">.

=head2 debug

  $log = $log->debug('You screwed up, but that is ok');
  $log = $log->debug('All', 'cool');

Emit L</"message"> event and log C<debug> message.

=head2 error

  $log = $log->error('You really screwed up this time');
  $log = $log->error('Wow', 'seriously');

Emit L</"message"> event and log C<error> message.

=head2 fatal

  $log = $log->fatal('Its over...');
  $log = $log->fatal('Bye', 'bye');

Emit L</"message"> event and log C<fatal> message.

=head2 info

  $log = $log->info('You are bad, but you prolly know already');
  $log = $log->info('Ok', 'then');

Emit L</"message"> event and log C<info> message.

=head2 is_level

  my $bool = $log->is_level('debug');

Check active log L</"level">.

  # True
  $log->level('debug')->is_level('debug');
  $log->level('debug')->is_level('info');

  # False
  $log->level('info')->is_level('debug');
  $log->level('fatal')->is_level('warn');

=head2 new

  my $log = Mojo::Log->new;

Construct a new L<Mojo::Log> object and subscribe to L</"message"> event with
default logger.

=head2 warn

  $log = $log->warn('Dont do that Dave...');
  $log = $log->warn('No', 'really');

Emit L</"message"> event and log C<warn> message.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
