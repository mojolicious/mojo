use Mojo::Base -strict;

use Test::More;

local $0 = 'not a path to a file';

eval { require Mojo::Home };
is $@, '', 'no exception loading Mojo::Home when $0 is not a file';

done_testing();
