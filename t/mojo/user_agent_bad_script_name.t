BEGIN{ $0 = '[ bad $0 ]' }
use Test::More;

require_ok('Mojo::UserAgent');

done_testing();

