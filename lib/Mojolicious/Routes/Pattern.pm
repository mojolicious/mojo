package Mojolicious::Routes::Pattern;
use Mojo::Base -base;

use Carp qw(croak);

has [qw(constraints defaults types)]   => sub { {} };
has [qw(placeholder_start type_start)] => ':';
has [qw(placeholders tree)]            => sub { [] };
has quote_end                          => '>';
has quote_start                        => '<';
has [qw(regex unparsed)];
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
  $self->_compile($detect) unless $self->{regex};

  return undef unless my @captures = $$pathref =~ $self->regex;
  $$pathref = ${^POSTMATCH};
  @captures = () if $#+ == 0;
  my $captures = {%{$self->defaults}};
  for my $placeholder (@{$self->placeholders}, 'format') {
    last unless @captures;
    my $capture = shift @captures;
    $captures->{$placeholder} = $capture if defined $capture;
  }

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
    my $part = '';

    # Text
    if ($op eq 'text') { ($part, $optional) = ($value, 0) }

    # Slash
    elsif ($op eq 'slash') { $part = '/' unless $optional }

    # Placeholder
    else {
      my $name    = $value->[0];
      my $default = $self->defaults->{$name};
      $part = $values->{$name} // $default // '';
      if    (!defined $default || ($default ne $part)) { $optional = 0 }
      elsif ($optional)                                { $part     = '' }
    }

    $str = $part . $str;
  }

  # Format can be optional
  return $endpoint && $format ? "$str.$format" : $str;
}

