package Mojo::BaseUtil;

# Only using pure Perl as the only purpose of this module is to break a circular dependency involving Mojo::Base
use strict;
use warnings;
use feature ':5.16';

use Exporter  qw(import);
use Sub::Util qw(set_subname);

our @EXPORT_OK = (qw(class_to_path monkey_patch));

sub class_to_path { join '.', join('/', split(/::|'/, shift)), 'pm' }

sub monkey_patch {
  my ($class, %patch) = @_;
  no strict 'refs';
  no warnings 'redefine';
  *{"${class}::$_"} = set_subname("${class}::$_", $patch{$_}) for keys %patch;
}

1;

=encoding utf8

=head1 NAME

Mojo::BaseUtil - Common utility functions used in Mojo::Base, re-exported in Mojo::Util

=head1 SYNOPSIS

  use Mojo::BaseUtil qw(class_to_patch monkey_path);

  my $path = class_to_path 'Foo::Bar';
  monkey_patch 'MyApp', foo => sub { say 'Foo!' };

=head1 DESCRIPTION

L<Mojo::BaseUtil> provides functions to both L<Mojo::Base> and L<Mojo::Util>, so that C<Mojo::Base> does not have to
load the rest of L<Mojo::Util>, while preventing a circular dependency.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
