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
    my $proto = shift;

    # Check attributes
    my $attrs;
    if (exists $_[1]) {
        my %attrs = (@_);
        $attrs = \%attrs;
    }
    else { $attrs = $_[0] }
    $attrs ||= {};

    # Create instance
    my $class = ref $proto || $proto;
    my $self = bless {}, $class;

    # Attributes
    for my $attr (keys %$attrs) {

        # Attribute
        if ($self->can($attr)) { $self->$attr($attrs->{$attr}) }

        # No attribute, pass through to instance hash
        else { $self->{$attr} = $attrs->{$attr} }
    }

    return $self;
}

# Performance is very important for something as often used as accessors,
# so we optimize them by compiling our own code
sub attr {
    my $class = shift;
    my $attrs = shift;

    # Shortcut
    return unless $class && $attrs;

    # Check options
    my $options;
    if (exists $_[1]) {
        my %options = (@_);
        $options = \%options;
    }
    else { $options = $_[0] }
    $options ||= {};

    Carp::croak('Option "filter" has to be a coderef')
      if ($options->{filter} && ref $options->{filter} ne 'CODE');

    my $chained = delete $options->{chained};
    my $default = delete $options->{default};
    my $filter  = delete $options->{filter};
    my $weak    = delete $options->{weak};

    undef $options;

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
        $code .= "${ws}my \$self = shift;\n";

        # No arguments
        $code .= "${ws}if (\@_ == 0) {\n";
        unless (defined $default) {

            # Return value
            $code .= "$ws${ws}return \$self->{'$attr'};\n";
        }
        else {

            # Return value
            $code .= "$ws${ws}return \$self->{'$attr'} ";
            $code .= "if exists \$self->{'$attr'};\n";

            # Return default value
            $code .= "$ws${ws}return \$self->{'$attr'} = ";
            $code .= ref $default eq 'CODE'
              ? '$default->($self)'
              : '$default';
            $code .= ";\n";
        }
        $code .= "$ws}\n";

        # Single argument
        $code .= "${ws}elsif (\@_ == 1) { \n";
        if ($filter) {

            # Filter and store argument
            $code .= "$ws${ws}local \$_ = \$_[0];\n";
            $code .= "$ws$ws\$self->{'$attr'} = \$filter->(\$self, \$_);\n";
        }
        else {

            # Store argument
            $code .= "$ws$ws\$self->{'$attr'} = \$_[0];\n";
        }
        $code .= "$ws}\n";

        # Multiple arguments
        $code .= "${ws}else {\n";
        if ($filter) {

            # Filter and store arguments
            $code .= "$ws${ws}local \$_ = \\\@_;\n";
            $code .= "$ws$ws\$self->{'$attr'} = \$filter->(\$self, \$_);\n";
        }
        else {

            # Store arguments
            $code .= "$ws$ws\$self->{'$attr'} = \\\@_;\n";
        }
        $code .= "$ws}\n";

        # Weaken
        $code .= "${ws}Scalar::Util::weaken(\$self->{'$attr'});\n" if $weak;

        # Return value or instance for chained
        $code .= "${ws}return ";
        $code .= $chained ? '$self' : "\$self->{'$attr'}";
        $code .= ";\n";

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

Mojo::Base - Once Upon A Midnight Dreary!

=head1 SYNOPSIS

    package Car;
    use base 'Mojo::Base';

    __PACKAGE__->attr('driver');
    __PACKAGE__->attr('doors',
        default => 2,
        filter  => sub { s/\D//g; $_ }
    );
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

L<Mojo::Base> is a universal base class containing simple and fast helpers
for object oriented Perl programming.

Main design goals are minimalism and staying out of your way.

The syntax is a bit like L<Moose> or Ruby and the performance close to
L<Class::Accessor::Fast>.
(Note that L<Mojo::Base> was never meant as a replacement for L<Moose>, both
are solutions to completely different problems.)

For debugging you can set the C<MOJO_BASE_DEBUG> environment variable.

=head1 METHODS

=head2 C<new>

    my $instance = BaseSubClass->new;
    my $instance = BaseSubClass->new(name => 'value');
    my $instance = BaseSubClass->new({name => 'value'});

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

Currently there are four options supported.

    chained: Whenever you call an attribute with arguments the instance
             is returned instead of the value.
    default: Default value for the attribute, can also be a coderef.
             Note that the default value is "lazy", which means it only
             gets assigned to the instance after the attribute has been
             called.
    filter:  Filters the value before assigning it to the instance,
             must be a coderef.
    weak:    Weakens the attribute value.

=cut