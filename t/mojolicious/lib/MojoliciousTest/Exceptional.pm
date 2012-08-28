package MojoliciousTest::Exceptional;
use Mojo::Base 'Mojolicious::Controller';

sub this_one_dies { die "doh!\n" }

sub this_one_might_die {
  die "double doh!\n" unless shift->req->headers->header('X-DoNotDie');
  1;
}

1;
