package MojoX::Dispatcher::QooxdooRpc;

use strict;
use warnings;

use Mojo::JSON;
use base 'Mojolicious::Controller';

sub handle_request {
    my $self = shift;
    
    my ($package, $method, @params, $id, $cross_domain, $data, $reply, $error);
    
    my $debug = 1;

    # instantiate a JSON encoder - decoder object.
    my $json = Mojo::JSON->new;
    
    # We have to differentiate between POST and GET requests, because
    # the data is not sent in the same place..
    
    # non cross domain POST calls. 
    if ($self->req->method eq 'POST'){
        # Data comes as JSON object, so fetch a reference to it
        $data           = $json->decode($self->req->body);
        $id             = $data->{id};
        $cross_domain   = 0;
    }
    
    # cross-domain GET requests
    elsif ($self->req->method eq 'GET'){
        $data           = $json->decode($self->param('_ScriptTransport_data'));
        $id             = $self->param('_ScriptTransport_id');
        $cross_domain   = 1;
    }
    else{
        print "wrong request method: ".$self->req->method."\n" if $debug;
        
        # I don't know any method to send a reply to qooxdoo if it doesn't send POST or GET
        # return will simply generate a "Transport error 0: Unknown status code" in qooxdoo
        return;
    }
    
    # Getting available services from stash
    my $services = $self->stash('services');
    
    # Check if desired service is available
    $package = $data->{service};
    
    if (not exists $services->{$package}){
        $reply = $json->encode({error => {origin => 1, message => "Service $package not available", code=> '9838'}, id => $id});
        _send_reply($reply, $id, $cross_domain, $self) and return;
    }
    
    # Check if method is not private (marked with a leading underscore)
    $method = $data->{method};
    
    if ($method =~ /^_/){
        $reply = $json->encode({error => {origin => 1, message => "private method ${package}::$method not accessible", code=> '9838'}, id => $id});
        _send_reply($reply, $id, $cross_domain, $self) and return;
    }
    
    # Check if method is 
    if ($method !~ /^[a-zA-Z_]+$/){
        $reply = $json->encode({error => {origin => 1, message => "methods should only contain a-z, A-Z and _, $method is forbidden", code=> '9838'}, id => $id});
        _send_reply($reply, $id, $cross_domain, $self) and return;
    }
    
    
    @params  = @{$data->{params}}; # is a reference, so "unpack" it
    
    
    # invocation of method in class according to request 
    eval{
        no strict 'refs';
        $reply = $services->{$package}->$method(@params);
    };
    if ($@){  
        # error is an object 
        #   which must contain 'code' (qooxdoo error code) and 'message'
        if (ref $@){ 
            # qooxdoo expects a json
            $reply = $json->encode({error => {origin => 1, message => $@->message(), code=>$@->code()}, id => $id});
        }
        
        # error is a string 
        else{
            $reply = $json->encode({error => {origin => 1, message => "error while processing ${package}::$method: $@", code=> '9838'}, id => $id});
        }
    }
    
    # no error occurred
    else{
        $reply = $json->encode({id => $id, result => $reply});
    }
    
    _send_reply($reply, $id, $cross_domain, $self);
}

sub _send_reply{
    my ($reply, $id, $cross_domain, $self) = @_;
    
    if ($cross_domain){
        # for GET requests, qooxdoo expects us to send a javascript method
        # and to wrap our json a litte bit more
        $self->res->headers->content_type('application/javascript');
        $reply = "qx.io.remote.transport.Script._requestFinished( $id, " . $reply . ");";
    }
    
    $self->render(text => $reply);
}

1

__END__

=head1 NAME

MojoX::Dispatcher::QooxdooRpc - Dispatcher for Qooxdoo Rpc Calls

=head1 SYNOPSIS

 # lib/your-application.pm
 sub startup {
    my $self = shift;

    # choose your directory for services:
    use lib ('qooxdoo-services'); 
    
    # use all services you want to use
    # (and omit everything you don't want to expose)
    use Test;
    
    # instantiate all services
    my $services= {
        Test => new Test(),
        
    };
    
    
    # add a route to the Qooxdoo dispatcher and route to it
    my $r = $self->routes;
    $r->route('/qooxdoo')->to('#handle_request', services => $services, namespace => 'MojoX::Dispatcher::QooxdooRpc');
        
 }

    

=head1 DESCRIPTION

L<Mojolicous::Plugin::QooxdooRpx> is a plugin that dispatches incoming
rpc requests from a qooxdoo application to your services and renders
a (hopefully) valid qooxdoo reply.

=head2 Options

=over 4

=item ...

=back

=head1 METHODS

L<Mojolicious::Plugin::QooxdooRpx> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register plugin hooks in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
