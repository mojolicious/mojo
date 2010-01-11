# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Server::Daemon::Prefork;

use strict;
use warnings;

use base 'Mojo::Server::Daemon';
use bytes;

use Carp 'croak';
use Fcntl ':flock';
use IO::File;
use IO::Poll 'POLLIN';
use IO::Socket;
use POSIX qw/setsid WNOHANG/;

use constant DEBUG => $ENV{MOJO_SERVER_DEBUG} || 0;

__PACKAGE__->attr(cleanup_interval                      => 15);
__PACKAGE__->attr(idle_timeout                          => 30);
__PACKAGE__->attr(max_clients                           => 1);
__PACKAGE__->attr(max_servers                           => 100);
__PACKAGE__->attr(max_spare_servers                     => 10);
__PACKAGE__->attr([qw/min_spare_servers start_servers/] => 5);

__PACKAGE__->attr(_child_poll => sub { IO::Poll->new });
__PACKAGE__->attr([qw/_child_read _child_write _cleanup _spawn/]);
__PACKAGE__->attr(_children => sub { {} });

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 8192;

# Marge? Since I'm not talking to Lisa,
# would you please ask her to pass me the syrup?
# Dear, please pass your father the syrup, Lisa.
# Bart, tell Dad I will only pass the syrup if it won't be used on any meat
# product.
# You dunkin' your sausages in that syrup homeboy?
# Marge, tell Bart I just want to drink a nice glass of syrup like I do every
# morning.
# Tell him yourself, you're ignoring Lisa, not Bart.
# Bart, thank your mother for pointing that out.
# Homer, you're not not-talking to me and secondly I heard what you said.
# Lisa, tell your mother to get off my case.
# Uhhh, dad, Lisa's the one you're not talking to.
# Bart, go to your room.
sub accept_lock {
    my ($self, $blocking) = @_;

    # Idle
    if ($blocking) {
        $self->_child_write->syswrite("$$ idle\n")
          or croak "Can't write to parent: $!";
    }

    # Lock
    my $lock = $self->SUPER::accept_lock($blocking);

    # Busy
    if ($lock) {
        $self->_child_write->syswrite("$$ busy\n")
          or croak "Can't write to parent: $!";
    }

    return $lock;
}

sub child { shift->ioloop->start }

sub daemonize {
    my $self = shift;

    # Fork and kill parent
    croak "Can't fork: $!" unless defined(my $child = fork);
    exit 0 if $child;
    setsid() or croak "Can't start a new session: $!";

    # Close file handles
    open STDIN,  '</dev/null';
    open STDOUT, '>/dev/null';
    open STDERR, '>&STDOUT';

    # Change paths
    chdir '/';
    umask(0);
    $ENV{PATH} = '/bin:/sbin:/usr/bin:/usr/sbin';

    return $$;
}

sub parent {
    my $self = shift;

    # Prepare ioloop
    $self->prepare_ioloop;
}

sub run {
    my $self = shift;

    # PID file
    $self->prepare_pid_file;

    # No windows support
    die "Prefork daemon not available for Windows.\n" if $^O eq 'MSWin32';

    # Pipe for child communication
    pipe($self->{_child_read}, $self->{_child_write})
      or croak "Can't create pipe: $!";
    $self->_child_poll->mask($self->_child_read, POLLIN);

    # Parent signals
    my $done = 0;
    $SIG{INT} = $SIG{TERM} = sub { $done++ };
    $SIG{CHLD} = sub { $self->_reap_child };

    # Preload application
    $self->app;

    # Parent stuff
    $self->parent;

    $self->app->log->debug('Prefork parent started.') if DEBUG;

    # Prefork
    $self->_spawn_child for (1 .. $self->start_servers);

    # We try to make spawning and killing as smooth as possible
    $self->_cleanup(time + $self->cleanup_interval);
    $self->_spawn(1);

    # Mainloop
    while (!$done) {
        $self->_read_messages;
        $self->_manage_children;
    }

    # Kill em all
    $self->_kill_children;
    exit 0;
}

sub _cleanup_children {
    my $self = shift;
    for my $pid (keys %{$self->_children}) {
        delete $self->_children->{$pid} unless kill 0, $pid;
    }
}

sub _kill_children {
    my $self = shift;

    # Close pipe
    $self->_child_read(undef);

    # Kill all children
    while (%{$self->_children}) {

        # Die die die
        for my $pid (keys %{$self->_children}) {
            $self->app->log->debug("Killing prefork child $pid.") if DEBUG;
            kill 'TERM', $pid;
        }

        # Cleanup
        $self->_cleanup_children;

        # Wait
        sleep 1;
    }

    # Remove PID file
    unlink $self->pid_file;
}

