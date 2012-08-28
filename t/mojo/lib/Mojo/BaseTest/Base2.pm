package Mojo::BaseTest::Base2;
use Mojo::Base 'Mojo::BaseTest::Base1';

has [qw(ears eyes)] => sub {2};
has coconuts => 0;

1;
