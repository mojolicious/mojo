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

sub match {
  my ($self, $path, $detect) = @_;
  my $captures = $self->match_partial(\$path, $detect);
  return !$path || $path eq '/' ? $captures : undef;
}

sub match_partial {
  my ($self, $pathref, $detect) = @_;

  # Compile on demand
  $self->_compile unless $self->{regex};
  $self->_compile_format if $detect && !$self->{format_regex};

  # Match
  return undef unless my @captures = $$pathref =~ $self->regex;
  $$pathref = ${^POSTMATCH};

  # Merge captures
  my $captures = {%{$self->defaults}};
  for my $placeholder (@{$self->placeholders}) {
    last unless @captures;
    my $capture = shift @captures;
    $captures->{$placeholder} = $capture if defined $capture;
  }

  # Format
  return $captures unless $detect && (my $regex = $self->format_regex);
  return undef unless $$pathref =~ $regex;
  $captures->{format} = $1 if defined $1;
  $$pathref = '';
  return $captures;
}

sub new { @_ > 1 ? shift->SUPER::new->parse(@_) : shift->SUPER::new }

sub parse {
  my $self = shift;

  my $pattern = @_ % 2 ? (shift // '/') : '/';
  $pattern =~ s!^/*|/+!/!g;
  return $self->constraints({@_}) if $pattern eq '/';
  $pattern =~ s!/$!!;

  return $self->constraints({@_})->_tokenize($pattern);
}

sub render {
  my ($self, $values, $endpoint) = @_;

  # Placeholders can only be optional without a format
  my $optional = !(my $format = $values->{format});

  my $str = '';
  for my $token (reverse @{$self->tree}) {
    my ($op, $value) = @$token;
    my $fragment = '';

    # Text
    if ($op eq 'text') { ($fragment, $optional) = ($value, 0) }

    # Slash
    elsif ($op eq 'slash') { $fragment = '/' unless $optional }

    # Placeholder
    else {
      my $default = $self->defaults->{$value};
      $fragment = $values->{$value} // $default // '';
      if (!defined $default || ($default ne $fragment)) { $optional = 0 }
      elsif ($optional) { $fragment = '' }
    }

    $str = "$fragment$str";
  }

  # Format can be optional
  return $endpoint && $format ? "$str.$format" : $str;
}

sub _compile {
  my $self = shift;

  my $placeholders = $self->placeholders;
  my $constraints  = $self->constraints;
  my $defaults     = $self->defaults;

  my $block = my $regex = '';
  my $optional = 1;
  for my $token (reverse @{$self->tree}) {
    my ($op, $value) = @$token;
    my $fragment = '';

    # Text
    if ($op eq 'text') { ($fragment, $optional) = (quotemeta $value, 0) }

    # Slash
    elsif ($op eq 'slash') {
      $regex = ($optional ? "(?:/$block)?" : "/$block") . $regex;
      ($block, $optional) = ('', 1);
      next;
    }

    # Placeholder
    else {
      unshift @$placeholders, $value;

      # Placeholder
      if ($op eq 'placeholder') { $fragment = '([^/.]+)' }

      # Relaxed
      elsif ($op eq 'relaxed') { $fragment = '([^/]+)' }

      # Wildcard
      else { $fragment = '(.+)' }

      # Custom regex
      if (my $c = $constraints->{$value}) { $fragment = _compile_req($c) }

      # Optional placeholder
      exists $defaults->{$value} ? ($fragment .= '?') : ($optional = 0);
    }

    $block = "$fragment$block";
  }

  # Not rooted with a slash
  $regex = "$block$regex" if $block;

  $self->regex(qr/^$regex/ps);
}

sub _compile_format {
  my $self = shift;

  # Default regex
  my $format = $self->constraints->{format};
  return $self->format_regex(qr!^/?(?:\.([^/]+))?$!) unless defined $format;

  # No regex
  return undef unless $format;

  # Compile custom regex
  my $regex = '\.' . _compile_req($format);
  $regex = "(?:$regex)?" if $self->defaults->{format};
  $self->format_regex(qr!^/?$regex$!);
}

sub _compile_req {
  my $req = shift;
  return "($req)" if ref $req ne 'ARRAY';
  return '(' . join('|', map {quotemeta} reverse sort @$req) . ')';
}

sub _tokenize {
  my ($self, $pattern) = @_;

  my $quote_end   = $self->quote_end;
  my $quote_start = $self->quote_start;
  my $placeholder = $self->placeholder_start;
  my $relaxed     = $self->relaxed_start;
  my $wildcard    = $self->wildcard_start;

  my (@tree, $inside, $quoted);
  for my $char (split '', $pattern) {

    # Quote start
    if ($char eq $quote_start) {
      push @tree, ['placeholder', ''];
      ($inside, $quoted) = (1, 1);
    }

    # Placeholder start
    elsif ($char eq $placeholder) {
      push @tree, ['placeholder', ''] unless $inside++;
    }

    # Relaxed or wildcard start (upgrade when quoted)
    elsif ($char eq $relaxed || $char eq $wildcard) {
      push @tree, ['placeholder', ''] unless $quoted;
      $tree[-1][0] = $char eq $relaxed ? 'relaxed' : 'wildcard';
      $inside = 1;
    }

    # Quote end
    elsif ($char eq $quote_end) { ($inside, $quoted) = (0, 0) }

    # Slash
    elsif ($char eq '/') {
      push @tree, ['slash'];
      $inside = 0;
    }

    # Placeholder, relaxed or wildcard
    elsif ($inside) { $tree[-1][-1] .= $char }

    # Text (optimize slash+text and *+text+slash+text)
    elsif ($tree[-1][0] eq 'text') { $tree[-1][-1] .= $char }
    elsif (!$tree[-2] && $tree[-1][0] eq 'slash') {
      @tree = (['text', "/$char"]);
    }
    elsif ($tree[-2] && $tree[-2][0] eq 'text' && $tree[-1][0] eq 'slash') {
      pop @tree && ($tree[-1][-1] .= "/$char");
    }
    else { push @tree, ['text', $char] }
  }

  return $self->pattern($pattern)->tree(\@tree);
}

1;

=encoding utf8

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

  my $raw  = $pattern->pattern;
  $pattern = $pattern->pattern('/(foo)/(bar)');

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
  $pattern = $pattern->tree([['text', '/foo']]);

Pattern in parsed form. Note that this structure should only be used very
carefully since it is very dynamic.

=head2 wildcard_start

  my $start = $pattern->wildcard_start;
  $pattern  = $pattern->wildcard_start('*');

Character indicating the start of a wildcard placeholder, defaults to C<*>.

=head1 METHODS

L<Mojolicious::Routes::Pattern> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 match

  my $captures = $pattern->match('/foo/bar');
  my $captures = $pattern->match('/foo/bar', 1);

Match pattern against entire path, format detection is disabled by default.

=head2 match_partial

  my $captures = $pattern->match_partial(\$path);
  my $captures = $pattern->match_partial(\$path, 1);

Match pattern against path and remove matching parts, format detection is
disabled by default.

=head2 new

  my $pattern = Mojolicious::Routes::Pattern->new('/:action');
  my $pattern
    = Mojolicious::Routes::Pattern->new('/:action', action => qr/\w+/);
  my $pattern = Mojolicious::Routes::Pattern->new(format => 0);

Construct a new L<Mojolicious::Routes::Pattern> object and L</"parse"> pattern
if necessary.

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
