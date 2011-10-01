package Mojolicious::Command::cpanify;
use Mojo::Base 'Mojo::Command';

use File::Basename 'basename';
use Getopt::Long 'GetOptions';
use Mojo::UserAgent;

has description => <<'EOF';
Upload distribution to CPAN.
EOF
has usage => <<"EOF";
usage: $0 cpanify [OPTIONS] [FILE]

  mojo cpanify -u sri -p secr3t Mojolicious-Plugin-MyPlugin-0.01.tar.gz

These options are available:
  --password <password>   PAUSE password.
  --user <name>           PAUSE username.
EOF

# "Hooray! A happy ending for the rich people!"
sub run {
  my $self = shift;

  # Options
  local @ARGV = @_;
  my $password = my $user = '';
  GetOptions(
    'password=s' => sub { $password = $_[1] },
    'user=s'     => sub { $user     = $_[1] }
  );
  my $file = shift @ARGV;
  die $self->usage unless $file;

  # Upload
  my $ua = Mojo::UserAgent->new;
  $ua->detect_proxy;
  $ua->log->level('fatal');
  my $tx = $ua->post_form(
    "https://$user:$password\@pause.perl.org/pause/authenquery" => {
      HIDDENNAME                        => $user,
      CAN_MULTIPART                     => 1,
      pause99_add_uri_upload            => basename($file),
      SUBMIT_pause99_add_uri_httpupload => " Upload this file from my disk ",
      pause99_add_uri_uri               => "",
      pause99_add_uri_httpupload        => {file => $file},
    }
  );

  # Error
  unless ($tx->success) {
    my $code = $tx->res->code || '';
    my $message = $tx->error;
    if    ($code eq '401') { $message = 'Wrong username or password.' }
    elsif ($code eq '409') { $message = 'File already exists on CPAN.' }
    die qq/Problem uploading file "$file". ($message)\n/;
  }
  say 'Upload sucessful!';
}

1;
__END__

=head1 NAME

Mojolicious::Command::cpanify - Cpanify command

=head1 SYNOPSIS

  use Mojolicious::Command::cpanify;

  my $cpanify = Mojolicious::Command::cpanify->new;
  $cpanify->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::cpanify> is a CPAN uploader.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojolicious::Command::cpanify> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

  my $description = $cpanify->description;
  $cpanify        = $cpanify->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $cpanify->usage;
  $cpanify  = $cpanify->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::cpanify> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

  $cpanify->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
