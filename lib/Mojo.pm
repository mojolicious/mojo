package Mojo;
use Mojo::Base -strict;

# "Professor: These old Doomsday devices are dangerously unstable. I'll rest
#             easier not knowing where they are."
use Mojo::Log;
use Mojo::Transaction::HTTP;
use Mojo::Util 'deprecated';

# DEPRECATED!
sub build_tx {
  deprecated 'Mojo::build_tx is DEPRECATED in favor of Mojolicious::build_tx';
  Mojo::Transaction::HTTP->new;
}

# DEPRECATED!
sub config {
  deprecated 'Mojo::config is DEPRECATED in favor of Mojolicious::config';
  Mojo::Util::_stash(config => @_);
}

# DEPRECATED!
sub log {
  deprecated 'Mojo::log is DEPRECATED in favor of Mojolicious::log';
  my $self = shift;
  return $self->{log} unless @_;
  $self->{log} = Mojo::Log->new // shift;
  return $self;
}

# DEPRECATED!
sub handler {
  deprecated 'Mojo::handler is DEPRECATED in favor of Mojolicious::handler';
}

1;

=encoding utf8

=head1 NAME

Mojo - Web development toolkit

=head1 SYNOPSIS

  # HTTP/WebSocket user agent
  use Mojo::UserAgent;
  my $ua = Mojo::UserAgent->new;
  say $ua->get('www.mojolicious.org')->result->headers->server;

  # HTML/XML DOM parser with CSS selectors
  use Mojo::DOM;
  my $dom = Mojo::DOM->new('<div><b>Hello Mojo!</b></div>');
  say $dom->at('div > b')->text;

  # Perl-ish templates
  use Mojo::Template;
  my $mt = Mojo::Template->new(vars => 1);
  say $mt->render('Hello <%= $what %>!', {what => 'Mojo'});

  # HTTP/WebSocket server
  use Mojo::Server::Daemon;
  my $daemon = Mojo::Server::Daemon->new(listen => ['http://*:8080']);
  $daemon->unsubscribe('request')->on(request => sub {
    my ($daemon, $tx) = @_;
    $tx->res->code(200);
    $tx->res->body('Hello Mojo!');
    $tx->resume;
  });
  $daemon->run;

  # Event loop
  use Mojo::IOLoop;
  for my $seconds (1 .. 5) {
    Mojo::IOLoop->timer($seconds => sub { say $seconds });
  }
  Mojo::IOLoop->start;

=head1 DESCRIPTION

A powerful web development toolkit, with all the basic tools and helpers needed
to write simple web applications and higher level web frameworks, such as
L<Mojolicious>. Some of the most commonly used tools are L<Mojo::UserAgent>,
L<Mojo::DOM>, L<Mojo::JSON>, L<Mojo::Server::Daemon>, L<Mojo::Server::Prefork>,
L<Mojo::IOLoop> and L<Mojo::Template>.

See L<Mojolicious::Guides> for more!

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
