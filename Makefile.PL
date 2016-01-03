use 5.010001;

use strict;
use warnings;

use ExtUtils::MakeMaker;

# Pod::Simple 3.09 first shipped with Perl 5.11.2
# JSON::PP 2.27103 first shipped with Perl 5.13.9
# Time::Local 1.2 first shipped with Perl 5.13.9
# IO::Socket::IP 0.37 first shipped with Perl 5.21.11
WriteMakefile(
  NAME         => 'Mojolicious',
  VERSION_FROM => 'lib/Mojolicious.pm',
  ABSTRACT     => 'Real-time web framework',
  AUTHOR       => 'Sebastian Riedel <sri@cpan.org>',
  LICENSE      => 'artistic_2',
  META_MERGE   => {
    dynamic_config => 0,
    'meta-spec'    => {version => 2},
    no_index       => {directory => ['examples', 't']},
    prereqs        => {runtime => {requires => {perl => '5.010001'}}},
    resources      => {
      bugtracker => {web => 'https://github.com/kraih/mojo/issues'},
      homepage   => 'http://mojolicious.org',
      license    => ['http://www.opensource.org/licenses/artistic-license-2.0'],
      repository => {
        type => 'git',
        url  => 'https://github.com/kraih/mojo.git',
        web  => 'https://github.com/kraih/mojo',
      },
      x_IRC => 'irc://irc.perl.org/#mojo'
    },
  },
  PREREQ_PM => {
    'IO::Socket::IP' => '0.37',
    'JSON::PP'       => '2.27103',
    'Pod::Simple'    => '3.09',
    'Time::Local'    => '1.2'
  },
  EXE_FILES => ['script/hypnotoad', 'script/mojo', 'script/morbo'],
  test => {TESTS => 't/*.t t/*/*.t'}
);
