#!perl

# Copyright (C) 2008, Sebastian Riedel.

use 5.008001;

use strict;
use warnings;

# Son, when you participate in sporting events,
# it's not whether you win or lose, it's how drunk you get.
use ExtUtils::MakeMaker;

# We only use core modules, so you shouldn't have to install anything besides
# Perl 5.8!
WriteMakefile(
    NAME          => 'Mojo',
    VERSION_FROM  => 'lib/Mojo.pm',
    AUTHOR        => 'Sebastian Riedel <sri@cpan.org>',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    EXE_FILES     => ['bin/mojo', 'bin/mojolicious'],
    PREREQ_PM     => {
        'Carp'                  => 0,
        'Cwd'                   => 0,
        'Digest::MD5'           => 0,
        'Encode'                => 0,
        'File::Basename'        => 0,
        'File::Copy'            => 0,
        'File::Path'            => 0,
        'File::Spec'            => 0,
        'File::Spec::Functions' => 0,
        'File::Temp'            => 0,
        'FindBin'               => 0,
        'IO::File'              => 0,
        'IO::Select'            => 0,
        'IO::Socket'            => 0,
        'MIME::Base64'          => 0,
        'MIME::QuotedPrint'     => 0,
        'POSIX'                 => 0,
        'Test::Builder::Module' => 0,
        'Test::Harness'         => 0,
        'Test::More'            => 0
    },
    test          => {
        TESTS => 't/*.t t/*/*.t t/*/*/*.t'
    }
);
