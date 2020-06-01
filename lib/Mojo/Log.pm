package Mojo::Log;
use Mojo::Base 'Mojo::EventEmitter';

use Carp qw(croak);
use Fcntl qw(:flock);
use Mojo::File;
use Mojo::Util qw(encode);
use Time::HiRes qw(time);

has format => sub { shift->short ? \&_short : \&_default };
has handle => sub {

  # STDERR
  return \*STDERR unless my $path = shift->path;

  # File
  return Mojo::File->new($path)->open('>>');
};
has history          => sub { [] };
has level            => 'debug';
has max_history_size => 10;
has 'path';
has short => sub { $ENV{MOJO_LOG_SHORT} };

# Supported log levels
my %LEVEL = (debug => 1, info => 2, warn => 3, error => 4, fatal => 5);

# Systemd magic numbers
my %MAGIC = (debug => 7, info => 6, warn => 4, error => 3, fatal => 2);

sub append {
  my ($self, $msg) = @_;

  return unless my $handle = $self->handle;
  flock $handle, LOCK_EX;
  $handle->print(encode('UTF-8', $msg)) or croak "Can't write to log: $!";
  flock $handle, LOCK_UN;
}

sub debug { 1 >= $LEVEL{$_[0]->level} ? _log(@_, 'debug') : $_[0] }

sub context { $_[0]->new(parent => $_[0], context => $_[1], level => $_[0]->level) }

sub error { 4 >= $LEVEL{$_[0]->level} ? _log(@_, 'error') : $_[0] }
sub fatal { 5 >= $LEVEL{$_[0]->level} ? _log(@_, 'fatal') : $_[0] }
sub info  { 2 >= $LEVEL{$_[0]->level} ? _log(@_, 'info')  : $_[0] }

sub is_level { $LEVEL{pop()} >= $LEVEL{shift->level} }

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(message => \&_message);
  return $self;
}

sub warn { 3 >= $LEVEL{$_[0]->level} ? _log(@_, 'warn') : $_[0] }

sub _default {
  my ($time, $level) = (shift, shift);
  my ($s, $m, $h, $day, $month, $year) = localtime $time;
  $time = sprintf '%04d-%02d-%02d %02d:%02d:%08.5f', $year + 1900, $month + 1, $day, $h, $m,
    "$s." . ((split /\./, $time)[1] // 0);
  return "[$time] [$$] [$level] " . join "\n", @_, '';
}

sub _log {
  my ($self, $level) = (shift, pop);
  my @msgs = ref $_[0] eq 'CODE' ? $_[0]() : @_;
  $msgs[0] = "$self->{context} $msgs[0]" if $self->{context};
  ($self->{parent} || $self)->emit('message', $level, @msgs);
}

sub _message {
  my ($self, $level) = (shift, shift);

  my $max     = $self->max_history_size;
  my $history = $self->history;
  push @$history, my $msg = [time, $level, @_];
  shift @$history while @$history > $max;

  $self->append($self->format->(@$msg));
}

sub _short {
  my ($time, $level) = (shift, shift);
  my ($magic, $short) = ("<$MAGIC{$level}>", substr($level, 0, 1));
  return "${magic}[$$] [$short] " . join("\n$magic", @_) . "\n";
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

L<Mojo::Log> inherits all events from L<Mojo::EventEmitter> and can emit the following new ones.

=head2 message

  $log->on(message => sub {
    my ($log, $level, @lines) = @_;
    ...
  });

Emitted when a new message gets logged.

  $log->on(message => sub {
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
    return "[2018-11-08 14:20:13.77168] [28320] [info] I ♥ Mojolicious\n";
  });

=head2 handle

  my $handle = $log->handle;
  $log       = $log->handle(IO::Handle->new);

Log filehandle used by default L</"message"> event, defaults to opening L</"path"> or C<STDERR>.

=head2 history

  my $history = $log->history;
  $log        = $log->history([[time, 'debug', 'That went wrong']]);

The last few logged messages.

=head2 level

  my $level = $log->level;
  $log      = $log->level('debug');

Active log level, defaults to C<debug>. Available log levels are C<debug>, C<info>, C<warn>, C<error> and C<fatal>, in
that order.

=head2 max_history_size

  my $size = $log->max_history_size;
  $log     = $log->max_history_size(5);

Maximum number of logged messages to store in L</"history">, defaults to C<10>.

=head2 path

  my $path = $log->path
  $log     = $log->path('/var/log/mojo.log');

Log file path used by L</"handle">.

=head2 short

  my $bool = $log->short;
  $log     = $log->short($bool);

Generate short log messages without a timestamp, suitable for systemd, defaults to the value of the C<MOJO_LOG_SHORT>
environment variables.

=head1 METHODS

L<Mojo::Log> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 append

  $log->append("[2018-11-08 14:20:13.77168] [28320] [info] I ♥ Mojolicious\n");

Append message to L</"handle">.

=head2 context

  my $new = $log->context('[extra] [information]');

Construct a new child L<Mojo::Log> object that will include context information with every log message.

  # Log with context
  my $log = Mojo::Log->new;
  my $context = $log->context('[17a60115]');
  $context->debug('This is a log message with context information');
  $context->info('And another');

=head2 debug

  $log = $log->debug('You screwed up, but that is ok');
  $log = $log->debug('All', 'cool');
  $log = $log->debug(sub {...});

Emit L</"message"> event and log C<debug> message.

=head2 error

  $log = $log->error('You really screwed up this time');
  $log = $log->error('Wow', 'seriously');
  $log = $log->error(sub {...});

Emit L</"message"> event and log C<error> message.

=head2 fatal

  $log = $log->fatal('Its over...');
  $log = $log->fatal('Bye', 'bye');
  $log = $log->fatal(sub {...});

Emit L</"message"> event and log C<fatal> message.

=head2 info

  $log = $log->info('You are bad, but you prolly know already');
  $log = $log->info('Ok', 'then');
  $log = $log->info(sub {...});

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
  my $log = Mojo::Log->new(level => 'warn');
  my $log = Mojo::Log->new({level => 'warn'});

Construct a new L<Mojo::Log> object and subscribe to L</"message"> event with default logger.

=head2 warn

  $log = $log->warn('Dont do that Dave...');
  $log = $log->warn('No', 'really');
  $log = $log->warn(sub {...});

Emit L</"message"> event and log C<warn> message.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
