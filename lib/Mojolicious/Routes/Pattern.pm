package Mojolicious::Routes::Pattern;
use Mojo::Base -base;

has defaults => sub { {} };
has quote_end      => ')';
has quote_start    => '(';
has relaxed_start  => '.';
has reqs           => sub { {} };
has symbol_start   => ':';
has symbols        => sub { [] };
has tree           => sub { [] };
has wildcard_start => '*';
has [qw/format pattern regex/];

# "This is the worst kind of discrimination. The kind against me!"
sub new {
  my $self = shift->SUPER::new();
  $self->parse(@_);
  return $self;
}

sub match {
  my ($self, $path) = @_;

  # Match
  my $result = $self->shape_match(\$path);

  # Endpoint
  return $result if !$path || $path eq '/';

  # Partial or no match
  return;
}

sub parse {
  my $self    = shift;
  my $pattern = shift;

  # Make sure we have a viable pattern
  return $self if !defined $pattern || $pattern eq '/';
  $pattern = "/$pattern" unless $pattern =~ /^\//;

  # Format
  if ($pattern =~ /\.([^\/\)]+)$/) { $self->format($1) }

  # Requirements
  my $reqs = ref $_[0] eq 'HASH' ? $_[0] : {@_};
  $self->reqs($reqs);

  # Tokenize
  $self->pattern($pattern);
  $self->_tokenize;

  return $self;
}

sub render {
  my ($self, $values) = @_;

  # Merge values with defaults
  $values ||= {};
  $values = {%{$self->defaults}, %$values};

  my $string   = '';
  my $optional = 1;
  for my $token (reverse @{$self->tree}) {
    my $op       = $token->[0];
    my $rendered = '';

    # Slash
    if ($op eq 'slash') {
      $rendered = '/' unless $optional;
    }

    # Text
    elsif ($op eq 'text') {
      $rendered = $token->[1];
      $optional = 0;
    }

    # Relaxed, symbol or wildcard
    elsif ($op eq 'relaxed' || $op eq 'symbol' || $op eq 'wildcard') {
      my $name = $token->[1];
      $rendered = $values->{$name};
      $rendered = '' unless defined $rendered;

      my $default = $self->defaults->{$name};
      $default = '' unless defined $default;

      $optional = 0 unless $default eq $rendered;
      $rendered = '' if $optional && $default eq $rendered;
    }

    $string = "$rendered$string";
  }

  return $string || '/';
}

sub shape_match {
  my ($self, $pathref) = @_;

  # Compile on demand
  my $regex;
  $regex = $self->_compile unless $regex = $self->regex;

  # Match
  if (my @captures = $$pathref =~ $regex) {
    $$pathref =~ s/$regex//;

    # Merge captures
    my $result = {%{$self->defaults}};
    for my $symbol (@{$self->symbols}) {
      last unless @captures;

      # Merge
      my $capture = shift @captures;
      $result->{$symbol} = $capture if defined $capture;
    }
    return $result;
  }

  return;
}

sub _compile {
  my $self = shift;

  my $block    = '';
  my $regex    = '';
  my $optional = 1;
  for my $token (reverse @{$self->tree}) {
    my $op       = $token->[0];
    my $compiled = '';

    # Slash
    if ($op eq 'slash') {

      # Full block
      $block = $optional ? "(?:/$block)?" : "/$block";

      $regex = "$block$regex";
      $block = '';

      next;
    }

    # Text
    elsif ($op eq 'text') {
      $compiled = quotemeta $token->[1];
      $optional = 0;
    }

    # Symbol
    elsif ($op eq 'relaxed' || $op eq 'symbol' || $op eq 'wildcard') {
      my $name = $token->[1];

      unshift @{$self->symbols}, $name;

      # Relaxed
      if ($op eq 'relaxed') { $compiled = '([^\/]+)' }

      # Symbol
      elsif ($op eq 'symbol') { $compiled = '([^\/\.]+)' }

      # Wildcard
      elsif ($op eq 'wildcard') { $compiled = '(.+)' }

      my $req = $self->reqs->{$name};
      $compiled = "($req)" if $req;

      $optional = 0 unless exists $self->defaults->{$name};

      $compiled .= '?' if $optional;
    }

    # Add to block
    $block = "$compiled$block";
  }

  # Not rooted with a slash
  $regex = "$block$regex" if $block;

  $regex = qr/^$regex/;
  $self->regex($regex);

  return $regex;
}