sub _compile {
  my ($self, $detect) = @_;

  my $constraints = $self->constraints;
  my $defaults    = $self->defaults;
  my $types       = $self->types;

  my $block    = my $regex = '';
  my $optional = 1;
  for my $token (reverse @{$self->tree}) {
    my ($op, $value, $type) = @$token;
    my $part = '';

    # Text
    if ($op eq 'text') { ($part, $optional) = (quotemeta $value, 0) }

    # Slash
    elsif ($op eq 'slash') {
      $regex = ($optional ? "(?:/$block)?" : "/$block") . $regex;
      ($block, $optional) = ('', 1);
      next;
    }

    # Placeholder
    else {
      if ($value->[1]) { $part = _compile_req($types->{$value->[1]} // '?!') }
      else             { $part = $type ? $type eq 'relaxed' ? '([^/]+)' : '(.+)' : '([^/.]+)' }

      # Custom regex
      if (my $c = $constraints->{$value->[0]}) { $part = _compile_req($c) }

      # Optional placeholder
      exists $defaults->{$value->[0]} ? ($part .= '?') : ($optional = 0);
    }

    $block = $part . $block;
  }

  # Not rooted with a slash
  $regex = $block . $regex if $block;

  # Format
  $regex .= _compile_format($constraints->{format}, exists $defaults->{format}) if $detect;

  $self->regex(qr/^$regex/ps);
}

sub _compile_format {
  my ($format, $has_default) = @_;

  # No regex
  return '' unless $format;

  # Default regex
  return '/?(?:\.([^/]+))?$' if $format eq '1';

  # Compile custom regex
  my $regex = '\.' . _compile_req($format);
  return $has_default ? "/?(?:$regex)?\$" : "/?$regex\$";
}

sub _compile_req {
  my $req = shift;
  return "($req)" if ref $req ne 'ARRAY';
  return '(' . join('|', map {quotemeta} reverse sort @$req) . ')';
}

sub _tokenize {
  my ($self, $pattern) = @_;

  my $placeholders = $self->placeholders;
  my $type_start   = $self->type_start;
  my $quote_end    = $self->quote_end;
  my $quote_start  = $self->quote_start;
  my $start        = $self->placeholder_start;
  my $relaxed      = $self->relaxed_start;
  my $wildcard     = $self->wildcard_start;

  my (@tree, $spec, $more);
  for my $char (split //, $pattern) {

    # Quoted
    if    ($char eq $quote_start) { push @tree, ['placeholder', ''] if ++$spec }
    elsif ($char eq $quote_end)   { $spec = $more = 0 }

    # Placeholder
    elsif (!$more && $char eq $start) { push @tree, ['placeholder', ''] unless $spec++ }

    # Relaxed or wildcard (upgrade when quoted)
    elsif (!$more && ($char eq $relaxed || $char eq $wildcard)) {
      push @tree, ['placeholder', ''] unless $spec++;
      $tree[-1][2] = $char eq $relaxed ? 'relaxed' : 'wildcard';
    }

    # Slash
    elsif ($char eq '/') {
      push @tree, ['slash'];
      $spec = $more = 0;
    }

    # Placeholder
    elsif ($spec && ++$more) { $tree[-1][1] .= $char }

    # Text (optimize slash+text and *+text+slash+text)
    elsif ($tree[-1][0] eq 'text')                                         { $tree[-1][-1] .= $char }
    elsif (!$tree[-2] && $tree[-1][0] eq 'slash')                          { @tree = (['text', "/$char"]) }
    elsif ($tree[-2] && $tree[-2][0] eq 'text' && $tree[-1][0] eq 'slash') { pop @tree && ($tree[-1][-1] .= "/$char") }
    else                                                                   { push @tree, ['text', $char] }
  }

  # Placeholder types
  for my $token (reverse @tree) {
    next unless $token->[0] eq 'placeholder';
    $token->[1] = $token->[1] =~ /^(.+)\Q$type_start\E(.+)$/ ? [$1, $2] : [$token->[1]];
    unshift @$placeholders, $token->[1][0];
  }

  return $self->unparsed($pattern)->tree(\@tree);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Routes::Pattern - Route pattern

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
  $pattern = $pattern->quote_end('}');

Character indicating the end of a quoted placeholder, defaults to C<E<gt>>.

=head2 quote_start

  my $start = $pattern->quote_start;
  $pattern  = $pattern->quote_start('{');

Character indicating the start of a quoted placeholder, defaults to C<E<lt>>.

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

Pattern in parsed form. Note that this structure should only be used very carefully since it is very dynamic.

=head2 type_start

  my $start = $pattern->type_start;
  $pattern  = $pattern->type_start('|');

Character indicating the start of a placeholder type, defaults to C<:>.

=head2 types

  my $types = $pattern->types;
  $pattern  = $pattern->types({int => qr/[0-9]+/});

Placeholder types.

=head2 unparsed

  my $unparsed = $pattern->unparsed;
  $pattern     = $pattern->unparsed('/:foo/:bar');

Raw unparsed pattern.

=head2 wildcard_start

  my $start = $pattern->wildcard_start;
  $pattern  = $pattern->wildcard_start('*');

Character indicating the start of a wildcard placeholder, defaults to C<*>.

=head1 METHODS

L<Mojolicious::Routes::Pattern> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 match

  my $captures = $pattern->match('/foo/bar');
  my $captures = $pattern->match('/foo/bar', 1);

Match pattern against entire path, format detection is disabled by default.

=head2 match_partial

  my $captures = $pattern->match_partial(\$path);
  my $captures = $pattern->match_partial(\$path, 1);

Match pattern against path and remove matching parts, format detection is disabled by default.

=head2 new

  my $pattern = Mojolicious::Routes::Pattern->new;
  my $pattern = Mojolicious::Routes::Pattern->new('/users/:id');
  my $pattern = Mojolicious::Routes::Pattern->new('/user/:id', id => qr/\d+/);
  my $pattern = Mojolicious::Routes::Pattern->new(format => ['json', 'yaml']);

Construct a new L<Mojolicious::Routes::Pattern> object and L</"parse"> pattern if necessary.

=head2 parse

  $pattern = $pattern->parse('/user/:id');
  $pattern = $pattern->parse('/user/:id', id=> qr/\d+/);
  $pattern = $pattern->parse(format => ['json', 'yaml']);

Parse pattern.

=head2 render

  my $path = $pattern->render({id => 24});
  my $path = $pattern->render({id => 24}, 1);

Render pattern into a path with parameters, format rendering is disabled by default.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
