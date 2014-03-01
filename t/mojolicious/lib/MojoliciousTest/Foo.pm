package MojoliciousTest::Foo;
use Mojo::Base 'Mojolicious::Controller';

sub DESTROY { shift->stash->{destroyed} = 1 }

sub config {
  my $self = shift;
  $self->render(text => $self->stash('config')->{test});
}

sub fun { shift->render }

sub index {
  my $self = shift;
  $self->layout('default');
  $self->stash(handler => 'xpl', msg => 'Hello World!');
}

sub longpoll {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished} = 1 });
  $self->write_chunk(
    sub {
      shift->write_chunk('Poll!' => sub { shift->write_chunk('') });
    }
  );
}

sub plugin_camel_case {
  my $self = shift;
  $self->render(text => $self->some_plugin);
}

sub plugin_upper_case {
  my $self = shift;
  $self->render(text => $self->upper_case_test_plugin);
}

sub session_domain {
  my $self = shift;
  $self->session(user => 'Bender');
  $self->render(text => 'Bender rockzzz!');
}

sub something {
  my $self = shift;
  $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  $self->render(text => $self->url_for('something', something => '42'));
}

sub stage1 {
  my $self = shift;

  # Authenticated
  return 1 if $self->req->headers->header('X-Pass');

  # Fail
  $self->render(text => 'Go away!');
  return undef;
}

sub stage2 { return shift->some_plugin }

sub suspended {
  my $self = shift;

  $self->res->headers->append('X-Suspended' => $self->match->current);
  Mojo::IOLoop->next_tick(
    sub {
      $self->res->headers->append('X-Suspended' => $self->match->current);
      $self->continue;
    }
  );

  return 0;
}

sub syntaxerror { shift->render('syntaxerror', format => 'html') }

sub templateless { shift->render(handler => 'test') }

sub test {
  my $self = shift;
  $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  $self->render(text => $self->url_for(controller => 'bar'));
}

sub url_for_missing {
  my $self = shift;
  $self->render(text => $self->url_for('does_not_exist', something => '42'));
}

sub willdie { die 'for some reason' }

sub withBlock { shift->render(template => 'withblock') }

sub withlayout { shift->stash(template => 'WithGreenLayout') }

1;
__DATA__

@@ foo/fun.html.ep
Have fun!\

@@ just/some/template.html.epl
Development template with high precedence.

@@ some/static/file.txt
Development static file with high precedence.
