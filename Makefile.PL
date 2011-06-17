#!/usr/bin/env perl

use 5.008007;

use strict;
use warnings;

# "Son, when you participate in sporting events,
#  it's not whether you win or lose, it's how drunk you get."
use ExtUtils::MakeMaker;

my ($mm) = $ExtUtils::MakeMaker::VERSION =~ /^([^_]+)/;

# We only use core modules, so you shouldn't have to install anything besides
# Perl 5.8.7!
WriteMakefile(
  NAME         => 'Mojolicious',
  VERSION_FROM => 'lib/Mojolicious.pm',
  ABSTRACT     => 'The Web In A Box!',
  AUTHOR       => 'Sebastian Riedel <sri@cpan.org>',

  ($mm < 6.3002 ? () : ('LICENSE' => 'artistic_2')),

  ( $mm < 6.46
    ? ()
    : (
      META_MERGE => {
        requires  => {perl => '5.008007'},
        resources => {
          homepage    => 'http://mojolicio.us',
          license     => 'http://dev.perl.org/licenses/',
          MailingList => 'http://groups.google.com/group/mojolicious',
          repository  => 'http://github.com/kraih/mojo',
          bugtracker  => 'http://github.com/kraih/mojo/issues'
        },
        no_index => {directory => [qw/t/]}
      },
      META_ADD => {
        build_requires     => {},
        configure_requires => {}
      },
    )
  ),

  EXE_FILES => ['script/hypnotoad', 'script/mojo', 'script/morbo'],
  PREREQ_PM => {
    'B'                     => 0,
    'Carp'                  => 0,
    'Cwd'                   => 0,
    'Data::Dumper'          => 0,
    'Digest::MD5'           => 0,
    'Encode'                => 0,
    'Errno'                 => 0,
    'Exporter'              => 0,
    'ExtUtils::MakeMaker'   => 0,
    'File::Basename'        => 0,
    'File::Copy'            => 0,
    'File::Path'            => 0,
    'File::Spec'            => 0,
    'File::Spec::Functions' => 0,
    'File::Temp'            => 0,
    'FindBin'               => 0,
    'Getopt::Long'          => 0,
    'I18N::LangTags'        => 0,
    'IO::File'              => 0,
    'IO::Poll'              => 0,
    'IO::Socket'            => 0,
    'List::Util'            => 0,
    'Locale::Maketext'      => 0,
    'MIME::Base64'          => 0,
    'MIME::QuotedPrint'     => 0,
    'POSIX'                 => 0,
    'Scalar::Util'          => 0,
    'Sys::Hostname'         => 0,
    'Test::Builder'         => 0,
    'Test::Harness'         => 0,
    'Test::More'            => 0,
    'Time::HiRes'           => 0
  },
  test => {TESTS => 't/*.t t/*/*.t'}
);

# Using Perl 5.8.x is a bad idea though
warn <<'EOF' unless $] >= 5.010;

*******************************************************************************
You are using Perl 5.8, a version that has reached the end of its life a few
years ago and which is no longer getting updated by the community.
It contains very serious flaws, especially around the regular expression
engine, that will never get fixed and are likely to put your applications at
risk.
While your operating system vendor might keep it compiling on their platform,
they will not fix these issues.

Therefore we highly recommend that you upgrade as soon as possible!
*******************************************************************************

EOF
