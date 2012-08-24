% my $c = shift;
% $c->stash(handler => 'epl');
Hello Mojo from the template <%= $c->url_for %>! <%= $c->stash('msg') %>
