package Mojo::LoaderException2;
use Mojo::Base -strict;

Mojo::LoaderException2_2::throw_error();

1;

package Mojo::LoaderException2_2;

use Carp 'croak';

sub throw_error {
  eval { Mojo::LoaderException2_3::throw_error() };
  croak $@ if $@;
}

# "Shoplifting is a victimless crime. Like punching someone in the dark."
package Mojo::LoaderException2_3;

use Carp 'croak';

sub throw_error {
  croak "Exception";
}

1;
