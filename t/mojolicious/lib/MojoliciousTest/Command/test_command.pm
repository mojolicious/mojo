package MojoliciousTest::Command::test_command;
use Mojo::Base 'Mojolicious::Command';

# "Who would have thought Hell would really exist?
#  And that it would be in New Jersey?"
sub run { return 'works!' }

1;
