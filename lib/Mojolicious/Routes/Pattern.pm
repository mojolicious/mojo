package Mojolicious::Routes::Pattern;
use Mojo::Base -base;

has [qw(constraints defaults)] => sub { {} };
has [qw(format_regex pattern regex)];
has placeholder_start => ':';
has [qw(placeholders tree)] => sub { [] };
has quote_end      => ')';
has quote_start    => '(';
has relaxed_start  => '#';
has wildcard_start => '*';

sub new { shift->SUPER::new->parse(@_) }

sub match {
  my ($self, $path, $detect) = @_;
  my $result = $self->shape_match(\$path, $detect);
  return !$path || $path eq '/' ? $result : undef;
}

sub parse {
  my $self = shift;

  # Make sure we have a viable pattern
  my $pattern = @_ % 2 ? (shift || '/') : '/';
  $pattern = "/$pattern" unless $pattern =~ m!^/!;

  # Constraints
  $self->constraints({@_});

  # Tokenize
  return $pattern eq '/' ? $self : $self->pattern($pattern)->_tokenize;
}

sub render {
  my ($self, $values, $render) = @_;

  # Merge values with defaults
  my $format = ($values ||= {})->{format};
  $values = {%{$self->defaults}, %$values};

  # Turn pattern into path
  my $string   = '';
  my $optional = 1;
  for my $token (reverse @{$self->tree}) {
    my $op       = $token->[0];
    my $rendered = '';

    # Slash
    if ($op eq 'slash') { $rendered = '/' unless $optional }

    # Text
    elsif ($op eq 'text') {
      $rendered = $token->[1];
      $optional = 0;
    }

    # Placeholder, relaxed or wildcard
    elsif (grep { $_ eq $op } qw(placeholder relaxed wildcard)) {
      my $name = $token->[1];
      $rendered = $values->{$name} // '';
      my $default = $self->defaults->{$name};
      if (!defined $default || ($default ne $rendered)) { $optional = 0 }
      elsif ($optional) { $rendered = '' }
    }

    $string = "$rendered$string";
  }

  # Format is optional
  $string ||= '/';
  return $render && $format ? "$string.$format" : $string;
}

sub shape_match {
  my ($self, $pathref, $detect) = @_;

  # Compile on demand
  my $regex = $self->regex || $self->_compile;
  my $format
    = $detect ? ($self->format_regex || $self->_compile_format) : undef;

  # Match
  return undef unless my @captures = $$pathref =~ $regex;
  $$pathref =~ s/($regex)//;

  # Merge captures
  my $result = {%{$self->defaults}};
  for my $placeholder (@{$self->placeholders}) {
    last unless @captures;
    my $capture = shift @captures;
    $result->{$placeholder} = $capture if defined $capture;
  }

  # Format
  my $constraint = $self->constraints->{format};
  return $result if !$detect || defined $constraint && !$constraint;
  if ($$pathref =~ s!^/?$format!!) { $result->{format} = $1 }
  elsif ($constraint) { return undef unless $result->{format} }

  return $result;
}

sub _compile {
  my $self = shift;

  # Compile tree to regex
  my $block = my $regex = '';
  my $constraints = $self->constraints;
  my $optional    = 1;
  my $defaults    = $self->defaults;
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

    # Placeholder
    elsif (grep { $_ eq $op } qw(placeholder relaxed wildcard)) {
      my $name = $token->[1];
      unshift @{$self->placeholders}, $name;

      # Placeholder
      if ($op eq 'placeholder') { $compiled = '([^\/\.]+)' }

      # Relaxed
      elsif ($op eq 'relaxed') { $compiled = '([^\/]+)' }

      # Wildcard
      elsif ($op eq 'wildcard') { $compiled = '(.+)' }

      # Custom regex
      my $constraint = $constraints->{$name};
      $compiled = _compile_req($constraint) if $constraint;

      # Optional placeholder
      $optional = 0 unless exists $defaults->{$name};
      $compiled .= '?' if $optional;
    }

    # Add to block
    $block = "$compiled$block";
  }

  # Not rooted with a slash
  $regex = "$block$regex" if $block;

  # Compile
  return $self->regex(qr/^$regex/s)->regex;
}

sub _compile_format {
  my $self = shift;

  # Default regex
  my $c = $self->constraints;
  return $self->format_regex(qr!\.([^/]+)$!)->format_regex
    unless defined $c->{format};

  # No regex
  return undef unless $c->{format};

  # Compile custom regex
  my $regex = _compile_req($c->{format});
  return $self->format_regex(qr!\.$regex$!)->format_regex;
}

sub _compile_req {
  my $req = shift;
  return "($req)" if ref $req ne 'ARRAY';
  return '(' . join('|', map {quotemeta} reverse sort @$req) . ')';
}

