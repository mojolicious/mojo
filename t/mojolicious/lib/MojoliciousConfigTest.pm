package MojoliciousConfigTest;
use Mojo::Base 'Mojolicious';

# "Aw, he looks like a little insane drunken angel."
sub startup { shift->plugin('Config') }

1;
