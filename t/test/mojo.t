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
    die("is_deeply() called more times than we expect\n") unless(@is_deeply_expects);
    $orig_is_deeply->(\@_, shift(@is_deeply_expects), 'is_deeply() called correctly');
};
my @fail_expects = (
    'exact match for JSON Pointer "/animal"'
);
*Test::More::fail = sub (;$) {
    $call_counter{fail}++;
    die("fail() called more times than we expect\n") unless(@fail_expects);
    is($_[0], shift(@fail_expects), "fail() called correctly");
};

my $t = Test::Mojo->new;

# these should Just Pass, calling is_deeply each time. Note that in @is_deeply_expects
# above the first two args passed to is_deeply should be the same
$t->get_ok('/testdata')->json_is({ fruit   => 'lemon' });
$t->get_ok('/testdata')->json_is( '/fruit' => 'lemon' );

# these should Just Fail, calling is_deeply each time. In @is_deeply_expects you can
# see that is_deeply is asked to compare different structures
$t->get_ok('/testdata')->json_is({ fruit   => 'bat' });
$t->get_ok('/testdata')->json_is( '/fruit' => 'bat' );

# the first of these will call is_deeply, the second will notice that there's nothing
# to compare (/animal doesn't exist in the JSON) so will call fail() instead to make
# sure is_deeply doesn't magic up an undef and whine misleadingly about that
# is_deeply, the second will just fail
$t->get_ok('/testdata')->json_is({ animal   => 'bat' });
$t->get_ok('/testdata')->json_is( '/animal' => 'bat' );

is($call_counter{is_deeply}, 5,
  "is_deeply() only called five times for six tests");
is($call_counter{fail},      1,
  "fail() called once (and only once!) when error was caught");

# sanity checks to make sure we respect the user's test descriptions
note("Repeat some of those but with a custom test description, make sure that is respected");
%call_counter = (is_deeply => 0, fail => 0);
@is_deeply_expects = (
    [{ fruit => 'lemon' }, { animal => 'bat' }, 'user supplied description for is_deeply'],
);
@fail_expects = ('user supplied description for fail');

# the surprising '' is because Test::Mojo assumes that two args means pointer and
# data. You *must* provide three args if you want it to notice a description. ''
# is the pointer to the root of the document, the default if only one arg is supplied.
$t->get_ok('/testdata')->json_is('', { animal   => 'bat' },
    "user supplied description for is_deeply");
$t->get_ok('/testdata')->json_is('/animal' => 'bat',
    "user supplied description for fail");
is($call_counter{is_deeply}, 1, "is_deeply() called once");
is($call_counter{fail},      1, "fail() called once");

done_testing();
