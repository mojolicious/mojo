# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Base;

use strict;
use warnings;

# No imports because we get subclassed, a lot!
require Carp;
require Scalar::Util;

# Kids, you tried your best and you failed miserably.
# The lesson is, never try.
sub new {
    my $class = shift;

    # Instantiate
    return bless
      exists $_[0] ? exists $_[1] ? {@_} : $_[0] : {},
      ref $class || $class;
}

# Performance is very important for something as often used as accessors,
# so we optimize them by compiling our own code, don't be scared, we have
# tests for every single case
sub attr {
    my $class = shift;
    my $attrs = shift;

    # Shortcut
    return unless $class && $attrs;

    # Check arguments
    my $args;
    if (exists $_[1]) {
        my %args = (@_);
        $args = \%args;
    }
    else { $args = $_[0] }
    $args ||= {};

    my $chained = delete $args->{chained};
    my $default = delete $args->{default};
    my $weak    = delete $args->{weak};

    undef $args;

    # Allow symbolic references
    no strict 'refs';

    # Create attributes
    $attrs = ref $attrs eq 'ARRAY' ? $attrs : [$attrs];
    my $ws = '    ';
    for my $attr (@$attrs) {

        Carp::croak("Attribute '$attr' invalid")
          unless $attr =~ /^[a-zA-Z_]\w*$/;

        # Header
        my $code = "sub {\n";

        # Warning gets optimized away
        unless ($ENV{MOJO_BASE_OPTIMIZE}) {

            # Check invocant
            $code .= "${ws}Carp::croak(\'";
            $code .= 'Attribute has to be called on an object, not a class';
            $code .= "')\n  ${ws}unless ref \$_[0];\n";
        }

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
            $code .= ref $default eq 'CODE'
              ? '$default->($_[0])'
              : '$default';
            $code .= ";\n";
        }
        $code .= "$ws}\n";


        # Store argument optimized
        if (!$weak && !$chained) {
            $code .= "${ws}return \$_[0]->{'$attr'} = \$_[1];\n";
        }

        # Store argument the old way
        else {
            $code .= "$ws\$_[0]->{'$attr'} = \$_[1];\n";
        }

        # Weaken
        $code .= "${ws}Scalar::Util::weaken(\$_[0]->{'$attr'});\n" if $weak;

        # Return value or instance for chained/weak
        if ($chained || $weak) {
            $code .= "${ws}return ";
            $code .= $chained ? '$_[0]' : "\$_[0]->{'$attr'}";
            $code .= ";\n";
        }

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

Mojo::Base - Minimal Object System For Mojo Related Projects

=head1 SYNOPSIS

    package Car;
    use base 'Mojo::Base';

    __PACKAGE__->attr('driver');
    __PACKAGE__->attr('doors', default => 2);
    __PACKAGE__->attr([qw/passengers seats/],
        chained => 1,
        default => sub { 2 }
    );
    __PACKAGE__->attr('trailer', weak => 1);

    package main;
    use Car;

    my $bmw = Car->new;
    print $bmw->doors;
    print $bmw->passengers(5)->doors;

    my $mercedes = Car->new(driver => 'Sebastian');
    print $mercedes->passengers(7)->passengers;

    $mercedes->trailer(Trailer->new);

=head1 DESCRIPTION

L<Mojo::Base> is a base class containing a simple and fast object system
for Perl objects.
Main design goals are minimalism and staying out of your way.
The syntax is a bit like Ruby and the performance better than
L<Class::Accessor::Fast>.

Note that this is just an accessor generator, look at L<Moose> if you want
a more comprehensive object system.

For debugging you can set the C<MOJO_BASE_DEBUG> environment variable.

=head1 METHODS

=head2 C<new>

    my $instance = BaseSubClass->new;
    my $instance = BaseSubClass->new(name => 'value');
    my $instance = BaseSubClass->new({name => 'value'});

This class provides a standard object constructor.
You can pass arguments to it either as a hash or as a hashref, and they will
be set in the object's internal hash reference.

=head2 C<attr>

    __PACKAGE__->attr('name');
    __PACKAGE__->attr([qw/name1 name2 name3/]);
    __PACKAGE__->attr('name', chained => 1, default => 'foo');
    __PACKAGE__->attr(name => (chained => 1, default => 'foo'));
    __PACKAGE__->attr('name', {chained => 1, default => 'foo'});
    __PACKAGE__->attr([qw/name1 name2 name3/] => {
        chained => 1,
        default => 'foo'}
    );

The C<attr> method generates one or more accessors, depending on the number
of arguments, which work as both getters and setters.
You can modify the accessor behavior by passing arguments to C<attr> either
as a hash or a hashref.

Currently there are three options supported.

    chained: Whenever you call an attribute with arguments the instance
             is returned instead of the value.
    default: Default value for the attribute, can also be a coderef.
             Note that the default value is "lazy", which means it only
             gets assigned to the instance when the attribute has been
             called.
    weak:    Weakens the attribute value, use to avoid memory leaks with
             circular references.

=cut