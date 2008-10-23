# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Routes::Pattern;

use strict;
use warnings;

use base 'Mojo::Base';

use constant DEBUG => $ENV{MOJOX_ROUTES_DEBUG} || 0;

__PACKAGE__->attr('defaults',          chained => 1, default => sub { {} });
__PACKAGE__->attr([qw/pattern regex/], chained => 1);
__PACKAGE__->attr('quote_end',         chained => 1, default => sub { ')' });
__PACKAGE__->attr('quote_start',       chained => 1, default => sub { '(' });
__PACKAGE__->attr('requirements',      chained => 1, default => sub { {} });
__PACKAGE__->attr('segments',          chained => 1, default => sub { 0 });
__PACKAGE__->attr('symbol_start',      chained => 1, default => sub { ':' });
__PACKAGE__->attr('symbols',           chained => 1, default => sub { [] });
__PACKAGE__->attr('tree',              chained => 1, default => sub { [] });

*reqs = \&requirements;

# This is the worst kind of discrimination. The kind against me!
sub new {
    my $self = shift->SUPER::new();
    $self->parse(@_);
    return $self;
}

sub match {
    my ($self, $string) = @_;

    # Debug
    if (DEBUG) {
        my $pattern = $self->pattern || '';
        warn "    [$pattern]\n";
    }

    # Nothing to match
    return $self->defaults unless $self->segments;

    # Compile on demand
    $self->_compile unless $self->regex;

    my $regex = $self->regex;

    # Debug
    warn "    $regex\n" if DEBUG;

    # Match
    if (my @captures = $string =~ $regex) {

        # Merge captures
        my $result = {%{$self->defaults}};
        for my $symbol (@{$self->symbols}) {
            last unless @captures;
            my $capture = shift @captures;
            $result->{$symbol} = $capture if $capture;
        }
        return $result;
    }
    return undef;
}

sub parse {
    my $self    = shift;
    my $pattern = shift;

    # Shortcut
    return $self unless $pattern;

    # Requirements
    my $reqs = ref $_[0] eq 'HASH' ? $_[0] : {@_};
    $self->reqs($reqs);

    # Tokenize
    $self->pattern($pattern);
    $self->_tokenize;

    return $self;
}

sub render {
    my $self = shift;

    # Merge values with defaults
    my $values = ref $_[0] eq 'HASH' ? $_[0] : {@_};
    $values    = {%{$self->defaults}, %$values};

    my $string = '';
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

        # Symbol
        elsif ($op eq 'symbol') {
            my $name  = $token->[1];
            $rendered = $values->{$name} || '';

            my $default = $self->defaults->{$name} || '';

            $optional = 0 unless $default eq $rendered;
            $rendered = '' if $optional && $default eq $rendered;
        }

        $string = "$rendered$string";
    }
    return $string;
}

sub _compile {
    my $self = shift;

    my $block = '';
    my $regex = '';
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
            $compiled = $token->[1];
            $optional = 0;
        }

        # Symbol
        elsif ($op eq 'symbol') {
            my $name  = $token->[1];

            unshift @{$self->symbols}, $name;

            $compiled = '([^\/]+)';

            my $req = $self->reqs->{$name};
            $compiled = "($req)" if $req;

            $optional = 0 unless $self->defaults->{$name};

            $compiled .= '?' if $optional;
        }

        # Add to block
        $block = "$compiled$block";
    }

    # Not rooted with a slash
    $regex = "$block$regex" if $block;

    $regex = qr/^$regex$/;
    $self->regex($regex);

    return $self;
}

sub _tokenize {
    my $self = shift;

    my $pattern      = $self->pattern;
    my $quote_end    = $self->quote_end;
    my $quote_start  = $self->quote_start;
    my $symbol_start = $self->symbol_start;

    my $tree     = [];
    my $state    = 'text';
    my $quote    = 0;
    my $segments = 0;

    while (my $char = substr $pattern, 0, 1, '') {

        # Quote start
        if ($char eq $quote_start && !$quote) {
            $quote = 1;
            next;
        }

        # Quote end
        if ($char eq $quote_end && $quote) {
            $state = 'text';
            $quote = 0;
            next;
        }

        # Slash
        if ($char eq '/') {
            $segments++;

            push @$tree, ['slash'];
            $state = 'text';
        }

        # Symbol start
        elsif ($char eq $symbol_start) {
            push @$tree, ['symbol', ''];
            $state = 'symbol';
        }

        # Symbol
        elsif ($state eq 'symbol') {
            $tree->[-1]->[-1] .= $char;
        }

        # Text
        elsif ($state eq 'text') {

            # New text element
            unless ($tree->[-1]->[0] eq 'text') {
                push @$tree, ['text', $char];
                next;
            }

            # More text
            $tree->[-1]->[-1] .= $char;
        }
    }

    # Cleanup segments
    $segments-- if $tree->[-1]->[0] eq 'slash';
    $self->segments($segments);

    $self->tree($tree);

    return $self;
}

1;
__END__

=head1 NAME

MojoX::Routes::Pattern - Pattern

=head1 SYNOPSIS

    use MojoX::Routes::Pattern;

    my $pattern = MojoX::Routes::Pattern->new;

=head1 DESCRIPTION

L<MojoX::Routes::Pattern> is a route pattern container.

=head2 ATTRIBUTES

=head2 C<defaults>

    my $defaults = $pattern->defaults;
    $pattern     = $pattern->defaults({foo => 'bar'});

=head2 C<pattern>

    my $pattern = $pattern->pattern;
    $pattern    = $pattern->pattern('/:foo/:bar');

=head2 C<quote_end>

    my $quote = $pattern->quote_end;
    $pattern  = $pattern->quote_end(')');

=head2 C<quote_start>

    my $quote = $pattern->quote_start;
    $pattern  = $pattern->quote_start('(');

=head2 C<regex>

    my $regex = $pattern->regex;
    $pattern  = $pattern->regex(qr/\/foo/);

=head2 C<reqs>

=head2 C<requirements>

    my $requirements = $pattern->reqs;
    my $requirements = $pattern->requirements;
    $pattern         = $pattern->reqs({foo => qr/\w+/});
    $pattern         = $pattern->requirements({foo => qr/\w+/});

=head2 C<segments>

    my $segments = $pattern->segments;
    $pattern     = $pattern->segments(4);

=head2 C<symbol_start>

    my $symbol_start = $pattern->symbol_start;
    $pattern         = $pattern->symbol_start(':');

=head2 C<symbols>

    my $symbols = $pattern->symbols;
    $pattern    = $pattern->symbols(['foo', 'bar']);

=head2 C<tree>

    my $tree = $pattern->tree;
    $pattern = $pattern->tree([ ... ]);

=head1 METHODS

L<MojoX::Routes::Pattern> inherits all methods from L<Mojo::Base> and
implements the follwing the ones.

=head2 C<new>

    my $pattern = MojoX::Routes::Pattern->new('/:controller/:action',
        action => qr/\w+/
    );

=head2 C<match>

    my $result = $pattern->match('/foo/bar');

=head2 C<parse>

    $pattern = $pattern->parse('/:controller/:action', action => qr/\w+/);

=head2 C<render>

    my $string = $pattern->render(action => 'foo');
    my $string = $pattern->render({action => 'foo'});

=cut