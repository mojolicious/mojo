#!perl

use strict;
use warnings;

use Test::More tests => 1;

use Mojo;
use MojoX::Context;
use MojoX::Renderer;

my $test = "If requested format is not defined, return undef";
 my $c = MojoX::Context->new( app => Mojo->new ); 
 my $r = MojoX::Renderer->new( default_format => 'debug' );
    $r->handler({ debug  => sub {
                my ($ignore, $also_ignore, $output_ref) = @_;
                $$output_ref .= "output of debug handler";
            }});



 $c->stash->{partial} = 1;
 $c->stash->{format} = 'not_defined';
 my $output = $r->render($c);
 is($output, undef, $test);




