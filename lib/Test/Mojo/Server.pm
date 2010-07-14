# Copyright (C) 2008-2010, Sebastian Riedel.

package Test::Mojo::Server;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use FindBin;
use IO::Socket::INET;
use Mojo::Command;
use Mojo::IOLoop;
use Mojo::Home;

require Test::More;

use constant DEBUG => $ENV{MOJO_SERVER_DEBUG} || 0;

__PACKAGE__->attr([qw/command pid/]);
__PACKAGE__->attr(delay      => 1);
__PACKAGE__->attr(executable => 'mojo');
__PACKAGE__->attr(home       => sub { Mojo::Home->new });
__PACKAGE__->attr(port    => sub { Mojo::IOLoop->singleton->generate_port });
__PACKAGE__->attr(timeout => 5);

# Hello, my name is Barney Gumble, and I'm an alcoholic.
# Mr Gumble, this is a girl scouts meeting.
# Is it, or is it you girls can't admit that you have a problem?
sub find_executable_ok {
    my $self = shift;
    my $path = $self->_find_executable;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::ok($path ? 1 : 0, 'executable found');
    return $path;
}

sub generate_port_ok {
    my $self = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $port = Mojo::IOLoop->singleton->generate_port;
    if ($port) {
        Test::More::ok(1, 'port generated');
        return $port;
    }

    Test::More::ok(0, 'port generated');
    return;
}

sub server_ok {
    my $self = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Not running
    unless ($self->port) {
        return Test::More::ok(0, 'server still running');
    }

    # Test
    my $ok = $self->_check_server(1) ? 1 : 0;
    Test::More::ok($ok, 'server still running');
}

sub start_daemon_ok {
    my $self = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Port
    my $port = $self->port;
    return Test::More::ok(0, 'server started') unless $port;

    # Path
    my $path = $self->_find_executable;
    return Test::More::ok(0, 'server started') unless $path;

    # Prepare command
    $self->command([$^X, $path, 'daemon', '--listen', "http:\/\/*:$port"]);

    return $self->start_server_ok;
}

sub start_daemon_prefork_ok {
    my $self = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Port
    my $port = $self->port;
    return Test::More::ok(0, 'server started') unless $port;

    # Path
    my $path = $self->_find_executable;
    return Test::More::ok(0, 'server started') unless $path;

    # Prepare command
    $self->command(
        [$^X, $path, 'daemon_prefork', '--listen', "http:\/\/*:$port"]);

    return $self->start_server_ok;
}

sub start_server_ok {
    my $self = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Start server
    my $pid = $self->_start_server;
    return Test::More::ok(0, 'server started') unless $pid;

    # Wait for server
    my $timeout     = $self->timeout;
    my $time_before = time;
    while (!$self->_check_server) {

        # Timeout
        $timeout -= time - $time_before;
        if ($timeout <= 0) {
            $self->_stop_server;
            return Test::More::ok(0, 'server started');
        }

        # Wait
        sleep 1;
    }

    # Done
    Test::More::ok(1, 'server started');

    return $self->port;
}

sub start_server_untested_ok {
    my $self = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Start server
    my $pid = $self->_start_server;
    return Test::More::ok(0, 'server started') unless $pid;

    # Done
    Test::More::ok(1, 'server started');

    return $self->port;
}

sub stop_server_ok {
    my $self = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Running
    unless ($self->pid && kill 0, $self->pid) {
        return Test::More::ok(0, 'server stopped');
    }

    # Debug
    if (DEBUG) {
        sysread $self->{_server}, my $buffer, 8192;
        warn "\nSERVER STDOUT: $buffer\n";
    }

    # Stop server
    $self->_stop_server();

    # Give it a few seconds to stop
    foreach (1 .. $self->timeout) {
        if ($self->_check_server) {
            sleep 1;
        }
        else {
            Test::More::ok(1, 'server stopped');
            return;
        }
    }
    Test::More::ok(0, 'server stopped');
}

