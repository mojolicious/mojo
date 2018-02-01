package Mojo::Promise;
use Mojo::Base -base;

use Mojo::IOLoop;
use Scalar::Util qw(blessed weaken);
use Mojo::Util 'deprecated';

has ioloop => sub { Mojo::IOLoop->singleton };

sub all {
  my ($class, @promises) = @_;

  # DEPRECATED!
  unshift(@promises, $class)
    and deprecated 'Use of Mojo::Promise::all as instance method is DEPRECATED'
    if ref $class;

  my $all = $class->new;

  my $results   = [];
  my $remaining = scalar @promises;
  for my $i (0 .. $#promises) {
    if ($promises[$i] && blessed $promises[$i] && $promises[$i]->can('then')) {
      $promises[$i]->then(
        sub {
          $results->[$i] = [@_];
          $all->resolve(@$results) if --$remaining <= 0;
        },
        sub { $all->reject(@_) }
      );
    } else {
      $results->[$i] = [$promises[$i]];
      --$remaining;
    }
  }
  $all->resolve(@$results) if $remaining <= 0; # all non-promises

  return $all;
}

sub catch { shift->then(undef, shift) }

sub finally {
  my ($self, $finally) = @_;

  my $new = $self->_clone;
  push @{$self->{resolve}}, sub { _finally($new, $finally, 'resolve', @_) };
  push @{$self->{reject}},  sub { _finally($new, $finally, 'reject',  @_) };

  $self->_defer if $self->{result};

  return $new;
}

sub race {
  my ($class, @promises) = @_;

  # DEPRECATED!
  unshift(@promises, $class)
    and deprecated 'Use of Mojo::Promise::race as instance method is DEPRECATED'
    if ref $class;

  my $new = $class->new;
  # make Promise of non-Promise so don't unfairly beat already-settled Promise
  @promises = map {
    ($_ && blessed $_ && $_->can('then')) ? $_ : $class->new->resolve($_)
  } @promises;
  $_->then(sub { $new->resolve(@_) }, sub { $new->reject(@_) }) for @promises;

  return $new;
}

sub reject  { shift->_settle('reject',  @_) }
sub resolve { shift->_settle('resolve', @_) }

sub then {
  my ($self, $resolve, $reject) = @_;

  my $new = $self->_clone;
  push @{$self->{resolve}}, sub { _then($new, $resolve, 'resolve', @_) };
  push @{$self->{reject}},  sub { _then($new, $reject,  'reject',  @_) };

  $self->_defer if $self->{result};

  return $new;
}

sub wait {
  my $self = shift;
  return if (my $loop = $self->ioloop)->is_running;
  $self->finally(sub { $loop->stop });
  $loop->start;
}

sub _clone {
  my $self  = shift;
  my $clone = $self->new;
  weaken $clone->ioloop($self->ioloop)->{ioloop};
  return $clone;
}

sub _defer {
  my $self = shift;

  return unless my $result = $self->{result};
  my $cbs = $self->{status} eq 'resolve' ? $self->{resolve} : $self->{reject};
  @{$self}{qw(resolve reject)} = ([], []);

  $self->ioloop->next_tick(sub { $_->(@$result) for @$cbs });
}

sub _finally {
  my ($new, $finally, $method, @result) = @_;
  my ($res) = eval { $finally->(@result) };
  return $new->$method(@result)
    unless $res && blessed $res && $res->can('then');
  $res->then(sub { $new->$method(@result) }, sub { $new->$method(@result) });
}

sub _settle {
  my ($self, $status) = (shift, shift);

  $_[0]->then(sub { $self->resolve(@_); () }, sub { $self->reject(@_); () })
    and return $self
    if blessed $_[0] && $_[0]->can('then');

  return $self if $self->{result};

  @{$self}{qw(result status)} = ([@_], $status);
  $self->_defer;
  return $self;
}

sub _then {
  my ($new, $cb, $method, @result) = @_;

  return $new->$method(@result) unless defined $cb;

  my @res;
  return $new->reject($@) unless eval { @res = $cb->(@result); 1 };
  return $new->resolve(@res);

}

1;

=encoding utf8

=head1 NAME

Mojo::Promise - Promises/A+

