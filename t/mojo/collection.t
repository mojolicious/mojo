#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More tests => 20;

# "'What are you lookin at?' - the innocent words of a drunken child."
use_ok 'Mojo::Collection', 'c';

# each
my $collection = c(3, 2, 1);
is_deeply [$collection->each], [3, 2, 1], 'right elements';
$collection = c([3], [2], [1]);
my @results;
$collection->each(sub { push @results, $_->[0] });
is_deeply \@results, [3, 2, 1], 'right elements';
@results = ();
$collection->each(sub { push @results, shift->[0], shift });
is_deeply \@results, [3, 1, 2, 2, 1, 3], 'right elements';

# join
$collection = c(1, 2, 3);
is $collection->join(''),    '123',       'right result';
is $collection->join('---'), '1---2---3', 'right result';
is $collection->join("\n"),  "1\n2\n3",   'right result';
is $collection->join('/')->url_escape, '1%2F2%2F3', 'right result';
$collection = c(c(1, 2, 3), c(3, 2, 1));
is $collection->join(''), "1\n2\n33\n2\n1", 'right result';

# map
$collection = c(1, 2, 3);
is $collection->map(sub { $_ + 1 })->join(''), '234', 'right result';
is_deeply [@$collection], [1, 2, 3], 'right elements';
is $collection->map(sub { shift() + 2 })->join(''), '345', 'right result';
is_deeply [@$collection], [1, 2, 3], 'right elements';

# size
$collection = c();
is $collection->size, 0, 'right size';
$collection = c(undef);
is $collection->size, 1, 'right size';
$collection = c(23);
is $collection->size, 1, 'right size';
$collection = c([2, 3]);
is $collection->size, 1, 'right size';
$collection = c(5, 4, 3, 2, 1);
is $collection->size, 5, 'right size';

# until
$collection = c(1, 2, 3, 4, 5);
@results = ();
$collection->until(sub { push(@results, @_) && $_ > 3 });
is_deeply \@results, [1, 1, 2, 2, 3, 3, 4, 4], 'right elements';

# while
$collection = c(5, 4, 3, 2, 1);
@results = ();
$collection->while(sub { $_ > 3 && push(@results, @_) });
is_deeply \@results, [5, 1, 4, 2], 'right elements';
