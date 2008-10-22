# Copyright (C) 2008, Sebastian Riedel.

package Test::Mojo::Server;

use strict;
use warnings;

use base 'Mojo::Base';

use constant DEBUG => $ENV{MOJO_SERVER_DEBUG} || 0;

use IO::Socket::INET;
use Mojo::Home;
use Test::Builder::Module;

__PACKAGE__->attr([qw/command pid port/], chained => 1);
__PACKAGE__->attr('home',
    chained => 1,
    default => sub { Mojo::Home->new }
);
__PACKAGE__->attr('timeout', chained => 1, default => sub { 5 });

# Hello, my name is Barney Gumble, and I'm an alcoholic.
# Mr Gumble, this is a girl scouts meeting.
# Is it, or is it you girls can't admit that you have a problem?
sub new {
    my $self = shift->SUPER::new();
    $self->{_tb} = Test::Builder->new;
    return $self;
}

sub generate_port_ok {
    my ($self, $desc) = @_;
    my $tb = $self->{_tb};

    my $port = $self->_generate_port;
    if ($port) {
        $tb->ok(1, $desc);
        return $port;
    }

    $tb->ok(0, $desc);
    return 0;
}

sub server_ok {
    my ($self, $desc) = @_;
    my $tb = $self->{_tb};

    # Not running
    unless ($self->port) {
        $tb->diag('No port specified for testing');
        return $tb->ok(0, $desc);
    }

    # Test
    my $ok = $self->_check_server(1) ? 1 : 0;
    $tb->ok($ok, $desc);
}

sub start_daemon_ok {
    my ($self, $desc) = @_;
    my $tb = $self->{_tb};

    # Port
    my $port = $self->port || $self->_generate_port;
    return $tb->ok(0, $desc) unless $port;

    # Path
    my $path = $self->home->executable;
    return $tb->ok(0, $desc) unless $path;

    # Prepare command
    $self->command(qq/$^X "$path" daemon $port/);

    return $self->start_server_ok($desc);
}

sub start_daemon_prefork_ok {
    my ($self, $desc) = @_;
    my $tb = $self->{_tb};

    # Port
    my $port = $self->port || $self->_generate_port;
    return $tb->ok(0, $desc) unless $port;

    # Path
    my $path = $self->home->executable;
    return $tb->ok(0, $desc) unless $path;

    # Prepare command
    $self->command(qq/$^X "$path" daemon_prefork $port/);
    

    return $self->start_server_ok($desc);
}

sub start_server_ok {
    my ($self, $desc) = @_;
    my $tb = $self->{_tb};

    # Start server
    my $pid = $self->_start_server;
    return $tb->ok(0, $desc) unless $pid;

    # Wait for server
    my $timeout = $self->timeout;
    my $time_before = time;
    while ($self->_check_server != 1) {

        # Timeout
        $timeout -= time - $time_before;
        if ($timeout <= 0) {
            $self->_stop_server;
            $tb->diag('Server timed out');
            return $tb->ok(0, $desc);
        }

        # Wait
        sleep 1;
    }

    # Done
    $tb->ok(1, $desc);

    return $self->port;
}

sub start_server_untested_ok {
    my ($self, $desc) = @_;
    my $tb = $self->{_tb};

    # Start server
    my $pid = $self->_start_server($desc);
    return $tb->ok(0, $desc) unless $pid;

    # Done
    $tb->ok(1, $desc);

    return $self->port;
}

sub stop_server_ok {
    my ($self, $desc) = @_;
    my $tb = $self->{_tb};

    # Running?
    unless ($self->pid && kill 0, $self->pid) {
        $tb->diag('Server not running');
        return $tb->ok(0, $desc);
    }

    # Debug
    if (DEBUG) {
        sysread $self->{_server}, my $buffer, 4096;
        warn "\nSERVER STDOUT: $buffer\n";
    }

    # Stop server
    $self->_stop_server();
    if ($self->_check_server) {
        $tb->diag("Can't stop server");
        $tb->ok(0, $desc);
    }
    else { $tb->ok(1, $desc) }
}

sub _check_server {
    my ($self, $diag) = @_;

    # Create socket
    my $server = IO::Socket::INET->new(
        Proto    => 'tcp',
        PeerAddr => 'localhost',
        PeerPort => $self->port
    );

    # Close socket
    if ($server) {
        close $server;
        return 1;
    }
    else {
        $self->{_tb}->diag("Server check failed: $!") if $diag;
        return 0
    }
}

sub _generate_port {
    my $self = shift;

    # Try ports
    my $port = 1 . int(rand 10) . int(rand 10) . int(rand 10) . int(rand 10);
    while ( $port++ < 30000 ) {
        my $server = IO::Socket::INET->new(
            Listen    => 5,
            LocalAddr => '127.0.0.1',
            LocalPort => $port,
            Proto     => 'tcp'
        );
        return $self->port($port)->port;
    }

    return 0;
}

sub _start_server {
    my $self = shift;
    my $tb = $self->{_tb};

    my $command = $self->command;
    warn "\nSERVER COMMAND: $command\n" if DEBUG;

    # Run server
    my $pid = open($self->{_server}, "$command |");
    $self->pid($pid);

    # Process started?
    unless ($pid) { 
        $tb->diag("Can't start server: $!");
        return 0;
    }

    $self->{_server}->blocking(0);

    return $pid;
}

sub _stop_server {
    my $self = shift;

    # Kill server
    kill 'INT', $self->pid;
    close $self->{_server};
    $self->pid(undef);
    undef $self->{_server};
}

1;
__END__

=head1 NAME

Test::Mojo::Server - Server Tests

=head1 SYNOPSIS

    use Mojo::Transaction;
    use Mojo::Test::Server;

    my $server = Test::Mojo::Server->new;
    $server->start_daemon_ok;
    $server->stop_server_ok;

=head1 DESCRIPTION

L<Mojo::Test::Server> is a test harness for server tests.

=head1 ATTRIBUTES

=head2 C<command>

    my $command = $server->command;
    $server     = $server->command("lighttpd -D -f $config");

=head2 C<home>

    my $home = $server->home;
    $server  = $server->home(Mojo::Home->new);

=head2 C<pid>

    my $pid = $server->pid;

=head2 C<port>

    my $port = $server->port;
    $server  = $server->port(3000);

=head2 C<timeout>

    my $timeout = $server->timeout;
    $server     = $server->timeout(5);

=head1 METHODS

L<Mojo::Test::Server> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $server = Mojo::Test::Server->new;

=head2 C<generate_port_ok>

    my $port = $server->generate_port_ok;
    my $port = $server->generate_port_ok('port test');

=head2 C<server_ok>

    $server->server_ok('server running');

=head2 C<start_daemon_ok>

    my $port = $server->start_daemon_ok('daemon test');

=head2 C<start_daemon_prefork_ok>

    my $port = $server->start_daemon_prefork_ok('prefork daemon test');

=head2 C<start_server_ok>

    my $port = $server->start_server_ok('server test');

=head2 C<start_server_untested_ok>

    my $port = $server->start_server_untested_ok('server test');

=head2 C<stop_server_ok>

    $server->stop_server_ok('server stopped');

=cut