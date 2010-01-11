# Copyright (C) 2008-2010, Sebastian Riedel.

package Test::Mojo::Server;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use FindBin;
use IO::Socket::INET;
use Mojo::Command;
use Mojo::Home;

require Test::More;

use constant DEBUG => $ENV{MOJO_SERVER_DEBUG} || 0;

__PACKAGE__->attr([qw/command pid port/]);
__PACKAGE__->attr(executable => 'mojo');
__PACKAGE__->attr(home       => sub { Mojo::Home->new });
__PACKAGE__->attr(timeout    => 5);

__PACKAGE__->attr('_server');

# Hello, my name is Barney Gumble, and I'm an alcoholic.
# Mr Gumble, this is a girl scouts meeting.
# Is it, or is it you girls can't admit that you have a problem?
sub find_executable_ok {
    my ($self, $desc) = @_;
    my $path = $self->_find_executable;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::ok($path ? 1 : 0, $desc);
    return $path;
}

sub generate_port_ok {
    my ($self, $desc) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $port = $self->_generate_port;
    if ($port) {
        Test::More::ok(1, $desc);
        return $port;
    }

    Test::More::ok(0, $desc);
    return;
}

sub server_ok {
    my ($self, $desc) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Not running
    unless ($self->port) {
        return Test::More::ok(0, $desc);
    }

    # Test
    my $ok = $self->_check_server(1) ? 1 : 0;
    Test::More::ok($ok, $desc);
}

sub start_daemon_ok {
    my ($self, $desc) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Port
    my $port = $self->port || $self->_generate_port;
    return Test::More::ok(0, $desc) unless $port;

    # Path
    my $path = $self->_find_executable;
    return Test::More::ok(0, $desc) unless $path;

    # Prepare command
    $self->command(qq/$^X "$path" daemon --listen http:*:$port/);

    return $self->start_server_ok($desc);
}

sub start_daemon_prefork_ok {
    my ($self, $desc) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Port
    my $port = $self->port || $self->_generate_port;
    return Test::More::ok(0, $desc) unless $port;

    # Path
    my $path = $self->_find_executable;
    return Test::More::ok(0, $desc) unless $path;

    # Prepare command
    $self->command(qq/$^X "$path" daemon_prefork http:*:$port/);

    return $self->start_server_ok($desc);
}

sub start_server_ok {
    my ($self, $desc) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Start server
    my $pid = $self->_start_server;
    return Test::More::ok(0, $desc) unless $pid;

    # Wait for server
    my $timeout     = $self->timeout;
    my $time_before = time;
    while (!$self->_check_server) {

        # Timeout
        $timeout -= time - $time_before;
        if ($timeout <= 0) {
            $self->_stop_server;
            return Test::More::ok(0, $desc);
        }

        # Wait
        sleep 1;
    }

    # Done
    Test::More::ok(1, $desc);

    return $self->port;
}

sub start_server_untested_ok {
    my ($self, $desc) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Start server
    my $pid = $self->_start_server($desc);
    return Test::More::ok(0, $desc) unless $pid;

    # Done
    Test::More::ok(1, $desc);

    return $self->port;
}

sub stop_server_ok {
    my ($self, $desc) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Running?
    unless ($self->pid && kill 0, $self->pid) {
        return Test::More::ok(0, $desc);
    }

    # Debug
    if (DEBUG) {
        sysread $self->_server, my $buffer, 8192;
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
            Test::More::ok(1, $desc);
            return;
        }
    }
    Test::More::ok(0, $desc);
}

sub _check_server {
    my $self = shift;

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

sub _generate_port {
    my $self = shift;

    # Try ports
    my $port = 1 . int(rand 10) . int(rand 10) . int(rand 10) . int(rand 10);
    while ($port++ < 30000) {
        my $server = IO::Socket::INET->new(
            Listen    => 5,
            LocalAddr => '127.0.0.1',
            LocalPort => $port,
            Proto     => 'tcp'
        );
        return $self->port($port)->port;
    }

    return;
}

sub _start_server {
    my $self = shift;

    my $command = $self->command;
    warn "\nSERVER COMMAND: $command\n" if DEBUG;

    # Run server
    my $pid = open($self->{_server}, "$command |");
    $self->pid($pid);

    # Process started?
    return unless $pid;

    $self->_server->blocking(0);

    return $pid;
}

sub _stop_server {
    my $self = shift;

    # Kill server portable
    kill $^O eq 'MSWin32' ? 'KILL' : 'INT', $self->pid;
    close $self->_server;
    $self->pid(undef);
    $self->_server(undef);
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
    $server     = $server->command("lighttpd -D -f $config");

=head2 C<executable>

    my $script = $server->executable;
    $server    = $server->executable('mojo');

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

L<Test::Mojo::Server> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $server = Test::Mojo::Server->new;

=head2 C<find_executable_ok>

    my $path = $server->find_executable_ok;
    my $path = $server->find_executable_ok('executable found');

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
