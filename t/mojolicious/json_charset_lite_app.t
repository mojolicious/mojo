use Mojo::Base -strict;

BEGIN {$ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll'}

use Test::Mojo;
use Test::More;
use Mojo::ByteStream qw(b);
use Mojolicious::Lite;

my $ascii = 'abc';
my $yatta = 'やった';
my $yatta_sjis = b($yatta)->encode('shift_jis')->to_string;
my $miyagawa = '宮川';
my $miyagawa_jp = b($miyagawa)->encode('euc-jp')->to_string;
my $hola = "áèñ";
my $hola_latin1 = "\x{e1}\x{e8}\x{f1}";

get '/' => [ format => [ $yatta ] ] => { format => undef } => 'index';

post '/' => sub {
    my $c = shift;
    $c->render(text => "foo: " . $c->param('foo'));
};

get '/ascii' => sub {
    my $c = shift;
    $c->render(json => { test => $ascii })
};

get '/unicode' => sub {
    my $c = shift;
    $c->render(json => { test => $yatta })
};

get '/shift_jis' => sub {
    my $c = shift;
    $c->res->headers->content_type("application/json;charset=Shift_JIS");
    $c->render(data => qq({"test":"$yatta_sjis"}));
};

get '/euc_jp' => sub {
    my $c = shift;
    $c->res->headers->content_type("application/json;charset=euc-jp");
    $c->render(data => qq({"test":"$miyagawa_jp"}));
};

get '/latin1' => sub {
    my $c = shift;
    $c->res->headers->content_type("application/json;charset=ISO-8859-1");
    $c->stash(data => qq({"test":"$hola_latin1"}));
};

my $t = Test::Mojo->new;

$t->get_ok('/ascii')->status_is(200)->content_is('{"test":"abc"}');
$t->get_ok('/ascii')->status_is(200)->json_is('/test' => $ascii);
$t->get_ok('/unicode')->status_is(200)->content_type_is('application/json;charset=UTF-8')->json_is('/test' => $yatta);
$t->get_ok('/shift_jis')->status_is(200)->content_type_is('application/json;charset=Shift_JIS')->json_is('/test' => $yatta);
$t->get_ok('/euc_jp')->status_is(200)->content_type_is('application/json;charset=euc-jp')->json_is('/test' => $miyagawa);
$t->get_ok('/latin1')->status_is(200)->content_type_is('application/json;charset=ISO-8859-1')->json_is('/test' => $hola);


done_testing();