sub _check_server {
    my $self = shift;

    # Delay
    my $delay = $self->delay;
    sleep $delay if $delay;

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

    return;
}

sub _find_executable {
    my $self = shift;

    # Find
    my @base = File::Spec->splitdir($FindBin::Bin);
    my $name = Mojo::Command->new->class_to_path($self->home->app_class);
    my @uplevel;
    my $path;
    for (1 .. 5) {
        push @uplevel, '..';

        # App executable in script directory
        $path = File::Spec->catfile(@base, @uplevel, 'script', $name);
        last if -f $path;

        # Custom executable in script directory
        $path =
          File::Spec->catfile(@base, @uplevel, 'script', $self->executable);
        last if -f $path;
    }

    # Found
    return $path if -f $path;

    # Not found
    return;
}

sub _start_server {
    my $self = shift;

    # Command
    my $command = $self->command;
    my @command = ref $command eq 'ARRAY' ? @$command : $command;

    # Run server
    my $pid = open $self->{_server}, '-|', @command;
    $self->pid($pid);

    # Process started
    return unless $pid;

    $self->{_server}->blocking(0);

    return $pid;
}

sub _stop_server {
    my $self = shift;

    # Kill server portable
    kill $^O eq 'MSWin32' ? 'KILL' : 'INT', $self->pid;
    close $self->{_server};
    $self->pid(undef);
    delete $self->{_server};
}

1;
__END__

=head1 NAME

Test::Mojo::Server - Server Tests

=head1 SYNOPSIS

    use Test::Mojo::Server;

    my $server = Test::Mojo::Server->new;
    $server->start_daemon_ok;
    $server->stop_server_ok;

=head1 DESCRIPTION

L<Test::Mojo::Server> is a collection of testing helpers specifically for
developers of L<Mojo> server bindings.

=head1 ATTRIBUTES

L<Test::Mojo::Server> implements the following attributes.

=head2 C<command>

    my $command = $server->command;
    $server     = $server->command("/usr/sbin/httpd -X -f 'x.cfg'");
    $server     = $server->command(['/usr/sbin/httpd', '-X', '-f', 'x.cfg']);

Command for external server start.

=head2 C<delay>

    my $delay = $server->delay;
    $server   = $server->delay(2);

Time to wait between server checks in seconds, defaults to C<1>.

=head2 C<executable>

    my $script = $server->executable;
    $server    = $server->executable('mojo');

L<Mojo> executable name.

=head2 C<home>

    my $home = $server->home;
    $server  = $server->home(Mojo::Home->new);

Home for application.

=head2 C<pid>

    my $pid = $server->pid;

Process id for external server.

=head2 C<port>

    my $port = $server->port;
    $server  = $server->port(3000);

Server port.

=head2 C<timeout>

    my $timeout = $server->timeout;
    $server     = $server->timeout(5);

Timeout for external server startup.

=head1 METHODS

L<Test::Mojo::Server> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $server = Test::Mojo::Server->new;

Construct a new L<Test::Mojo::Server> object.

=head2 C<find_executable_ok>

    my $path = $server->find_executable_ok;

Try to find L<Mojo> executable.

=head2 C<generate_port_ok>

    my $port = $server->generate_port_ok;

=head2 C<server_ok>

    $server->server_ok;

Check if server is still running.

=head2 C<start_daemon_ok>

    my $port = $server->start_daemon_ok;

Start external L<Mojo::Server::Daemon> server.

=head2 C<start_daemon_prefork_ok>

    my $port = $server->start_daemon_prefork_ok;

Start external L<Mojo::Server::Daemon::Prefork> server.

=head2 C<start_server_ok>

    my $port = $server->start_server_ok;

Start external server.

=head2 C<start_server_untested_ok>

    my $port = $server->start_server_untested_ok;

Start external server without testing the port.

=head2 C<stop_server_ok>

    $server->stop_server_ok;

Stop external server.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