sub _manage_children {
    my $self = shift;

    # Make sure we have enough idle processes
    my @idle = sort { $a <=> $b }
      grep { ($self->_children->{$_}->{state} || '') eq 'idle' }
      keys %{$self->_children};

    # Debug
    if (DEBUG) {
        my $idle  = @idle;
        my $total = keys %{$self->_children};
        my $spawn = $self->_spawn;
        $self->app->log->debug(
            "$idle of $total children idle, 1 listen (spawn $spawn).");
    }

    # Need more children
    if (@idle < $self->min_spare_servers) {
        for (1 .. $self->_spawn) {
            last if $self->max_servers <= keys %{$self->_children};
            $self->_spawn_child;
        }

        # Spawn counter
        $self->_spawn($self->_spawn * 2);
        $self->_spawn(8) if $self->_spawn > 8;
    }

    # Too many children
    elsif ((@idle > $self->max_spare_servers)) {

        # Kill one at a time
        my $timeout = time - $self->idle_timeout;
        for my $idle (@idle) {
            next unless $timeout > $self->_children->{$idle}->{time};
            kill 'HUP', $idle;
            $self->app->log->debug("Prefork child $idle stopped.") if DEBUG;

            # Spawn counter
            $self->_spawn($self->_spawn / 2) if $self->_spawn >= 2;

            last;
        }
    }

    # Remove dead child processes every 30 seconds
    if (time > $self->_cleanup) {
        $self->_cleanup_children;
        $self->_cleanup(time + $self->cleanup_interval);
    }
}

sub _read_messages {
    my $self = shift;

    # Read messages
    $self->_child_poll->poll(1);
    my @readers = $self->_child_poll->handles(POLLIN);
    my $buffer  = '';
    if (@readers) {
        return unless $self->_child_read->sysread(my $chunk, CHUNK_SIZE);
        $buffer .= $chunk;
    }

    # Parse messages
    my $pos = 0;
    while (length $buffer) {

        # Full message?
        $pos = index $buffer, "\n";
        last if $pos < 0;

        # Parse
        my $message = substr $buffer, 0, $pos + 1, '';
        next unless $message =~ /^(\d+)\ (\w+)\n$/;
        my $pid   = $1;
        my $state = $2;

        # Update status
        if ($state eq 'done') { delete $self->_children->{$pid} }
        else {
            $self->_children->{$pid} = {
                state => $state,
                time  => time
            };
        }
    }
}

sub _reap_child {
    my $self = shift;
    while ((my $child = waitpid(-1, WNOHANG)) > 0) {
        $self->app->log->debug("Prefork child $child died.") if DEBUG;
        delete $self->_children->{$child};
    }
}

sub _spawn_child {
    my $self = shift;

    # Fork
    croak "Can't fork: $!" unless defined(my $child = fork);

    # Parent takes care of child
    if ($child) {
        $self->_children->{$child} = {state => 'idle', time => time};
    }

    # Child
    else {

        # Prepare environment
        $self->prepare_lock_file;

        # Signal handlers
        $SIG{HUP} = $SIG{INT} = $SIG{TERM} = sub { exit 0 };
        $SIG{CHLD} = 'DEFAULT';
    }

    # Do child stuff
    unless ($child) {

        $self->app->log->debug('Prefork child started.') if DEBUG;

        # No need for child reader
        close($self->_child_read);
        $self->_child_poll(undef);

        # Parent will send a SIGHUP when there are too many children idle
        my $done = 0;
        $SIG{HUP} = sub {
            $self->ioloop->stop;
            $done++;
        };

        # User and group
        $self->setuidgid;

        # Spin
        while (!$done) { $self->child }

        # Done
        $self->_child_write->syswrite("$$ done\n")
          or croak "Can't write to parent: $!";
        $self->_child_write(undef);
        exit 0;
    }

    return $child;
}

1;
__END__

=head1 NAME

Mojo::Server::Daemon::Prefork - Prefork HTTP Server

=head1 SYNOPSIS

    use Mojo::Daemon::Prefork;

    my $daemon = Mojo::Daemon::Prefork->new;
    $daemon->port(8080);
    $daemon->run;

=head1 DESCRIPTION

L<Mojo::Daemon::Prefork> is a simple prefork HTTP server.

=head1 ATTRIBUTES

L<Mojo::Server::Daemon::Prefork> inherits all attributes from
L<Mojo::Server::Daemon> and implements the following new ones.

=head2 C<cleanup_interval>

    my $cleanup_interval = $daemon->cleanup_interval;
    $daemon              = $daemon->cleanup_interval(15);

=head2 C<idle_timeout>

    my $idle_timeout = $daemon->idle_timeout;
    $daemon          = $daemon->idle_timeout(30);

=head2 C<max_clients>

    my $max_clients = $daemon->max_clients;
    $daemon         = $daemon->max_clients(1);

=head2 C<max_servers>

    my $max_servers = $daemon->max_servers;
    $daemon         = $daemon->max_servers(100);

=head2 C<max_spare_servers>

    my $max_spare_servers = $daemon->max_spare_servers;
    $daemon               = $daemon->max_spare_servers(10);

=head2 C<min_spare_servers>

    my $min_spare_servers = $daemon->min_spare_servers;
    $daemon               = $daemon->min_spare_servers(5);

=head2 C<start_servers>

    my $start_servers = $daemon->start_servers;
    $daemon           = $daemon->start_servers(5);

=head1 METHODS

L<Mojo::Server::Daemon::Prefork> inherits all methods from
L<Mojo::Server::Daemon> and implements the following new ones.

=head2 C<accept_lock>

    my $lock = $daemon->accept_lock($blocking);

=head2 C<child>

    $daemon->child;

=head2 C<daemonize>

    $daemon->daemonize;

=head2 C<parent>

    $daemon->parent;

=head2 C<run>

    $daemon->run;

=cut