=head1 SYNOPSIS

  use Mojo::Promise;
  use Mojo::UserAgent;

  # Wrap continuation-passing style APIs with promises
  my $ua = Mojo::UserAgent->new;
  sub get {
    my $promise = Mojo::Promise->new;
    $ua->get(@_ => sub {
      my ($ua, $tx) = @_;
      my $err = $tx->error;
      $promise->resolve($tx) if !$err || $err->{code};
      $promise->reject($err->{message});
    });
    return $promise;
  }

  # Perform non-blocking operations sequentially
  get('http://mojolicious.org')->then(sub {
    my $mojo = shift;
    say $mojo->res->code;
    return get('http://metacpan.org');
  })->then(sub {
    my $cpan = shift;
    say $cpan->res->code;
  })->catch(sub {
    my $err = shift;
    warn "Something went wrong: $err";
  })->wait;

  # Synchronize non-blocking operations (all)
  my $mojo = get('http://mojolicious.org');
  my $cpan = get('http://metacpan.org');
  Mojo::Promise->all($mojo, $cpan)->then(sub {
    my ($mojo, $cpan) = @_;
    say $mojo->[0]->res->code;
    say $cpan->[0]->res->code;
  })->catch(sub {
    my $err = shift;
    warn "Something went wrong: $err";
  })->wait;

  # Synchronize non-blocking operations (race)
  my $mojo = get('http://mojolicious.org');
  my $cpan = get('http://metacpan.org');
  Mojo::Promise->race($mojo, $cpan)->then(sub {
    my $tx = shift;
    say $tx->req->url, ' won!';
  })->catch(sub {
    my $err = shift;
    warn "Something went wrong: $err";
  })->wait;

=head1 DESCRIPTION

L<Mojo::Promise> is a Perl-ish implementation of
L<Promises/A+|https://promisesaplus.com>.

=head1 ATTRIBUTES

L<Mojo::Promise> implements the following attributes.

=head2 ioloop

  my $loop = $promise->ioloop;
  $promise = $promise->ioloop(Mojo::IOLoop->new);

Event loop object to control, defaults to the global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::Promise> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 all

  my $new = Mojo::Promise->all(@promises_or_other);

  my $new = Mojo::Promise->all('hello', Mojo::Promise->new->resolve('there'));
  my @data;
  $new->then(sub { @data = @_ }); # @data will be (['hello'], ['there'])

Returns a new L<Mojo::Promise> object that either fulfills when all of the
passed arguments have fulfilled, or rejects as soon as one of them rejects.
Any of the arguments that are not "then-able" (do not have a C<then>
method) will be treated as though they are promises that have fulfilled
immediately with that value.

If the returned promise fulfills, it is fulfilled with the values from
the fulfilled promises in the same order as the passed promises.
The values from each fulfilled promise are within an array-ref, so that
there are the same number of arguments to the returned promise's C<then>
as there were arguments to C<all>.

This method can be useful for aggregating results of multiple promises.

=head2 catch

  my $new = $promise->catch(sub {...});

Appends a rejection handler callback to the promise, and returns a new
L<Mojo::Promise> object resolving to the return value of the callback if it is
called, or to its original fulfillment value if the promise is instead
fulfilled.

  # Longer version
  my $new = $promise->then(undef, sub {...});

  # Pass along the rejection reason
  $promise->catch(sub {
    my @reason = @_;
    warn "Something went wrong: $reason[0]";
    return @reason;
  });

  # Change the rejection reason
  $promise->catch(sub {
    my @reason = @_;
    return "This is bad: $reason[0]";
  });

=head2 finally

  my $new = $promise->finally(sub {...});

Appends a fulfillment and rejection handler to the promise, and returns a new
L<Mojo::Promise> object resolving to the original fulfillment value or rejection
reason.

  # Do something on fulfillment and rejection
  $promise->finally(sub {
    my @value_or_reason = @_;
    say "We are done!";
  });

=head2 race

  my $new = Mojo::Promise->race(@promises);

Returns a new L<Mojo::Promise> object that fulfills or rejects as soon as one of
the passed arguments fulfills or rejects, with the value or reason from that
promise. Any of the arguments that are not "then-able" (do not have a C<then>
method) will be treated as though they are promises that have fulfilled
immediately with that value.

=head2 reject

  $promise = $promise->reject(@reason);

Reject the promise with one or more rejection reasons.

  # Generate rejected promise
  my $promise = Mojo::Promise->new->reject('Something went wrong: Oops');

=head2 resolve

  $promise = $promise->resolve(@value);

Resolve the promise with one or more fulfillment values.

  # Generate fulfilled promise
  my $promise = Mojo::Promise->new->resolve('The result is: 24');

=head2 then

  my $new = $promise->then(sub {...});
  my $new = $promise->then(sub {...}, sub {...});
  my $new = $promise->then(undef, sub {...});

Appends fulfillment and rejection handlers to the promise, and returns a new
L<Mojo::Promise> object resolving to the return value of the called handler.

  # Pass along the fulfillment value or rejection reason
  $promise->then(
    sub {
      my @value = @_;
      say "The result is $value[0]";
      return @value;
    },
    sub {
      my @reason = @_;
      warn "Something went wrong: $reason[0]";
      return @reason;
    }
  );

  # Change the fulfillment value or rejection reason
  $promise->then(
    sub {
      my @value = @_;
      return "This is good: $value[0]";
    },
    sub {
      my @reason = @_;
      return "This is bad: $reason[0]";
    }
  );

=head2 wait

  $promise->wait;

Start L</"ioloop"> and stop it again once the promise has been fulfilled or
rejected, does nothing when L</"ioloop"> is already running.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
