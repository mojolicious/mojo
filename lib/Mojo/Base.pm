# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Base;

use strict;
use warnings;

# No imports because we get subclassed, a lot!
require Carp;

# Kids, you tried your best and you failed miserably.
# The lesson is, never try.
sub new {
    my $class = shift;

    # Instantiate
    return bless
      exists $_[0] ? exists $_[1] ? {@_} : {%{$_[0]}} : {},
      ref $class || $class;
}

# Performance is very important for something as often used as accessors,
# so we optimize them by compiling our own code, don't be scared, we have
# tests for every single case
sub attr {
    my $class   = shift;
    my $attrs   = shift;
    my $default = shift;

    # Check for more arguments
    Carp::croak('Attribute generator called with too many arguments') if @_;

    # Shortcut
    return unless $class && $attrs;

    # Check default
    Carp::croak('Default has to be a code reference or constant value')
      if ref $default && ref $default ne 'CODE';

    # Allow symbolic references
    no strict 'refs';

    # Create attributes
    $attrs = ref $attrs eq 'ARRAY' ? $attrs : [$attrs];
    my $ws = '    ';
    for my $attr (@$attrs) {

        Carp::croak(qq/Attribute "$attr" invalid/)
          unless $attr =~ /^[a-zA-Z_]\w*$/;

        # Header
        my $code = "sub {\n";

        # No value
        $code .= "${ws}if (\@_ == 1) {\n";
        unless (defined $default) {

            # Return value
            $code .= "$ws${ws}return \$_[0]->{'$attr'};\n";
        }
        else {

            # Return value
            $code .= "$ws${ws}return \$_[0]->{'$attr'} ";
            $code .= "if exists \$_[0]->{'$attr'};\n";

            # Return default value
            $code .= "$ws${ws}return \$_[0]->{'$attr'} = ";
            $code .=
              ref $default eq 'CODE'
              ? '$default->($_[0])'
              : '$default';
            $code .= ";\n";
        }
        $code .= "$ws}\n";

        # Store value
        $code .= "$ws\$_[0]->{'$attr'} = \$_[1];\n";

        # Return invocant
        $code .= "${ws}return \$_[0];\n";

        # Footer
        $code .= '};';

        # We compile custom attribute code for speed
        *{"${class}::$attr"} = eval $code;

        # This should never happen (hopefully)
        Carp::croak("Mojo::Base compiler error: \n$code\n$@\n") if $@;

        # Debug mode
        if ($ENV{MOJO_BASE_DEBUG}) {
            warn "\nATTRIBUTE: $class->$attr\n";
            warn "$code\n\n";
        }
    }
}

1;
__END__

=head1 NAME

Mojo::Base - Minimal Base Class For Mojo Projects

=head1 SYNOPSIS

    package Car;
    use base 'Mojo::Base';

    __PACKAGE__->attr('driver');
    __PACKAGE__->attr('doors' => 2);
    __PACKAGE__->attr([qw/passengers seats/] => sub { 2 });

    package main;

    my $bmw = Car->new;
    print $bmw->doors;
    print $bmw->doors(5)->doors;

    my $mercedes = Car->new(driver => 'Sebastian');
    print $mercedes->passengers(7)->passengers;

=head1 DESCRIPTION

L<Mojo::Base> is a minimalistic base class for L<Mojo> projects.

=head1 METHODS

=head2 C<new>

    my $instance = BaseSubClass->new;
    my $instance = BaseSubClass->new(name => 'value');
    my $instance = BaseSubClass->new({name => 'value'});

=head2 C<attr>

    __PACKAGE__->attr('name');
    __PACKAGE__->attr([qw/name1 name2 name3/]);
    __PACKAGE__->attr(name => 'foo');
    __PACKAGE__->attr(name => sub { ... });
    __PACKAGE__->attr([qw/name1 name2 name3/] => 'foo');
    __PACKAGE__->attr([qw/name1 name2 name3/] => sub { ... });

=cut
