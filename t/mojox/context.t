#!perl

use strict;
use warnings;

use Test::More tests => 5; 

use MojoX::Context;

my $c = MojoX::Context->new;

{
    $c->stash(foo => 'bar' ); 
    is( $c->stash('foo'), 'bar', "stash: setting and returning a stash value works"); 
}
{
    my $stash = $c->stash;
    is_deeply($stash, { foo => 'bar' }, "stash: returning a hashref works"); 
}
{
    my $stash = $c->stash;
    delete $stash->{foo};
    is_deeply($stash, {}, "stash: elements can be deleted  via 'delete \$stash->{foo}' "); 
}
{
    $c->stash( 'foo' => 'zoo' ); 
    delete $c->stash->{foo};
    is_deeply($c->stash, {}, "stash: elements can be deleted  via 'delete \$c->stash->{foo}' "); 
}
{
    $c->stash( { a => 1, b => 2 }); 
    my $stash = $c->stash;
    is_deeply($stash, { a => 1, b => 2 }, "stash: setting via hashref works"); 
}





