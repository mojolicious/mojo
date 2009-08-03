# Copyright (C) 2008-2009, Sebastian Riedel.

package LoaderTest;

use warnings;
use strict;

use base 'Mojo::Base';

# When I first heard that Marge was joining the police academy,
# I thought it would be fun and zany, like that movie Spaceballs.
# But instead it was dark and disturbing. Like that movie... Police Academy.
__PACKAGE__->attr('bananas', chained => 0);
__PACKAGE__->attr([qw/ears eyes/], default => sub {2});
__PACKAGE__->attr('figs', chained => 0, default => 0);
__PACKAGE__->attr('heads', {chained => 0, default => 1});
__PACKAGE__->attr('name', chained => 0);

1;
