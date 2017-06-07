#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::IOLoop;
use Data::Dumper;

get '/' => sub {
  my $self = shift;
  $self->render('index');
};

my $ua = Mojo::UserAgent->new;
my $delay;
Mojo::IOLoop->recurring(5 => sub {
  print("enter timer\n");

  # Non-blocking concurent requests (does work inside a running event loop)
  $delay = Mojo::IOLoop->delay(sub {
    my ($delay, @titles) = @_;
    print (Dumper(@titles));
  });
  for my $url ('mojolicio.us', 'www.cpan.org') {
    my $end = $delay->begin(0);
    $ua->get($url => sub {
      my ($ua, $tx) = @_;
      $end->($tx->res->dom->at('title')->text);
    });
  }
  $delay->wait unless Mojo::IOLoop->is_running;
  print("leave timer\n");
});


app->start;
__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
Welcome to the Mojolicious real-time web framework!

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
