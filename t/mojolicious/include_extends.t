use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

my $t = Test::Mojo->new;

get '/' => 'main';

# When we include some template we want its content. So $stash->{'mojo.content'}
# shoould be localized.
# Without that when our main template *occasionally* has content with same name
# this will prevent the template we are inluding to generate its own
# Even if we include two templates which have contents with same name the first
# template will prevent following to generate right content. In large system
# things goes too wired and complex to debug
$t->get_ok('/')->status_is(200)
  ->content_is(<<CONTENT);
  MAIN

  BASE


  T1


  T2


CONTENT

done_testing();


__DATA__
@@ base.html.ep
% content test => begin
  BASE
% end
%= content 'test';
@@ t1.html.ep
% extends 'base';
% content test => begin
  T1
% end
@@ t2.html.ep
% extends 'base';
% content test => begin
  T2
% end
@@ main.html.ep
% content test => begin
  MAIN
% end
%= content 'test';
%= include 'base';
%= include 't1';
%= include 't2';
