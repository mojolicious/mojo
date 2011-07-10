package Mojo::Resolver;
use Mojo::Base -base;

use List::Util 'first';
use Mojo::IOLoop;
use Mojo::URL;

use constant DEBUG => $ENV{MOJO_RESOLVER_DEBUG} || 0;

# "AF_INET6" requires Socket6 or Perl 5.12
use constant IPV6_AF_INET6 => eval { Socket::AF_INET6() }
  || eval { require Socket6 and Socket6::AF_INET6() };

# "inet_pton" requires Socket6 or Perl 5.12
BEGIN {

  # Socket
  if (defined &Socket::inet_pton) { *inet_pton = \&Socket::inet_pton }

  # Socket6
  elsif (eval { require Socket6 and defined &Socket6::inet_pton }) {
    *inet_pton = \&Socket6::inet_pton;
  }
}

# IPv6 DNS support requires "AF_INET6" and "inet_pton"
use constant IPV6 => defined IPV6_AF_INET6 && defined &inet_pton;

has ioloop => sub { Mojo::IOLoop->new };
has timeout => 3;

# DNS server (default to Google Public DNS)
my $SERVERS = ['8.8.8.8', '8.8.4.4'];

# Try to detect DNS server
if (-r '/etc/resolv.conf') {
  my $file = IO::File->new('< /etc/resolv.conf');
  my @servers;
  for my $line (<$file>) {

    # New DNS server
    if ($line =~ /^nameserver\s+(\S+)$/) {
      push @servers, $1;
      warn qq/DETECTED DNS SERVER ($1)\n/ if DEBUG;
    }
  }
  unshift @$SERVERS, @servers;
}

# User defined DNS server
unshift @$SERVERS, $ENV{MOJO_DNS_SERVER} if $ENV{MOJO_DNS_SERVER};

# Always start with first DNS server
my $CURRENT_SERVER = 0;

# DNS record types
my $DNS_TYPES = {
  '*'   => 0x00ff,
  A     => 0x0001,
  AAAA  => 0x001c,
  CNAME => 0x0005,
  MX    => 0x000f,
  NS    => 0x0002,
  PTR   => 0x000c,
  TXT   => 0x0010
};

# "localhost"
our $LOCALHOST = '127.0.0.1';

sub lookup {
  my ($self, $name, $cb) = @_;

  # "localhost"
  my $loop = $self->ioloop;
  return $loop->timer(0 => sub { shift->$cb($LOCALHOST) })
    if $name eq 'localhost';

  # IPv4
  $self->resolve(
    $name, 'A',
    sub {
      my ($self, $records) = @_;

      # Success
      my $result = first { $_->[0] eq 'A' } @$records;
      return $self->$cb($result->[1]) if $result;

      # IPv6
      $self->resolve(
        $name, 'AAAA',
        sub {
          my ($self, $records) = @_;

          # Success
          my $result = first { $_->[0] eq 'AAAA' } @$records;
          return $self->$cb($result->[1]) if $result;

          # Pass through
          $self->$cb();
        }
      );
    }
  );
}

# "I can't believe it! Reading and writing actually paid off!"
sub resolve {
  my ($self, $name, $type, $cb) = @_;

  # No lookup required or record type not supported
  my $ipv4 = $name =~ $Mojo::URL::IPV4_RE ? 1 : 0;
  my $ipv6   = IPV6 && $name =~ $Mojo::URL::IPV6_RE ? 1 : 0;
  my $t      = $DNS_TYPES->{$type};
  my $server = $self->servers;
  my $loop   = $self->ioloop;
  if (!$server || !$t || ($t ne $DNS_TYPES->{PTR} && ($ipv4 || $ipv6))) {
    $loop->timer(0 => sub { $self->$cb([]) });
    return $self;
  }

  # Request
  warn "RESOLVE $type $name ($server)\n" if DEBUG;
  my $timer;
  my $tx = int rand 0x10000;
  my $id = $loop->connect(
    address    => $server,
    port       => 53,
    proto      => 'udp',
    on_connect => sub {
      my ($loop, $id) = @_;

      # Header (one question with recursion)
      my $req = pack 'nnnnnn', $tx, 0x0100, 1, 0, 0, 0;

      # Reverse
      my @parts = split /\./, $name;
      if ($t eq $DNS_TYPES->{PTR}) {

        # IPv4
        if ($ipv4) { @parts = reverse 'arpa', 'in-addr', @parts }

        # IPv6
        elsif ($ipv6) {
          @parts = reverse 'arpa', 'ip6', split //, unpack 'H32',
            inet_pton(IPV6_AF_INET6, $name);
        }
      }

      # Query (Internet)
      for my $part (@parts) {
        $req .= pack 'C/a*', $part if defined $part;
      }
      $req .= pack 'Cnn', 0, $t, 0x0001;
      $loop->write($id => $req);
    },
    on_error => sub {
      my ($loop, $id) = @_;
      warn "FAILED $type $name ($server)\n" if DEBUG;
      $CURRENT_SERVER++;
      $loop->drop($timer) if $timer;
      $self->$cb([]);
    },
    on_read => sub {
      my ($loop, $id, $chunk) = @_;

      # Cleanup
      $loop->drop($id);
      $loop->drop($timer) if $timer;

      # Check answers
      my @packet = unpack 'nnnnnna*', $chunk;
      warn "ANSWERS $packet[3] ($server)\n" if DEBUG;
      return $self->$cb([]) unless $packet[0] eq $tx;

      # Questions
      my $content = $packet[6];
      for (1 .. $packet[2]) {
        my $n;
        do { ($n, $content) = unpack 'C/aa*', $content } while ($n ne '');
        $content = (unpack 'nna*', $content)[2];
      }

      # Answers
      my @answers;
      for (1 .. $packet[3]) {

        # Parse
        (my ($t, $ttl, $a), $content) =
          (unpack 'nnnNn/aa*', $content)[1, 3, 4, 5];
        my @answer = _parse_answer($t, $a, $chunk, $content);

        # No answer
        next unless @answer;

        # Answer
        push @answers, [@answer, $ttl];
        warn "ANSWER $answer[0] $answer[1]\n" if DEBUG;
      }
      $self->$cb(\@answers);
    }
  );

  # Timer
  $timer = $loop->timer(
    $self->timeout => sub {
      my $loop = shift;
      warn "RESOLVE TIMEOUT ($server)\n" if DEBUG;

      # Abort
      $CURRENT_SERVER++;
      $loop->drop($id);
      $self->$cb([]);
    }
  );

  return $self;
}

