# Copyright (C) 2008-2009, Sebastian Riedel.

package LoaderException2;

use warnings;
use strict;

LoaderException2_2::throw_error();

1;

package LoaderException2_2;
use Carp 'croak';

sub throw_error {
    eval {LoaderException2_3::throw_error()};
    croak $@ if $@;
}

package LoaderException2_3;
use Carp 'croak';

sub throw_error {
    croak "Exception";
}


1;
