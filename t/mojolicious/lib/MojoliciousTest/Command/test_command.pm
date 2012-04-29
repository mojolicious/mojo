package MojoliciousTest::Command::test_command;
use Mojo::Base 'Mojo::Command';

# "Who would have thought Hell would really exist?
#  And that it would be in New Jersey?"
has description => "Test command.\n";
has usage       => "usage: $0 test_command";

sub run { return 'works!' }

1;
