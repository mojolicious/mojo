#!/usr/bin/env perl
use Mojo::Base -strict;

# Use bundled libraries
use FindBin;
use lib "$FindBin::Bin/../lib";

# "After all this time, somebody else with one eye... who ISN'T a clumsy
#  carpenter or a kid with a BB gun."
use Mojo::IOLoop;

# Run as root only
die "Server needs to run as user root to be able to listen to port 843.\n"
  unless $> == 0 && $< == 0;

# Flash policy XML
my $xml = <<'EOF';
<?xml version="1.0"?>
<!DOCTYPE cross-domain-policy SYSTEM "/xml/dtds/cross-domain-policy.dtd">
<cross-domain-policy>
<site-control permitted-cross-domain-policies="master-only"/>
<allow-access-from domain="*" to-ports="*" secure="false"/>
</cross-domain-policy>
EOF

# Flash policy server
Mojo::IOLoop->listen(
  port    => 843,
  on_read => sub {
    my ($loop, $id) = @_;

    # Write XML
    $loop->write($id, $xml, sub { shift->drop($id) });
  }
) or die "Couldn't create listen socket!\n";

print "Starting server on port 843.\n";

# Start loop
Mojo::IOLoop->start;

1;
