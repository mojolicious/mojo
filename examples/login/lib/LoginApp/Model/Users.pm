package LoginApp::Model::Users;

use strict;
use warnings;
use experimental qw(signatures);

use Mojo::Util qw(secure_compare);

my $USERS = {joel => 'las3rs', marcus => 'lulz', sebastian => 'secr3t'};

sub new ($class) { bless {}, $class }

sub check ($self, $user, $pass) {

  # Success
  return 1 if $USERS->{$user} && secure_compare $USERS->{$user}, $pass;

  # Fail
  return undef;
}

1;
