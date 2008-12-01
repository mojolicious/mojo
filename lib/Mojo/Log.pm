# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Log;

use strict;
use warnings;

use base 'Mojo::Base';

use IO::File;

__PACKAGE__->attr(
    handle => (
        chained => 1,
        default => sub {
            my $self = shift;

            # Need a log file
            return \*STDERR unless $self->path;

            # Open
l           my $file = IO::File->new;
            my $path = $self->path;
            $file->open(">> $path")
              || die qq/Couldn't open log file "$path": $!/;
            return $file;
        }
    )
);
__PACKAGE__->attr(level => (chained => 1, default => 'debug'));
__PACKAGE__->attr(path => (chained => 1));

my $LEVEL = {debug => 1, info => 2, warn => 3, error => 4, fatal => 5};

# Yes, I got the most! I win X-Mas!
sub debug { shift->log('debug', @_) }
sub error { shift->log('error', @_) }
sub fatal { shift->log('fatal', @_) }
sub info  { shift->log('info',  @_) }

sub is_debug { shift->is_level('debug') }
sub is_error { shift->is_level('error') }
sub is_fatal { shift->is_level('fatal') }
sub is_info  { shift->is_level('info') }

sub is_level {
    my ($self, $level) = @_;

    # Shortcut
    return 0 unless $level;

    # Check
    $level = lc $level;
    my $current = $self->level;
    return $LEVEL->{$level} >= $LEVEL->{$current};
}

sub is_warn { shift->is_level('warn') }

sub log {
    my ($self, $level, @msgs) = @_;

    # Check log level
    $level = lc $level;
    return $self unless $level && $self->is_level($level);

    # Write
    my $time = localtime(time);
    my $msgs = join "\n", @msgs;
    my ($pkg, $line) = (caller())[0, 2];
    ($pkg, $line) = (caller(1))[0, 2] if $pkg eq ref $self;
    $self->handle->syswrite("[$time][$level][$pkg:$line] $msgs\n");

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

L<Mojo::Log> is a simple logger.
Include log statements at various levels throughout your code.
Then when you create the new logging object, set the minimum log level you
want to keep track off.
Set it low, to 'debug' for development, then higher in production.

=head1 ATTRIBUTES

=head2 C<handle>

    my $handle = $log->handle;
    $log       = $log->handle(IO::File->new);

Returns a IO handle used for logging if called without arguments.
Returns the invocant if called with arguments.
Any object with a C<syswrite> method will do.

=head2 C<level>

    my $level = $log->level;
    $log      = $log->level('debug');

Returns the minimum logging level if called without arguments.
Returns the invocant if called with arguments.
Valid value are: debug, info, warn, error and fatal.

=head2 C<path>

    my $path = $log->path
    $log     = $log->path('/var/log/mojo.log');

Returns the path of the log file to write to if called without arguments.
Returns the invocant if called with arguments.
This is used as the default location for C<handle>, STDERR will be used if no
path is provided.

=head1 METHODS

L<Mojo::Log> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<debug>

    $log = $log->debug('You screwed up, but thats ok');

=head2 C<error>

    $log = $log->error('You really screwed up this time');

=head2 C<fatal>

    $log = $log->fatal('Its over...');

=head2 C<info>

    $log = $log->info('You are bad, but you prolly know already');

=head2 C<is_level>

    my $is = $log->is_level('debug');

Returns true if the current logging level is at or above this level.

=head2 C<is_debug>

    my $is = $log->is_debug;

Returns true if the current logging level is at or above this level.

=head2 C<is_error>

    my $is = $log->is_error;

Returns true if the current logging level is at or above this level.

=head2 C<is_fatal>

    my $is = $log->is_fatal;

Returns true if the current logging level is at or above this level.

=head2 C<is_info>

    my $is = $log->is_info;

Returns true if the current logging level is at or above this level.

=head2 C<is_warn>

    my $is = $log->is_warn;

Returns true if the current logging level is at or above this level.

=head2 C<log>

    $log = $log->log(debug => 'This should work');

A long-hand alternative to the logging shortcuts above.

=head2 C<warn>

    $log = $log->warn('Dont do that Dave...');

=head1 SEE ALSO

L<Log::Dispatch> is an established logger with a similar interface, with many
more options for logging backends.

=cut
