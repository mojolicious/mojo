use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;
use Mojo::JSON qw(false true);
use Mojolicious::Lite;

get '/testdata' => sub {
  my $c = shift;
  $c->render(json => { fruit => 'lemon' });
};

no warnings 'redefine';
my $orig_is_deeply = Test::More->can('is_deeply');
my %call_counter = (
    is_deeply => 0,
    fail      => 0,
);
my $fail_message;

# we're going to test that is_deeply is called as we expect each time.
# later we'll also test that it's called the expected number of times.
my @is_deeply_expects = (
    [{ fruit   => 'lemon' }, { fruit  => 'lemon' }, 'exact match for JSON Pointer ""'],
    ['lemon',                'lemon',               'exact match for JSON Pointer "/fruit"'],
    [{ fruit   => 'lemon' }, { fruit  => 'bat' },   'exact match for JSON Pointer ""'],
    ['lemon',                'bat',                 'exact match for JSON Pointer "/fruit"'],
    [{ fruit   => 'lemon' }, { animal => 'bat' },   'exact match for JSON Pointer ""'],
);
*Test::More::is_deeply = sub {
    $call_counter{is_deeply}++;
    $orig_is_deeply->(\@_, shift(@is_deeply_expects), 'is_deeply() called correctly');
};

*Test::More::fail = sub {
    $call_counter{fail}++;
    ok($_[0] eq 'no data for pointer /animal', "fail() called correctly");
};

my $t = Test::Mojo->new;

# these should Just Pass, calling is_deeply each time
$t->get_ok('/testdata')->json_is({ fruit   => 'lemon' });
$t->get_ok('/testdata')->json_is( '/fruit' => 'lemon' );

# these should Just Fail, calling is_deeply each time
$t->get_ok('/testdata')->json_is({ fruit   => 'bat' });
$t->get_ok('/testdata')->json_is( '/fruit' => 'bat' );

# these should whine about the data not existing. Neither should
# talk about 'undef'. The first will call is_deeply, the second
# will just fail
$t->get_ok('/testdata')->json_is({ animal   => 'bat' });
$t->get_ok('/testdata')->json_is( '/animal' => 'bat' );

is($call_counter{is_deeply}, 5,
  "is_deeply() only called five times for six tests");
is($call_counter{fail},      1,
  "fail() called once (and only once!) when error was caught");

done_testing();
