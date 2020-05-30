use 5.016;

use strict;
use warnings;

use ExtUtils::MakeMaker;

# Sub::Util 1.41 first shipped with Perl 5.21.4
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
    no_index       => {directory => [qw(examples t)], package => [qw(Mojo::Server::PSGI::_IO Mojo::Util::_Guard)],},
    prereqs        => {runtime => {requires => {perl => '5.016'}}},
    resources      => {
      bugtracker => {web => 'https://github.com/mojolicious/mojo/issues'},
      homepage   => 'https://mojolicious.org',
      license    => ['http://www.opensource.org/licenses/artistic-license-2.0'],
      repository => {
        type => 'git',
        url  => 'https://github.com/mojolicious/mojo.git',
        web  => 'https://github.com/mojolicious/mojo',
      },
      x_IRC => 'irc://irc.freenode.net/#mojo'
    },
  },
  PREREQ_PM => {'IO::Socket::IP' => '0.37', 'Sub::Util' => '1.41'},
  EXE_FILES => ['script/hypnotoad', 'script/mojo', 'script/morbo'],
  test      => {TESTS => 't/*.t t/*/*.t'}
);
