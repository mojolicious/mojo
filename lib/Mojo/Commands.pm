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

These commands are currently available:
EOF
__PACKAGE__->attr(namespaces => sub { ['Mojo::Command'] });

# Aren't we forgetting the true meaning of Christmas?
# You know, the birth of Santa.
sub run {
    my ($self, $name, @args) = @_;

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
        $help ? $command->help : $command->run(@args);
        return $self;
    }

    # Try all namspaces
    my $commands = [];
    my $seen     = {};
    for my $namespace (@{$self->namespaces}) {

        # Search
        my $found = Mojo::Loader->search($namespace);

        for my $module (@$found) {

            # Load
            if (my $e = Mojo::Loader->load($module)) { die $e }

            # Seen
            my $command = $module;
            $command =~ s/^$namespace\:://;
            push @$commands, [$command => $module] unless $seen->{$command};
            $seen->{$command} = 1;
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
    ref $self ? $self->run(@args) : $self->new->run(@args);
}

1;
__END__

=head1 NAME

Mojo::Commands - Commands

=head1 SYNOPSIS

    use Mojo::Commands;

    my $commands = Mojo::Commands->new;
    $commands->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Commands> is the interactive command interface to the L<Mojo>
framework.

L<Mojo::Commands> calls commands, usually implemented as
L<Mojo::Command>, and is itself derived from C<Mojo::Command>. This
means that a command can be implemented based on L<Mojo::Commands> and
provide sub-commans (see L<Mojo::Command::Generate> for an example).

Follwing is a list of Interaciteve commands and short descriptions in Mojolicious:

=over 4

=item * B<overview and help>

    mojo[licious]
    mojo[licious] help

Prints a usage statement and lists available commands and short
descriptions (C<description> attribute).

    mojo[licious] help <command>

Prints short usage for the command (C<usage> attribute).

=item * B<code generation overview and help>

    mojo[licious] generate
    mojo[licious] generate help

Prints a usage statement, lists available generator commands and
prints the C<hint> attribute (how to get help on a generator).

    mojo[licious] generate help <generator>

Prints short usage for the command (C<usage> attribute) for the
generator specified.

=item * B<code generation>

    mojo[licious] generate app <App_name>

Generates application directory structure (scaffolding) for a full
Mojolicious application.

In the scaffolding, a subdirectory C<script> will be created with a
script named after the application. This script can be used to run the
application and to run other commands as described bellow.

    mojolicious generate lite_app <App_name>

Generates a minimalistic single-file contained L<Mojolicious::Lite>
application. The generated script contains the application and the
command interface, so it can be used to run the application and to run
other commands as described bellow.

=item * B<application startup>

    <script> daemon          <options>
    <script> daemon_prefork  <options>
    <script> cgi             <options>
    <script> fastcgi         <options>

Start the application with a stand-alone HTTP 1.1 backend, a prefork
HTTP 1.1 backend, a CGI (where the application handles a single
request and quites) or a FASTCGI backend (where the application runs persistently).

See application help for options.

Note that there is no command for running under C<mod_perl>, you need
L<Mojo::Apache2> (possibly outdated) from CPAN for that.

=item * B<application interaction>

   <script> get <URL> [--headers]

The C<get> command performs a complete request/response process,
actually starting the HTTP 1.1 server backend of the appliation and requesting
the URL with the built-in HTTP client, optionaly printing the headers
from the response.

   <script> test

Runs tests in the standard C<./t>. A full Mojolicious application
generated with the default generator conains an example test:
C<./t/basic.t>.

=item * B<general info and services>

   <script> version
   <script> generate makfile
   <script> generate psgi

Reports the versions of modules used, generates a C<Makefile.PL> and a
C<.psgi> file (Perl Web Server Gateway Interface description) for the
application.

=back


=head1 ATTRIBUTES

L<Mojo::Commands> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<message>

    my $message  = $commands->message;
    $commands    = $commands->message('Hello World!');

Overview message to print when called with no command to
execute. Usually set to a short usage statement and a list of
available commands.

=head2 C<namespaces>

    my $namespaces = $commands->namespaces;
    $commands      = $commands->namespaces(['Mojo::Command']);

Namespaces to search for available commands.

=head1 METHODS

L<Mojo::Commands> inherits all methods from L<Mojo::Command> and implements
the following new ones.

=head2 C<run>

    $commands = $commands->run;
    $commands = $commands->run(@ARGV);

Loads the proper modules and executes the command. Also handles the C<help> request.

=head2 C<start>

    Mojo::Commands->start;
    Mojo::Commands->start(@ARGV);

Intializatizes the module and calls $self->run(@_ ? @_ : @ARGV) unless reloading.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Book>, L<http://mojolicious.org>.

=cut
