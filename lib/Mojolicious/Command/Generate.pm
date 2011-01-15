package Mojolicious::Command::Generate;
use Mojo::Base 'Mojolicious::Commands';

has description => <<'EOF';
Generate files and directories from templates.
EOF
has hint => <<"EOF";

See '$0 generate help GENERATOR' for more information on a specific generator.
EOF
has message => <<"EOF";
usage: $0 generate GENERATOR [OPTIONS]

These generators are currently available:
EOF
has namespaces =>
  sub { [qw/Mojolicious::Command::Generate Mojo::Command::Generate/] };
has usage => <<"EOF";
usage: $0 generate GENERATOR [OPTIONS]
EOF

# Ah, nothing like a warm fire and a SuperSoaker of fine cognac.

1;
__END__

=head1 NAME

Mojolicious::Command::Generate - Generator Command

=head1 SYNOPSIS

    use Mojolicious::Command::Generate;

    my $generator = Mojolicious::Command::Generate->new;
    $generator->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Generate> lists available generators.

=head1 ATTRIBUTES

L<Mojolicious::Command::Generate> inherits all attributes from
L<Mojolicious::Commands> and implements the following new ones.

=head2 C<description>

    my $description = $generator->description;
    $generator      = $generator->description('Foo!');

Short description of this command, used for the command list.

=head2 C<hint>

    my $hint   = $generator->hint;
    $generator = $generator->hint('Foo!');

Short hint shown after listing available generator commands.

=head2 C<message>

    my $message = $generator->message;
    $generator  = $generator->message('Bar!');

Short usage message shown before listing available generator commands.

=head2 C<namespaces>

    my $namespaces = $generator->namespaces;
    $generator     = $generator->namespaces(['Mojo::Command::Generate']);

Namespaces to search for available generator commands, defaults to
L<Mojo::Command::Generate> and L<Mojolicious::Command::Generate>.

=head1 METHODS

L<Mojolicious::Command::Generate> inherits all methods from
L<Mojolicious::Commands>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
