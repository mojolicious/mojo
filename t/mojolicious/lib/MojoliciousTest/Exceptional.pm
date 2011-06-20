package MojoliciousTest::Exceptional;
use Mojo::Base 'Mojolicious::Controller';

# "Dr. Zoidberg, can you note the time and declare the patient legally dead?
#  Can I! That’s my specialty!"
sub render_exception {
  my ($self, $e) = @_;
  $self->render_text("Action died: $e");
}

sub render_not_found { shift->render_json({error => 'not found!'}) }

sub this_one_dies { die "doh!\n" }

sub this_one_might_die {
  die "double doh!\n" unless shift->req->headers->header('X-DoNotDie');
  1;
}

1;
