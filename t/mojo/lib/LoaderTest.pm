# Copyright (C) 2008, Sebastian Riedel.

package LoaderTest;

use warnings;
use strict;

use base 'Mojo::Base';

# When I first heard that Marge was joining the police academy,
# I thought it would be fun and zany, like that movie Spaceballs.
# But instead it was dark and disturbing. Like that movie... Police Academy.
__PACKAGE__->attr('bananas');
__PACKAGE__->attr([qw/ears eyes/], default => sub {2}, chained => 1);
__PACKAGE__->attr('figs', default => 0);
__PACKAGE__->attr('friend', {weak    => 1});
__PACKAGE__->attr('heads',  {default => 1});
__PACKAGE__->attr('name');

1;
