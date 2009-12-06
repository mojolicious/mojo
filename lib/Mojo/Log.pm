# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Log;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use IO::File;

__PACKAGE__->attr(
    handle => sub {
        my $self = shift;

        # Need a log file
        unless ($self->path) {
            binmode STDERR, ':utf8';
            return \*STDERR;
        }

        # Open
        my $file = IO::File->new;
        my $path = $self->path;
        $file->open(">> $path") or croak qq/Can't open log file "$path": $!/;

        # utf8
        binmode $file, ':utf8';

        return $file;
    }
);
__PACKAGE__->attr(level => 'debug');
__PACKAGE__->attr('path');

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
    return unless $level;

    # Check
    $level = lc $level;
    my $current = $ENV{MOJO_LOG_LEVEL} || $self->level;
    return $LEVEL->{$level} >= $LEVEL->{$current};
}

sub is_warn { shift->is_level('warn') }

sub log {
    my ($self, $level, @msgs) = @_;

    # Check log level
    $level = lc $level;
    return $self unless $level && $self->is_level($level);

    my $time = localtime(time);
    my $msgs = join "\n", @msgs;

    # Caller
    my ($pkg, $line) = (caller())[0, 2];
    ($pkg, $line) = (caller(1))[0, 2] if $pkg eq ref $self;

    # Write
    $self->handle->syswrite("$time $level $pkg:$line [$$]: $msgs\n");

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

=head2 C<level>

    my $level = $log->level;
    $log      = $log->level('debug');

=head2 C<path>

    my $path = $log->path
    $log     = $log->path('/var/log/mojo.log');

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

=head2 C<is_debug>

    my $is = $log->is_debug;

=head2 C<is_error>

    my $is = $log->is_error;

=head2 C<is_fatal>

    my $is = $log->is_fatal;

=head2 C<is_info>

    my $is = $log->is_info;

=head2 C<is_warn>

    my $is = $log->is_warn;

=head2 C<log>

    $log = $log->log(debug => 'This should work');

=head2 C<warn>

    $log = $log->warn('Dont do that Dave...');

=cut
