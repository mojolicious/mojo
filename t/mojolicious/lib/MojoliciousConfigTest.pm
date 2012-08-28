package MojoliciousConfigTest;
use Mojo::Base 'Mojolicious';

sub startup { shift->plugin('Config') }

1;
