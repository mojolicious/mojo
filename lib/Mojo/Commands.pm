# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Commands;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::ByteStream 'b';
use Mojo::Loader;

__PACKAGE__->attr(hint => <<"EOF");

See '$0 help COMMAND' for more information on a specific command.
EOF
__PACKAGE__->attr(message => <<"EOF");
usage: $0 COMMAND [OPTIONS]

Tip: CGI, FastCGI and PSGI environments can be automatically detected very
     often and work without commands.

These commands are currently available:
EOF
__PACKAGE__->attr(namespaces => sub { ['Mojo::Command'] });

# Aren't we forgetting the true meaning of Christmas?
# You know, the birth of Santa.
sub run {
    my ($self, $name, @args) = @_;

    # Try to detect environment
    $name = $self->_detect($name) unless $ENV{MOJO_NO_DETECT};

    # Run command
    if ($name && $name =~ /^\w+$/ && ($name ne 'help' || $args[0])) {

        # Help
        my $help = $name eq 'help' ? 1 : 0;
        $name = shift @args if $help;

        # Try all namespaces
        my $module;
        for my $namespace (@{$self->namespaces}) {

            # Generate module
            my $try = $namespace . '::' . b($name)->camelize;

            # Load
            if (my $e = Mojo::Loader->load($try)) {

                # Module missing
                next unless ref $e;

                # Real error
                die $e;
            }

            # Module is a command
            next unless $try->can('new') && $try->can('run');

            # Found
            $module = $try;
            last;
        }

        # Command missing
        die qq/Command "$name" missing, maybe you need to install it?\n/
          unless $module;

        # Run
        my $command = $module->new;
        return $help ? $command->help : $command->run(@args);
    }

    # Try all namespaces
    my $commands = [];
    my $seen     = {};
    for my $namespace (@{$self->namespaces}) {

        # Search
        if (my $modules = Mojo::Loader->search($namespace)) {
            for my $module (@$modules) {

                # Load
                if (my $e = Mojo::Loader->load($module)) { die $e }

                # Seen
                my $command = $module;
                $command =~ s/^$namespace\:://;
                push @$commands, [$command => $module]
                  unless $seen->{$command};
                $seen->{$command} = 1;
            }
        }
    }

    # Print overview
    print $self->message;

    # Make list
    my $list   = [];
    my $length = 0;
    foreach my $command (@$commands) {

        # Generate name
        my $name = $command->[0];
        $name = b($name)->decamelize;

        # Add to list
        my $l = length $name;
        $length = $l if $l > $length;
        push @$list, [$name, $command->[1]->new->description];
    }

    # Print list
    foreach my $command (@$list) {
        my $name        = $command->[0];
        my $description = $command->[1];
        my $padding     = ' ' x ($length - length $name);
        print "  $name$padding   $description";
    }

    # Hint
    print $self->hint;

    return $self;
}

sub start {
    my $self = shift;

    # Don't run commands if we are reloading
    return $self if $ENV{MOJO_COMMANDS_DONE};
    $ENV{MOJO_COMMANDS_DONE} ||= 1;

    # Arguments
    my @args = @_ ? @_ : @ARGV;

    # Run
    return ref $self ? $self->run(@args) : $self->new->run(@args);
}

sub _detect {
    my ($self, $name) = @_;

    # PSGI (Plack only for now)
    return 'psgi' if defined $ENV{PLACK_ENV};

    # No further detection if we have a name
    return $name if $name;

    # CGI
    return 'cgi'
      if defined $ENV{PATH_INFO} || defined $ENV{GATEWAY_INTERFACE};

    # FastCGI
    return 'fastcgi' unless defined $ENV{PATH};

    # Nothing
    return;
}

1;
__END__

=head1 NAME

Mojo::Commands - Commands

=head1 SYNOPSIS

    use Mojo::Commands;

    # Command line interface
    my $commands = Mojo::Commands->new;
    $commands->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Commands> is the interactive command line interface to the L<Mojo>
framework.
It will automatically detect available commands in the L<Mojo::Command>
namespace.
Commands are implemented by subclassing L<Mojo::Command>.

These commands are available by default.

=over 4

=item C<help>

    mojo
    mojo help

List available commands with short descriptions.

    mojo help <command>

List available options for the command with short descriptions.

=item C<generate>

    mojo generate
    mojo generate help

List available generator commands with short descriptions.

    mojo generate help <generator>

List available options for generator command with short descriptions.

=item C<generate app>

    mojo generate app <AppName>

Generate application directory structure for a fully functional L<Mojo>
application.

=item C<generate makefile>

    script/myapp generate makefile

Generate C<Makefile.PL> file for application.

=item C<generate psgi>

    script/myapp generate psgi

Generate C<myapp.psgi> file for application.

=item C<cgi>

    mojo cgi
    script/myapp cgi

Start application with CGI backend.

=item C<daemon>

    mojo cgi
    script/myapp daemon

Start application with standalone HTTP 1.1 server backend.

=item C<daemon_prefork>

    mojo daemon_prefork
    script/myapp daemon_prefork

Start application with preforking standalone HTTP 1.1 server backend.

=item C<fastcgi>

    mojo fastcgi
    script/myapp fastcgi

Start application with FastCGI backend.

=item C<get>

   mojo get http://mojolicious.org
   script/myapp get /foo

Perform GET request to remote host or local application.

=item C<test>

   mojo test
   script/myapp test
   script/myapp test t/foo.t

Runs application tests from the C<t> directory.

=item C<version>

    mojo version

List version information for installed core and optional modules, very useful
for debugging.

=back

=head1 ATTRIBUTES

L<Mojo::Commands> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<hint>

    my $hint  = $commands->hint;
    $commands = $commands->hint('Foo!');

Short hint shown after listing available commands.

=head2 C<message>

    my $message  = $commands->message;
    $commands    = $commands->message('Hello World!');

Short usage message shown before listing available commands.

=head2 C<namespaces>

    my $namespaces = $commands->namespaces;
    $commands      = $commands->namespaces(['Mojo::Command']);

Namespaces to search for available commands, defaults to L<Mojo::Command>.

=head1 METHODS

L<Mojo::Commands> inherits all methods from L<Mojo::Command> and implements
the following new ones.

=head2 C<run>

    $commands->run;
    $commands->run(@ARGV);

Load and run commands.

=head2 C<start>

    Mojo::Commands->start;
    Mojo::Commands->start(@ARGV);

Start the command line interface.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
