package Mojo::DOM::Collection;
use Mojo::Base -base;
use overload 'bool' => sub {1}, '""' => sub { shift->to_xml }, fallback => 1;

# "Hi, Super Nintendo Chalmers!"
sub new {
  my $class = shift;
  bless shift, ref $class || $class;
}

sub each   { shift->_iterate(@_) }
sub to_xml { join "\n", map({"$_"} @{$_[0]}) }
sub until  { shift->_iterate(@_, 1) }
sub while  { shift->_iterate(@_, 0) }

# "All right, let's not panic.
#  I'll make the money by selling one of my livers.
#  I can get by with one."
sub _iterate {
  my ($self, $cb, $cond) = @_;
  return @$self unless $cb;

  # Iterate until condition is true
  my $i = 1;
  if (defined $cond) { !!$_->$cb($i++) == $cond && last for @$self }

  # Iterate over all elements
  else { $_->$cb($i++) for @$self }

  # Root
  return unless my $start = $self->[0];
  return $start->root;
}

1;
__END__

=head1 NAME

Mojo::DOM::Collection - Element Collection

=head1 SYNOPSIS

  use Mojo::DOM::Collection;

=head1 DESCRIPTION

L<Mojo::DOM::Collection> is a container for element collections used by
L<Mojo::DOM>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::DOM::Collection> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<new>

  my $collection = Mojo::DOM::Collection->new([...]);

Construct a new L<Mojo::DOM::Collection> object.

=head2 C<each>

  my @elements = $collection->each;
  my $root     = $collection->each(sub { print shift->text });
  my $root     = $collection->each(sub {
    my ($e, $count) = @_;
    print "$count: ", $e->text;
  });

Iterate over whole collection.

=head2 C<to_xml>

  my $xml = $collection->to_xml;

Render collection to XML.

=head2 C<until>

  my $root = $collection->until(sub { $_->text =~ /x/ && print $_->text });
  my $root = $collection->until(sub {
    my ($e, $count) = @_;
    $e->text =~ /x/ && print "$count: ", $e->text;
  });

Iterate over collection until closure returns true.

=head2 C<while>

  my $root = $collection->while(sub {
    print($_->text) && $_->text =~ /x/
  });
  my $root = $collection->while(sub {
    my ($e, $count) = @_;
    print("$count: ", $e->text) && $e->text =~ /x/;
  });

Iterate over collection while closure returns true.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
