package Mojolicious::Commands;

use strict;
use warnings;

use base 'Mojo::Command';

use Getopt::Long qw/GetOptions :config pass_through/;
use Mojo::Loader;
use Mojo::Util qw/camelize decamelize/;

__PACKAGE__->attr(hint => <<"EOF");

These options are available for all commands:
    --home <path>   Path to your applications home directory, defaults to
                    the value of MOJO_HOME or auto detection.
    --mode <name>   Run mode of your application, defaults to the value of
                    MOJO_MODE or development.

See '$0 help COMMAND' for more information on a specific command.
EOF
__PACKAGE__->attr(message => <<"EOF");
usage: $0 COMMAND [OPTIONS]

Tip: CGI, FastCGI and PSGI environments can be automatically detected very
     often and work without commands.

These commands are currently available:
EOF
__PACKAGE__->attr(
    namespaces => sub { [qw/Mojolicious::Command Mojo::Command/] });

# Used by BEGIN
sub detect {
    my ($self, $guess) = @_;

    # Hypnotoad
    return 'hypnotoad' if defined $ENV{HYPNOTOAD_APP};

    # PSGI (Plack only for now)
    return 'psgi' if defined $ENV{PLACK_ENV};

    # CGI
    return 'cgi'
      if defined $ENV{PATH_INFO} || defined $ENV{GATEWAY_INTERFACE};

    # No further detection if we have a guess
    return $guess if $guess;

    # FastCGI (detect absence of WINDIR for Windows and USER for UNIX)
    return 'fastcgi' if !defined $ENV{WINDIR} && !defined $ENV{USER};

    # Nothing
    return;
}

# Command line options for MOJO_HOME and MOJO_MODE
BEGIN {
    GetOptions(
        'home=s' => sub { $ENV{MOJO_HOME} = $_[1] },
        'mode=s' => sub { $ENV{MOJO_MODE} = $_[1] }
    ) unless Mojolicious::Commands->detect;
}

# One day a man has everything, the next day he blows up a $400 billion
# space station, and the next day he has nothing. It makes you think.
sub run {
    my ($self, $name, @args) = @_;

    # Try to detect environment
    $name = $self->detect($name) unless $ENV{MOJO_NO_DETECT};

    # Run command
    if ($name && $name =~ /^\w+$/ && ($name ne 'help' || $args[0])) {

        # Help
        my $help = $name eq 'help' ? 1 : 0;
        $name = shift @args if $help;

        # Try all namespaces
        my $module;
        for my $namespace (@{$self->namespaces}) {

            # Generate module
            my $camelized = $name;
            camelize $camelized;
            my $try = "$namespace\::$camelized";

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

    # Test
    return $self if $ENV{HARNESS_ACTIVE};

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
        decamelize $name;

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

1;
__END__

=head1 NAME

Mojolicious::Commands - Commands

=head1 SYNOPSIS

    use Mojolicious::Commands;

    # Command line interface
    my $commands = Mojolicious::Commands->new;
    $commands->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicous::Commands> is the interactive command line interface to the
L<Mojolicious> framework.
It will automatically detect available commands in the
L<Mojolicious::Command> namespace.

These commands are available by default.

=over 4

=item C<help>

    mojo
    mojo help

List available commands with short descriptions.

    mojo help <command>

List available options for the command with short descriptions.

=item C<cgi>

    mojo cgi
    script/myapp cgi

Start application with CGI backend.

=item C<daemon>

    mojo cgi
    script/myapp daemon

Start application with standalone HTTP 1.1 server backend.

=item C<fastcgi>

    mojo fastcgi
    script/myapp fastcgi

Start application with FastCGI backend.

=item C<generate>

    mojo generate
    mojo generate help

List available generator commands with short descriptions.

    mojo generate help <generator>

List available options for generator command with short descriptions.

=item C<generate app>

    mojo generate app <AppName>

Generate application directory structure for a fully functional
L<Mojolicious> application.

=item C<generate lite_app>

    mojo generate lite_app

Generate a fully functional L<Mojolicious::Lite> application.

=item C<generate makefile>

    mojo generate makefile

Generate C<Makefile.PL> file for application.

=item C<get>

   mojo get http://mojolicious.org
   script/myapp get /foo

Perform GET request to remote host or local application.

=item C<inflate>

    myapp.pl inflate

Turn embedded files from the C<DATA> section into real files.

=item C<routes>

    myapp.pl routes
    script/myapp routes

List application routes.

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

L<Mojolicious::Commands> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<hint>

    my $hint  = $commands->hint;
    $commands = $commands->hint('Foo!');

Short hint shown after listing available commands.

=head2 C<message>

    my $message = $commands->message;
    $commands   = $commands->message('Hello World!');

Short usage message shown before listing available commands.

=head2 C<namespaces>

    my $namespaces = $commands->namespaces;
    $commands      = $commands->namespaces(['Mojolicious::Commands']);

Namespaces to search for available commands, defaults to L<Mojo::Command> and
L<Mojolicious::Command>.

=head1 METHODS

L<Mojolicious::Commands> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<detect>

    my $env = $commands->detect;
    my $env = $commands->detect($guess);

Try to detect environment.

=head2 C<run>

    $commands->run;
    $commands->run(@ARGV);

Load and run commands.

=head2 C<start>

    Mojolicious::Commands->start;
    Mojolicious::Commands->start(@ARGV);

Start the command line interface.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
