package Mojolicious::Command::cpanify;
use Mojo::Base 'Mojolicious::Command';

use File::Basename 'basename';
use Mojo::UserAgent;

has description => "Upload distribution to CPAN.\n";
has usage       => <<"EOF";
usage: $0 cpanify [OPTIONS] [FILE]

  mojo cpanify -u sri -p secr3t Mojolicious-Plugin-MyPlugin-0.01.tar.gz

These options are available:
  -p, --password <password>   PAUSE password.
  -u, --user <name>           PAUSE username.

Term::ReadKey is used to prompt for a password if none is given via command option.
EOF

sub run {
  my ($self, @args) = @_;

  # Options
  $self->_options(
    \@args,
    'p|password=s' => \(my $password),
    'u|user=s'     => \(my $user     = '')
  );
  die $self->usage unless my $file = shift @args;

  unless ( defined $password ) {
    $password = $self->_read_password;
  }

  # Upload
  my $tx = Mojo::UserAgent->new->detect_proxy->post_form(
    "https://$user:$password\@pause.perl.org/pause/authenquery" => {
      HIDDENNAME                        => $user,
      CAN_MULTIPART                     => 1,
      pause99_add_uri_upload            => basename($file),
      SUBMIT_pause99_add_uri_httpupload => ' Upload this file from my disk ',
      pause99_add_uri_uri               => '',
      pause99_add_uri_httpupload        => {file => $file},
    }
  );

  # Error
  unless ($tx->success) {
    my $code = $tx->res->code || '';
    my $msg = $tx->error;
    if    ($code eq '401') { $msg = 'Wrong username or password.' }
    elsif ($code eq '409') { $msg = 'File already exists on CPAN.' }
    die qq{Problem uploading file "$file". ($msg)\n};
  }
  say 'Upload successful!';
}

sub _read_password {
  my $self = shift;

  # set to autoflush STDOUT
  # this isn't strictly necessary, but it places the newline after reading the password
  # and before any error from the uploader
  local $| = 1;

  eval 'use Term::ReadKey (); 1' or die "Prompt for password requires Term::ReadKey installed\n";
  print "Password: ";

  # set password mode
  Term::ReadKey::ReadMode(2);
  chomp( my $password = <STDIN> );

  # return to previous read mode
  Term::ReadKey::ReadMode(0);
  print "\n";

  return $password;
}

1;

=head1 NAME

Mojolicious::Command::cpanify - Cpanify command

=head1 SYNOPSIS

  use Mojolicious::Command::cpanify;

  my $cpanify = Mojolicious::Command::cpanify->new;
  $cpanify->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::cpanify> uploads files to CPAN.

=head1 ATTRIBUTES

L<Mojolicious::Command::cpanify> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 C<description>

  my $description = $cpanify->description;
  $cpanify        = $cpanify->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $cpanify->usage;
  $cpanify  = $cpanify->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::cpanify> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 C<run>

  $cpanify->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
