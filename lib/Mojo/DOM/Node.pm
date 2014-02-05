package Mojo::DOM::Node;
use Mojo::Base -base;
use overload bool => sub {1}, '""' => sub { shift->content }, fallback => 1;

has [qw(parent tree)];

sub content {
  my $self = shift;
  return $self->tree->[1] unless @_;
  $self->tree->[1] = shift;
  return $self;
}

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

1;

=encoding utf8

=head1 NAME

Mojo::DOM::Node - DOM Node

=head1 SYNOPSIS

  use Mojo::DOM::Node;

  my $node = Mojo::DOM::Node->new(parent => $parent, tree => $tree);
  say $node->content;

=head1 DESCRIPTION

L<Mojo::DOM::Node> is a container for nodes used by L<Mojo::DOM>.

=head1 ATTRIBUTES

L<Mojo::DOM::Node> implements the following attributes.

=head2 parent

  my $parent = $node->parent;
  $node      = $node->parent(Mojo::DOM->new);

L<Mojo::DOM> object for parent of this node.

=head2 tree

  my $tree = $node->tree;
  $node    = $node->tree(['text', 'foo']);

Document Object Model. Note that this structure should only be used very
carefully since it is very dynamic.

=head1 METHODS

L<Mojo::DOM::Node> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 content

  my $content = $node->content;
  $node       = $node->content('foo');

Return or replace this node's content.

=head2 node

  my $type = $node->node;

This node's type, usually C<cdata>, C<comment>, C<doctype>, C<pi>, C<raw> or
C<text>.

=head2 remove

  my $parent = $node->remove;

Remove this node and return L</"parent">.

=head1 OPERATORS

L<Mojo::DOM::Node> overloads the following operators.

=head2 bool

  my $bool = !!$node;

Always true.

=head2 stringify

  my $content = "$node";

Alias for L</content>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
