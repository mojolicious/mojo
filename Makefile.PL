use 5.010001;

use strict;
use warnings;

# "Son, when you participate in sporting events,
#  it's not whether you win or lose, it's how drunk you get."
use ExtUtils::MakeMaker;

my ($mm) = $ExtUtils::MakeMaker::VERSION =~ /^([^_]+)/;

WriteMakefile(
  NAME         => 'Mojolicious',
  VERSION_FROM => 'lib/Mojolicious.pm',
  ABSTRACT     => 'Real-time web framework',
  AUTHOR       => 'Sebastian Riedel <sri@cpan.org>',

  ($mm < 6.3002 ? () : ('LICENSE' => 'artistic_2')),

  ( $mm < 6.46
    ? ()
    : (
      META_MERGE => {
        requires  => {perl => '5.010001'},
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
    're'                     => 0,
    'B'                      => 0,
    'Carp'                   => 0,
    'Config'                 => 0,
    'Cwd'                    => 0,
    'Data::Dumper'           => 0,
    'Digest::MD5'            => 0,
    'Digest::SHA'            => 0,
    'Encode'                 => 0,
    'Errno'                  => 0,
    'Exporter'               => 0,
    'ExtUtils::MakeMaker'    => 0,
    'Fcntl'                  => 0,
    'File::Basename'         => 0,
    'File::Copy'             => 0,
    'File::Find'             => 0,
    'File::Path'             => 0,
    'File::Spec'             => 0,
    'File::Temp'             => 0,
    'FindBin'                => 0,
    'Getopt::Long'           => 0,
    'I18N::LangTags'         => 0,
    'I18N::LangTags::Detect' => 0,
    'IO::File'               => 0,
    'IO::Poll'               => 0,
    'IO::Socket'             => 0,
    'IO::Socket::INET'       => 0,
    'List::Util'             => 0,
    'Locale::Maketext'       => 0,
    'MIME::Base64'           => 0,
    'MIME::QuotedPrint'      => 0,
    'Pod::Simple::HTML'      => 0,
    'Pod::Simple::Search'    => 0,
    'POSIX'                  => 0,
    'Scalar::Util'           => 0,
    'Socket'                 => 0,
    'Sys::Hostname'          => 0,
    'Test::Harness'          => 0,
    'Test::More'             => 0,
    'Time::HiRes'            => 0
  },
  test => {TESTS => 't/*.t t/*/*.t'}
);