sub _tokenize {
  my $self = shift;

  my $pattern        = $self->pattern;
  my $quote_end      = $self->quote_end;
  my $quote_start    = $self->quote_start;
  my $relaxed_start  = $self->relaxed_start;
  my $symbol_start   = $self->symbol_start;
  my $wildcard_start = $self->wildcard_start;
  my $tree           = [];
  my $state          = 'text';
  my $quoted         = 0;

  while (length(my $char = substr $pattern, 0, 1, '')) {

    # Inside a symbol
    my $symbol = 0;
    $symbol = 1
      if $state eq 'relaxed'
        || $state eq 'symbol'
        || $state eq 'wildcard';

    # Quote start
    if ($char eq $quote_start) {
      $quoted = 1;
      $state  = 'symbol';
      push @$tree, ['symbol', ''];
      next;
    }

    # Symbol start
    if ($char eq $symbol_start) {
      push @$tree, ['symbol', ''] if $state ne 'symbol';
      $state = 'symbol';
      next;
    }

    # Relaxed start
    if ($quoted && $char eq $relaxed_start) {

      # Upgrade relaxed to wildcard
      if ($state eq 'symbol') {
        $state = 'relaxed';
        $tree->[-1]->[0] = 'relaxed';
        next;
      }

    }

    # Wildcard start
    if ($quoted && $char eq $wildcard_start) {

      # Upgrade relaxed to wildcard
      if ($state eq 'symbol') {
        $state = 'wildcard';
        $tree->[-1]->[0] = 'wildcard';
        next;
      }

    }

    # Quote end
    if ($char eq $quote_end) {
      $quoted = 0;
      $state  = 'text';
      next;
    }

    # Slash
    if ($char eq '/') {
      push @$tree, ['slash'];
      $state = 'text';
      next;
    }

    # Relaxed, symbol or wildcard
    elsif ($symbol && $char =~ /\w/) {
      $tree->[-1]->[-1] .= $char;
      next;
    }

    # Text
    else {

      $state = 'text';

      # New text element
      unless ($tree->[-1]->[0] eq 'text') {
        push @$tree, ['text', $char];
        next;
      }

      # More text
      $tree->[-1]->[-1] .= $char;
    }
  }
  $self->tree($tree);

  return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Routes::Pattern - Routes Pattern

=head1 SYNOPSIS

  use Mojolicious::Routes::Pattern;

=head1 DESCRIPTION

L<Mojolicious::Routes::Pattern> is a container for routes pattern which are
used to match paths against.

=head1 ATTRIBUTES

L<Mojolicious::Routes::Pattern> implements the following attributes.

=head2 C<defaults>

  my $defaults = $pattern->defaults;
  $pattern     = $pattern->defaults({foo => 'bar'});

Default parameters.

=head2 C<pattern>

  my $pattern = $pattern->pattern;
  $pattern    = $pattern->pattern('/(foo)/(bar)');

Raw unparsed pattern.

=head2 C<quote_end>

  my $quote = $pattern->quote_end;
  $pattern  = $pattern->quote_end(']');

Character indicating the end of a quoted placeholder, defaults to C<)>.

=head2 C<quote_start>

  my $quote = $pattern->quote_start;
  $pattern  = $pattern->quote_start('[');

Character indicating the start of a quoted placeholder, defaults to C<(>.

=head2 C<regex>

  my $regex = $pattern->regex;
  $pattern  = $pattern->regex(qr/\/foo/);

Pattern in compiled regex form.

=head2 C<relaxed_start>

  my $relaxed = $pattern->relaxed_start;
  $pattern    = $pattern->relaxed_start('*');

Character indicating a relaxed placeholder, defaults to C<.>.

=head2 C<reqs>

  my $reqs = $pattern->reqs;
  $pattern = $pattern->reqs({foo => qr/\w+/});

Regex constraints.

=head2 C<symbol_start>

  my $symbol = $pattern->symbol_start;
  $pattern   = $pattern->symbol_start(':');

Character indicating a placeholder, defaults to C<:>.

=head2 C<symbols>

  my $symbols = $pattern->symbols;
  $pattern    = $pattern->symbols(['foo', 'bar']);

Placeholder names.

=head2 C<tree>

  my $tree = $pattern->tree;
  $pattern = $pattern->tree([ ... ]);

Pattern in parsed form.

=head2 C<wildcard_start>

  my $wildcard = $pattern->wildcard_start;
  $pattern     = $pattern->wildcard_start('*');

Character indicating the start of a wildcard placeholder, defaults to C<*>.

=head1 METHODS

L<Mojolicious::Routes::Pattern> inherits all methods from L<Mojo::Base> and
implements the following ones.

=head2 C<new>

  my $pattern = Mojolicious::Routes::Pattern->new('/:controller/:action',
    action => qr/\w+/
  );

Construct a new pattern object.

=head2 C<match>

  my $result = $pattern->match('/foo/bar');

Match pattern against a path.

=head2 C<parse>

  $pattern = $pattern->parse('/:controller/:action', action => qr/\w+/);

Parse a raw pattern.

=head2 C<render>

  my $path = $pattern->render({action => 'foo'});

Render pattern into a path with parameters.

=head2 C<shape_match>

  my $result = $pattern->shape_match(\$path);

Match pattern against a path and remove matching parts.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
