package LoginApp::Controller::Login;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub index ($self) {
  my $user = $self->param('user') || '';
  my $pass = $self->param('pass') || '';
  return $self->render unless $self->users->check($user, $pass);

  $self->session(user => $user);
  $self->flash(message => 'Thanks for logging in.');
  $self->redirect_to('protected');
}

sub logged_in ($self) {
  return 1 if $self->session('user');
  $self->redirect_to('index');
  return undef;
}

sub logout ($self) {
  $self->session(expires => 1);
  $self->redirect_to('index');
}

1;
