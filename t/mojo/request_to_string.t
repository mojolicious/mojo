use Mojo::Base -strict;

use Test::More;
use Mojo::Message::Response;

my $res = Mojo::Message::Response->new;
$res->code(204);
is $res->code(), 204, 'setting the code';
$res->body('whatever');
is $res->body(), 'whatever', 'setting the body';

# getting a string rendition
my $string = $res->to_string();
my ($status_line) = split /\s*\n/, $string;
is $status_line, 'HTTP/1.1 204 No Content',
   'status line fine in string rendition';

$res->code(200);
is $res->code(), 200, 'changing the code';

# getting the new string rendition, hopefully
$string = $res->to_string();
($status_line) = split /\s*\n/, $string;
is $status_line, 'HTTP/1.1 200 OK',
   'status line changed in string rendition';

done_testing();
