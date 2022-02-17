use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::File qw(path tempdir);
use Mojolicious::Command;

subtest 'Application' => sub {
  my $command = Mojolicious::Command->new;
  isa_ok $command->app, 'Mojolicious', 'right application';
};

subtest 'Creating directories' => sub {
  my $command = Mojolicious::Command->new;
  my $cwd     = path;
  my $dir     = tempdir;
  my $buffer  = '';
  chdir $dir;
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $command->create_rel_dir('foo/bar');
  }
  like $buffer, qr/[mkdir]/, 'right output';
  ok -d path('foo', 'bar'), 'directory exists';

  $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $command->create_rel_dir('foo/bar');
  }
  like $buffer, qr/\[exist\]/, 'right output';
  chdir $cwd;
};

subtest 'Generating files' => sub {
  my $command = Mojolicious::Command->new;
  my $cwd     = path;
  my $dir     = tempdir;
  is $command->rel_file('foo/bar.txt')->basename, 'bar.txt', 'right result';

  my $template = <<'EOF';
@@ foo_bar
% my $word = shift;
just <%= $word %>!
@@ dies
% die 'template error';
@@ bar_baz
just <%= $word %> too!
EOF
  open my $data, '<', \$template;
  no strict 'refs';
  *{"Mojolicious::Command::DATA"} = $data;
  chdir $dir;
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $command->template({})->render_to_rel_file('foo_bar', 'bar/baz.txt', 'works');
  }
  like $buffer, qr/\[mkdir\].*\[write\]/s, 'right output';
  open my $txt, '<', $command->rel_file('bar/baz.txt');
  is join('', <$txt>), "just works!\n", 'right result';

  $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $command->template({vars => 1})->render_to_rel_file('bar_baz', 'bar/two.txt', {word => 'works'});
  }
  like $buffer, qr/\[exist\].*\[write\]/s, 'right output';
  open $txt, '<', $command->rel_file('bar/two.txt');
  is join('', <$txt>), "just works too!\n", 'right result';

  $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $command->chmod_rel_file('bar/baz.txt', 0700);
  }
  like $buffer, qr/\[chmod\]/, 'right output';
  ok -e $command->rel_file('bar/baz.txt'), 'file is executable';

  $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $command->write_rel_file('123.xml', "seems\nto\nwork");
  }
  like $buffer, qr/\[exist\].*\[write\]/s, 'right output';

  $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $command->write_rel_file('123.xml', 'fail');
  }
  like $buffer, qr/\[exist\]/, 'right output';
  open my $xml, '<', $command->rel_file('123.xml');
  is join('', <$xml>), "seems\nto\nwork", 'right result';

  eval { $command->render_data('dies') };
  like $@, qr/template error/, 'right error';
  chdir $cwd;
};

subtest 'Quiet' => sub {
  my $command = Mojolicious::Command->new;
  my $cwd     = path;
  my $dir     = tempdir;
  chdir $dir;
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDOUT = $handle;
    $command->quiet(1)->write_rel_file('123.xml', 'fail');
  }
  is $buffer, '', 'no output';
  chdir $cwd;
};

subtest 'Abstract methods' => sub {
  eval { Mojolicious::Command->run };
  like $@, qr/Method "run" not implemented by subclass/, 'right error';
};

done_testing();