# "I wonder where Bart is, his dinner's getting all cold... and eaten."
sub servers {
  my $self = shift;

  # New servers
  if (@_) {
    @$SERVERS       = @_;
    $CURRENT_SERVER = 0;
    return $self;
  }

  # List all
  return @$SERVERS if wantarray;

  # Current server
  $CURRENT_SERVER = 0 unless $SERVERS->[$CURRENT_SERVER];
  return $SERVERS->[$CURRENT_SERVER];
}

# Answer helper for "resolve"
sub _parse_answer {
  my ($t, $a, $packet, $rest) = @_;

  # A
  if ($t eq $DNS_TYPES->{A}) { return A => join('.', unpack 'C4', $a) }

  # AAAA
  elsif ($t eq $DNS_TYPES->{AAAA}) {
    return AAAA => sprintf('%x:%x:%x:%x:%x:%x:%x:%x', unpack('n*', $a));
  }

  # TXT
  elsif ($t eq $DNS_TYPES->{TXT}) { return TXT => unpack('(C/a*)*', $a) }

  # Offset
  my $offset = length($packet) - length($rest) - length($a);

  # CNAME
  my $type;
  if ($t eq $DNS_TYPES->{CNAME}) { $type = 'CNAME' }

  # MX
  elsif ($t eq $DNS_TYPES->{MX}) {
    $type = 'MX';
    $offset += 2;
  }

  # NS
  elsif ($t eq $DNS_TYPES->{NS}) { $type = 'NS' }

  # PTR
  elsif ($t eq $DNS_TYPES->{PTR}) { $type = 'PTR' }

  # Domain name
  return $type => _parse_name($packet, $offset) if $type;

  # Not supported
  return;
}

# Domain name helper for "resolve"
sub _parse_name {
  my ($packet, $offset) = @_;

  # Elements
  my @elements;
  for (1 .. 128) {

    # Element length
    my $len = ord substr $packet, $offset++, 1;

    # Offset
    if ($len >= 0xc0) {
      $offset = (unpack 'n', substr $packet, ++$offset - 2, 2) & 0x3fff;
    }

    # Element
    elsif ($len) {
      push @elements, substr $packet, $offset, $len;
      $offset += $len;
    }

    # Zero length element (the end)
    else { return join '.', @elements }
  }

  return;
}

1;
__END__

=head1 NAME

Mojo::Resolver - Async IO DNS Resolver

=head1 SYNOPSIS

  use Mojo::Resolver;

=head1 DESCRIPTION

L<Mojo::Resolver> is a minimalistic async io stub resolver.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojo::Resolver> implements the following attributes.

=head2 C<ioloop>

  my $ioloop = $resolver->ioloop;
  $resolver  = $resolver->ioloop(Mojo::IOLoop->new);

Loop object to use for io operations, by default a L<Mojo::IOLoop> object
will be used.

=head2 C<timeout>

  my $timeout = $resolver->timeout;
  $resolver   = $resolver->timeout(5);

Maximum time in seconds a C<DNS> lookup can take, defaults to C<3>.

=head1 METHODS

L<Mojo::Resolver> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<servers>

  my @all     = $resolver->servers;
  my $current = $resolver->servers;
  $resolver   = $resolver->servers('8.8.8.8', '8.8.4.4');

IP addresses of C<DNS> servers used for lookups, defaults to the value of
C<MOJO_DNS_SERVER>, auto detection, C<8.8.8.8> or C<8.8.4.4>.

=head2 C<lookup>

  $resolver = $resolver->lookup('mojolicio.us' => sub {...});

Lookup C<IPv4> or C<IPv6> address for domain.

  $resolver->lookup('mojolicio.us' => sub {
    my ($loop, $address) = @_;
    print "Address: $address\n";
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<resolve>

  $resolver = $resolver->resolve('mojolicio.us', 'A', sub {...});

Resolve domain into C<A>, C<AAAA>, C<CNAME>, C<MX>, C<NS>, C<PTR> or C<TXT>
records, C<*> will query for all at once.
Since this is a "stub resolver" it depends on a recursive name server for DNS
resolution.

=head1 DEBUGGING

You can set the C<MOJO_RESOLVER_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_RESOLVER_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
