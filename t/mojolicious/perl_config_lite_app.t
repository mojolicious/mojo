use Mojo::Base -strict;
use Test::Mojo;
use Test::More;
use Mojo::File qw(curfile tempdir);
use Mojolicious::Lite;

my $conffile = curfile->sibling('perl_config_lite_app.conf')->to_abs;

plugin 'Config';
is_deeply app->config,
  {foo => "bar", utf => "утф", file => $conffile->to_string, line => 7},
  'right value';

my $tempdir = tempdir CLEANUP => 1;

{
  my $cf = $tempdir->child(qq{foo bar.conf});
  $conffile->copy_to($cf);
  my $config = plugin Config => {file => $cf};
  is_deeply $config,
    {foo => "bar", utf => "утф", file => $cf->to_string, line => 7},
    'space in path works';
}
SKIP: {
  skip 'these filenames are all invalid in Windows anyway', 5
    if $^O eq 'MSWin32';
  {
    my $cf = $tempdir->child(qq{foo\rquz\tbaz.conf});
    $conffile->copy_to($cf);
    my $config = plugin Config => {file => $cf};
    is_deeply $config,
      {foo => "bar", utf => "утф", file => $cf->to_string, line => 7},
      'other whitespace in path works';
  }
  {
    my $cf = $tempdir->child(qq{quz"baz.conf});
    $conffile->copy_to($cf);
    my $config = plugin Config => {file => $cf};
    like $config->{file}, qr/\(eval /,
      'filename doesn\'t work with quote in path';
    is_deeply $config,
      {foo => "bar", utf => "утф", file => $config->{file}, line => 7},
      'line still works with quote in path';
  }
  {
    my $cf = $tempdir->child(qq{hello\nworld.conf});
    $conffile->copy_to($cf);
    my $config = plugin Config => {file => $cf};
    like $config->{file}, qr/\(eval /,
      'filename doesn\'t work with newline in path';
    is_deeply $config,
      {foo => "bar", utf => "утф", file => $config->{file}, line => 7},
      'line still works with newline in path';
  }
}

done_testing();
