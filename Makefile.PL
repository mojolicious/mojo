#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use 5.008001;

use strict;
use warnings;

# Son, when you participate in sporting events,
# it's not whether you win or lose, it's how drunk you get.
use ExtUtils::MakeMaker;

my $mm = $ExtUtils::MakeMaker::VERSION;

# We only use core modules, so you shouldn't have to install anything besides
# Perl 5.8.1!
WriteMakefile(
    NAME         => 'Mojo',
    VERSION_FROM => 'lib/Mojo.pm',
    ABSTRACT     => 'Web Framework',
    AUTHOR       => 'Sebastian Riedel <sri@cpan.org>',

    ($mm < 6.3002 ? () : ('LICENSE' => 'artistic_2')),

    (   $mm < 6.46
        ? ()
        : ( META_MERGE => {
                requires  => {perl => '5.008001'},
                resources => {
                    homepage => 'http://mojolicious.org',
                    license  => 'http://dev.perl.org/licenses/',
                    MailingList =>
                      'http://lists.kraih.com/cgi-bin/mailman/listinfo',
                    repository => 'http://github.com/kraih/mojo/tree/master'
                },
                no_index => {directory => [qw/t/]}
            },
            META_ADD => {
                build_requires     => {},
                configure_requires => {}
            },
        )
    ),

    EXE_FILES => ['script/mojo', 'script/mojolicious'],
    PREREQ_PM => {
        'Carp'                  => 0,
        'Cwd'                   => 0,
        'Data::Dumper'          => 0,
        'Digest::MD5'           => 0,
        'Encode'                => 0,
        'ExtUtils::MakeMaker'   => 0,
        'File::Basename'        => 0,
        'File::Copy'            => 0,
        'File::Path'            => 0,
        'File::Spec'            => 0,
        'File::Spec::Functions' => 0,
        'File::Temp'            => 0,
        'FindBin'               => 0,
        'Getopt::Long'          => 0,
        'IO::File'              => 0,
        'IO::Poll'              => 0,
        'IO::Socket'            => 0,
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
    test => {TESTS => 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t'}
);

# Devel::Cover support
sub MY::postamble {
    qq/
testcover :
\t cover -delete && \\
   HARNESS_PERL_SWITCHES=-MDevel::Cover \$(MAKE) test && \\
   cover
/
}