sub _tokenize {
  my $self = shift;

  # Token
  my $quote_end   = $self->quote_end;
  my $quote_start = $self->quote_start;
  my $placeholder = $self->placeholder_start;
  my $relaxed     = $self->relaxed_start;
  my $wildcard    = $self->wildcard_start;

  # Parse the pattern character wise
  my $pattern = $self->pattern;
  my $state   = 'text';
  my (@tree, $quoted);
  while (length(my $char = substr $pattern, 0, 1, '')) {

    # Inside a placeholder
    my $inside = !!grep { $_ eq $state } qw(placeholder relaxed wildcard);

    # Quote start
    if ($char eq $quote_start) {
      $quoted = 1;
      $state  = 'placeholder';
      push @tree, ['placeholder', ''];
    }

    # Placeholder start
    elsif ($char eq $placeholder) {
      push @tree, ['placeholder', ''] if $state ne 'placeholder';
      $state = 'placeholder';
    }

    # Relaxed or wildcard start (upgrade when quoted)
    elsif (grep { $_ eq $char } $relaxed, $wildcard) {
      push @tree, ['placeholder', ''] unless $quoted;
      $tree[-1][0] = $state = $char eq $relaxed ? 'relaxed' : 'wildcard';
    }

    # Quote end
    elsif ($char eq $quote_end) {
      $quoted = 0;
      $state  = 'text';
    }

    # Slash
    elsif ($char eq '/') {
      push @tree, ['slash'];
      $state = 'text';
    }

    # Placeholder, relaxed or wildcard
    elsif ($inside && $char =~ /\w/) { $tree[-1][-1] .= $char }

    # Text
    else {
      $state = 'text';

      # New text element
      push @tree, ['text', $char] and next unless $tree[-1][0] eq 'text';

      # More text
      $tree[-1][-1] .= $char;
    }
  }

  return $self->tree(\@tree);
}

1;

=head1 NAME

Mojolicious::Routes::Pattern - Routes pattern engine

=head1 SYNOPSIS

  use Mojolicious::Routes::Pattern;

  # Create pattern
  my $pattern = Mojolicious::Routes::Pattern->new('/test/:name');

  # Match routes
  my $result  = $pattern->match('/test/sebastian');
  say $result->{name};

=head1 DESCRIPTION

L<Mojolicious::Routes::Pattern> is the core of L<Mojolicious::Routes>.

=head1 ATTRIBUTES

L<Mojolicious::Routes::Pattern> implements the following attributes.

=head2 C<constraints>

  my $constraints = $pattern->constraints;
  $pattern        = $pattern->constraints({foo => qr/\w+/});

Regular expression constraints.

=head2 C<defaults>

  my $defaults = $pattern->defaults;
  $pattern     = $pattern->defaults({foo => 'bar'});

Default parameters.

=head2 C<format_regex>

  my $regex = $pattern->format_regex;
  $pattern  = $pattern->format_regex($regex);

Compiled regular expression for format matching.

=head2 C<pattern>

  my $pattern = $pattern->pattern;
  $pattern    = $pattern->pattern('/(foo)/(bar)');

Raw unparsed pattern.

=head2 C<placeholder_start>

  my $start = $pattern->placeholder_start;
  $pattern  = $pattern->placeholder_start(':');

Character indicating a placeholder, defaults to C<:>.

=head2 C<placeholders>

  my $placeholders = $pattern->placeholders;
  $pattern         = $pattern->placeholders(['foo', 'bar']);

Placeholder names.

=head2 C<quote_end>

  my $end  = $pattern->quote_end;
  $pattern = $pattern->quote_end(']');

Character indicating the end of a quoted placeholder, defaults to C<)>.

=head2 C<quote_start>

  my $start = $pattern->quote_start;
  $pattern  = $pattern->quote_start('[');

Character indicating the start of a quoted placeholder, defaults to C<(>.

=head2 C<regex>

  my $regex = $pattern->regex;
  $pattern  = $pattern->regex($regex);

Pattern in compiled regular expression form.

=head2 C<relaxed_start>

  my $start = $pattern->relaxed_start;
  $pattern  = $pattern->relaxed_start('*');

Character indicating a relaxed placeholder, defaults to C<#>.

=head2 C<tree>

  my $tree = $pattern->tree;
  $pattern = $pattern->tree([ ... ]);

Pattern in parsed form.

=head2 C<wildcard_start>

  my $start = $pattern->wildcard_start;
  $pattern  = $pattern->wildcard_start('*');

Character indicating the start of a wildcard placeholder, defaults to C<*>.

=head1 METHODS

L<Mojolicious::Routes::Pattern> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<new>

  my $pattern = Mojolicious::Routes::Pattern->new('/:action');
  my $pattern
    = Mojolicious::Routes::Pattern->new('/:action', action => qr/\w+/);
  my $pattern = Mojolicious::Routes::Pattern->new(format => 0);

Construct a new L<Mojolicious::Routes::Pattern> object.

=head2 C<match>

  my $result = $pattern->match('/foo/bar');
  my $result = $pattern->match('/foo/bar', 1);

Match pattern against entire path, format detection is disabled by default.

=head2 C<parse>

  $pattern = $pattern->parse('/:action');
  $pattern = $pattern->parse('/:action', action => qr/\w+/);
  $pattern = $pattern->parse(format => 0);

Parse a raw pattern.

=head2 C<render>

  my $path = $pattern->render({action => 'foo'});
  my $path = $pattern->render({action => 'foo'}, 1);

Render pattern into a path with parameters, format rendering is disabled by
default.

=head2 C<shape_match>

  my $result = $pattern->shape_match(\$path);
  my $result = $pattern->shape_match(\$path, 1);

Match pattern against path and remove matching parts, format detection is
disabled by default.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
