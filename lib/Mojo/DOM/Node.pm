package Mojo::DOM::Node;
use Mojo::Base -base;
use overload bool => sub {1}, '""' => sub { shift->value }, fallback => 1;

has [qw(parent tree)];

sub node { shift->tree->[0] }

sub remove {
  my $self = shift;

  my $parent = $self->parent;
  my $tree   = $parent->tree;
  my $node   = $self->tree;
  $tree->[$_] eq $node and splice(@$tree, $_, 1) and last
    for ($tree->[0] eq 'root' ? 1 : 4) .. $#$tree;

  return $parent;
}

sub value {
  my $self = shift;
  return $self->tree->[1] unless @_;
  $self->tree->[1] = shift;
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::DOM::Node - DOM Node

=head1 SYNOPSIS

  use Mojo::DOM::Node;

  my $node = Mojo::DOM::Node->new(parent => $parent, tree => $tree);
  say $node->value;

=head1 DESCRIPTION

L<Mojo::DOM::Node> is a container for nodes used by L<Mojo::DOM>.

=head1 ATTRIBUTES

L<Mojo::DOM::Node> implements the following attributes.

=head2 parent

  my $parent = $node->parent;
  $node      = $node->parent(Mojo::DOM->new);

Return L<Mojo::DOM> object for parent of this node.

=head2 tree

  my $tree = $node->tree;
  $node    = $node->tree(['text', 'foo']);

Document Object Model. Note that this structure should only be used very
carefully since it is very dynamic.

=head1 METHODS

L<Mojo::DOM::Node> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 node

  my $type = $node->node;

Node type, usually C<cdata>, C<comment>, C<doctype>, C<pi>, C<raw> or C<text>.

=head2 remove

  my $parent = $node->remove;

Remove node and return L<Mojo::DOM> object for parent of node.

=head2 value

  my $value = $node->value;
  $node     = $node->value('foo');
  my $value = "$node";

Node value.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
