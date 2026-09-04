package Mojo::SSE;
use Mojo::Base -strict;

use Carp       qw(croak);
use Exporter   qw(import);
use Mojo::Util qw(decode encode);

our @EXPORT_OK = (qw(build_event parse_event));

my $SPLIT_RE = qr/(?:\x0d\x0a|(?<!\x0d)\x0a|\x0d(?!\x0a))/;

sub build_event {
  my $event = shift;

  my @data    = defined $event->{text}    ? split($SPLIT_RE, $event->{text})    : ();
  my @comment = defined $event->{comment} ? split($SPLIT_RE, $event->{comment}) : ();

  my @parts;
  if (@comment) { push @parts, ": $_" for @comment }
  else {
    push @parts, "event: $event->{type}" if defined $event->{type};
    push @parts, "data: $_" for @data;
    push @parts, "id: $event->{id}" if defined $event->{id};
  }

  return encode('UTF-8', join("\x0d\x0a", @parts, '', ''));
}

sub parse_event {
  my $buffer = shift;
  my $event  = {id => undef, type => 'message', text => ''};

  while ($$buffer =~ s/^(.*?)(?:(?:\x0d\x0a|(?<!\x0d)\x0a|\x0d(?!\x0a)){2})//s) {

    # Skip lines with encoding errors
    next unless defined(my $lines = decode 'UTF-8', $1);

    # Skip comments
    next if $lines =~ /^\s*:/;

    my $first = 0;
    for my $line (split $SPLIT_RE, $lines) {
      if    ($line =~ /^event(?::\s*(\S.*))?$/) { $event->{type} = $1 // 'message' }
      elsif ($line =~ /^data(?::\s*(.*))?$/)    { $event->{text} .= ($first++ ? "\n" : '') . ($1 // '') }
      elsif ($line =~ /^id(?::\s*(.*))?$/)      { $event->{id} = $1 }
    }

    return $event;
  }

  return undef;
}

1;

=encoding utf8

=head1 NAME

Mojo::SSE - Server-Sent Events

=head1 SYNOPSIS

  use Mojo::SSE qw(build_event parse_event);

=head1 DESCRIPTION

L<Mojo::SSE> implements the Server-Sent Events protocol. Note that this module is B<EXPERIMENTAL> and may change
without warning!

=head1 FUNCTIONS

L<Mojo::SSE> implements the following functions, which can be imported individually.

=head2 build_event

  my $bytes = build_event $event, $chars;

Build Server-Sent Event.

=head2 parse_event

  my $event = parse_event \$bytes;

Parse Server-Sent Event. Returns C<undef> if no complete event was found.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
