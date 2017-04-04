package Mojo::Server::Morbo::Backend::TestBackend;
use Mojo::Base 'Mojo::Server::Morbo::Backend';

sub modified_files { return ['always_changed'] }

1
