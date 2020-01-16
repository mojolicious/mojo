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
my $orig_like      = Test::More->can('like');

my(%call_counter, @is_deeply_expects, @fail_expects, @like_expects);
*Test::More::is_deeply = sub {
    $call_counter{is_deeply}++;
    die("is_deeply() called more times than we expect\n") unless(@is_deeply_expects);
    $orig_is_deeply->(\@_, shift(@is_deeply_expects), 'is_deeply() called correctly');
};
*Test::More::fail = sub (;$) {
    $call_counter{fail}++;
    die("fail() called more times than we expect\n") unless(@fail_expects);
    is($_[0], shift(@fail_expects), "fail() called correctly");
};
*Test::More::like = sub ($$;$) {
    $call_counter{like}++;
    die("like() called more times than we expect\n") unless(@like_expects);
    $orig_is_deeply->(\@_, shift(@like_expects), 'like() called correctly');
};

my $t = Test::Mojo->new;

json_is();
json_like();
done_testing();

sub json_is {
    note("json_is tests");
    # we're going to test that is_deeply is called as we expect each time.
    # we'll also test that it's called the expected number of times.
    %call_counter = (is_deeply => 0, fail => 0, like => 0);
    @is_deeply_expects = (
        [{ fruit => 'lemon' }, { fruit  => 'lemon' }, 'exact match for JSON Pointer ""'],
        ['lemon',              'lemon',               'exact match for JSON Pointer "/fruit"'],
        [{ fruit => 'lemon' }, { fruit  => 'bat' },   'exact match for JSON Pointer ""'],
        ['lemon',              'bat',                 'exact match for JSON Pointer "/fruit"'],
        [{ fruit => 'lemon' }, { animal => 'bat' },   'exact match for JSON Pointer ""'],
        [{ fruit => 'lemon' }, { animal => 'bat' },   'user supplied description for is_deeply'],
    );
    @fail_expects = (
        'exact match for JSON Pointer "/animal"',
        'user supplied description for fail',
    );
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
    $t->get_ok('/testdata')->json_is({ animal   => 'bat' });
    $t->get_ok('/testdata')->json_is( '/animal' => 'bat' );
    
    # the surprising '' is because Test::Mojo assumes that two args means pointer and
    # data. You *must* provide three args if you want it to notice a description. ''
    # is the pointer to the root of the document, the default if only one arg is supplied.
    $t->get_ok('/testdata')->json_is('', { animal   => 'bat' },
        "user supplied description for is_deeply");
    $t->get_ok('/testdata')->json_is('/animal' => 'bat',
        "user supplied description for fail");

    $orig_is_deeply->(
        \%call_counter,
        { is_deeply => 6, fail => 2, like => 0 },
        "is_deeply() and fail() called the right number of times"
    );
}

sub json_like {
    note("json_like tests");
    %call_counter = (like => 0, fail => 0, is_deeply => 0);
    @like_expects = (
        ['lemon', qr{mon}, 'similar match for JSON Pointer "/fruit"'],
        ['lemon', qr{mon}, 'Yes mon'],
        ['lemon', qr{Jose}, 'similar match for JSON Pointer "/fruit"'],
        ['lemon', qr{Jose}, 'No way'],
    );
    @fail_expects = (
        'similar match for JSON Pointer "/animal"',
        'totally Gothic'
    );
    # These should pass, calling like() each time
    $t->get_ok('/testdata')->json_like('/fruit', qr{mon});
    $t->get_ok('/testdata')->json_like('/fruit', qr{mon}, 'Yes mon');
    # These should fail, calling like() each time cos the pointer exists but data is wrong
    $t->get_ok('/testdata')->json_like('/fruit', qr{Jose});
    $t->get_ok('/testdata')->json_like('/fruit', qr{Jose}, 'No way');
    # These should fail, calling fail() each time cos the pointer doesn't exist
    $t->get_ok('/testdata')->json_like('/animal', qr{bat});
    $t->get_ok('/testdata')->json_like('/animal', qr{bat}, 'totally Gothic');

    $orig_is_deeply->(
        \%call_counter,
        { is_deeply => 0, fail => 2, like => 4 },
        "like() and fail() called the right number of times"
    );
}
