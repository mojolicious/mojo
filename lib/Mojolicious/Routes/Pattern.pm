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
  my $captures = $self->match_partial(\$path, $detect);
  return !$path || $path eq '/' ? $captures : undef;
}

sub match_partial {
  my ($self, $pathref, $detect) = @_;

  # Compile on demand
  my $regex = $self->regex || $self->_compile;
  my $format
    = $detect ? ($self->format_regex || $self->_compile_format) : undef;

  # Match
  return undef unless my @captures = $$pathref =~ $regex;
  $$pathref =~ s/$regex//;

  # Merge captures
  my $captures = {%{$self->defaults}};
  for my $placeholder (@{$self->placeholders}) {
    last unless @captures;
    my $capture = shift @captures;
    $captures->{$placeholder} = $capture if defined $capture;
  }

  # Format
  my $constraint = $self->constraints->{format};
  return $captures if !$detect || defined $constraint && !$constraint;
  if ($$pathref =~ s!^/?$format!!) { $captures->{format} = $1 }
  elsif ($constraint) { return undef unless $captures->{format} }

  return $captures;
}

sub parse {
  my $self = shift;

  # Make sure we have a viable pattern
  my $pattern = @_ % 2 ? (shift || '/') : '/';
  $pattern = "/$pattern" unless $pattern =~ m!^/!;
  $self->constraints({@_});

  return $pattern eq '/' ? $self : $self->pattern($pattern)->_tokenize;
}

sub render {
  my ($self, $values, $render) = @_;

  # Merge values with defaults
  my $format = ($values ||= {})->{format};
  $values = {%{$self->defaults}, %$values};

  # Placeholders can only be optional without a format
  my $optional = !$format;

  my $str = '';
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
    elsif ($op eq 'placeholder' || $op eq 'relaxed' || $op eq 'wildcard') {
      my $name = $token->[1];
      $rendered = $values->{$name} // '';
      my $default = $self->defaults->{$name};
      if (!defined $default || ($default ne $rendered)) { $optional = 0 }
      elsif ($optional) { $rendered = '' }
    }

    $str = "$rendered$str";
  }

  # Format is optional
  $str ||= '/';
  return $render && $format ? "$str.$format" : $str;
}

sub _compile {
  my $self = shift;

  my $block = my $regex = '';
  my $optional    = 1;
  my $constraints = $self->constraints;
  my $defaults    = $self->defaults;
  for my $token (reverse @{$self->tree}) {
    my $op       = $token->[0];
    my $compiled = '';

    # Slash
    if ($op eq 'slash') {
      $regex = ($optional ? "(?:/$block)?" : "/$block") . $regex;
      $block = '';
      next;
    }

    # Text
    elsif ($op eq 'text') {
      $compiled = quotemeta $token->[1];
      $optional = 0;
    }

    # Placeholder
    elsif ($op eq 'placeholder' || $op eq 'relaxed' || $op eq 'wildcard') {
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

    $block = "$compiled$block";
  }

  # Not rooted with a slash
  $regex = "$block$regex" if $block;

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

  my $quote_end   = $self->quote_end;
  my $quote_start = $self->quote_start;
  my $placeholder = $self->placeholder_start;
  my $relaxed     = $self->relaxed_start;
  my $wildcard    = $self->wildcard_start;

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
    elsif ($char eq $relaxed || $char eq $wildcard) {
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
  my $captures = $pattern->match('/test/sebastian');
  say $captures->{name};

=head1 DESCRIPTION

L<Mojolicious::Routes::Pattern> is the core of L<Mojolicious::Routes>.

=head1 ATTRIBUTES

L<Mojolicious::Routes::Pattern> implements the following attributes.

=head2 constraints

  my $constraints = $pattern->constraints;
  $pattern        = $pattern->constraints({foo => qr/\w+/});

Regular expression constraints.

=head2 defaults

  my $defaults = $pattern->defaults;
  $pattern     = $pattern->defaults({foo => 'bar'});

Default parameters.

=head2 format_regex

  my $regex = $pattern->format_regex;
  $pattern  = $pattern->format_regex($regex);

Compiled regular expression for format matching.

=head2 pattern

  my $pattern = $pattern->pattern;
  $pattern    = $pattern->pattern('/(foo)/(bar)');

Raw unparsed pattern.

=head2 placeholder_start

  my $start = $pattern->placeholder_start;
  $pattern  = $pattern->placeholder_start(':');

Character indicating a placeholder, defaults to C<:>.

=head2 placeholders

  my $placeholders = $pattern->placeholders;
  $pattern         = $pattern->placeholders(['foo', 'bar']);

Placeholder names.

=head2 quote_end

  my $end  = $pattern->quote_end;
  $pattern = $pattern->quote_end(']');

Character indicating the end of a quoted placeholder, defaults to C<)>.

=head2 quote_start

  my $start = $pattern->quote_start;
  $pattern  = $pattern->quote_start('[');

Character indicating the start of a quoted placeholder, defaults to C<(>.

=head2 regex

  my $regex = $pattern->regex;
  $pattern  = $pattern->regex($regex);

Pattern in compiled regular expression form.

=head2 relaxed_start

  my $start = $pattern->relaxed_start;
  $pattern  = $pattern->relaxed_start('*');

Character indicating a relaxed placeholder, defaults to C<#>.

=head2 tree

  my $tree = $pattern->tree;
  $pattern = $pattern->tree([['slash'], ['text', 'foo']]);

Pattern in parsed form. Note that this structure should only be used very
carefully since it is very dynamic.

=head2 wildcard_start

  my $start = $pattern->wildcard_start;
  $pattern  = $pattern->wildcard_start('*');

Character indicating the start of a wildcard placeholder, defaults to C<*>.

=head1 METHODS

L<Mojolicious::Routes::Pattern> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 new

  my $pattern = Mojolicious::Routes::Pattern->new('/:action');
  my $pattern
    = Mojolicious::Routes::Pattern->new('/:action', action => qr/\w+/);
  my $pattern = Mojolicious::Routes::Pattern->new(format => 0);

Construct a new L<Mojolicious::Routes::Pattern> object and C<parse> pattern if
necessary.

=head2 match

  my $captures = $pattern->match('/foo/bar');
  my $captures = $pattern->match('/foo/bar', 1);

Match pattern against entire path, format detection is disabled by default.

=head2 match_partial

  my $captures = $pattern->match_partial(\$path);
  my $captures = $pattern->match_partial(\$path, 1);

Match pattern against path and remove matching parts, format detection is
disabled by default.

=head2 parse

  $pattern = $pattern->parse('/:action');
  $pattern = $pattern->parse('/:action', action => qr/\w+/);
  $pattern = $pattern->parse(format => 0);

Parse pattern.

=head2 render

  my $path = $pattern->render({action => 'foo'});
  my $path = $pattern->render({action => 'foo'}, 1);

Render pattern into a path with parameters, format rendering is disabled by
default.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
