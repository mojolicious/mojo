use Mojo::Base -strict;

use Test::More tests => 85;

# "Hello, my name is Mr. Burns. I believe you have a letter for me.
#  Okay Mr. Burns, what's your first name.
#  I don't know."
use Mojo::Cookie::Response;
use Mojo::URL;
use Mojo::UserAgent::CookieJar;

# Session cookie
my $jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain => '.kraih.com',
    path   => '/',
    name   => 'just',
    value  => 'works'
  )
);
my @cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'foo',   'right name';
is $cookies[0]->value, 'bar',   'right value';
is $cookies[1]->name,  'just',  'right name';
is $cookies[1]->value, 'works', 'right value';
is $cookies[2], undef, 'no third cookie';
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'foo',   'right name';
is $cookies[0]->value, 'bar',   'right value';
is $cookies[1]->name,  'just',  'right name';
is $cookies[1]->value, 'works', 'right value';
is $cookies[2], undef, 'no third cookie';
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'foo',   'right name';
is $cookies[0]->value, 'bar',   'right value';
is $cookies[1]->name,  'just',  'right name';
is $cookies[1]->value, 'works', 'right value';
is $cookies[2], undef, 'no third cookie';
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'foo',   'right name';
is $cookies[0]->value, 'bar',   'right value';
is $cookies[1]->name,  'just',  'right name';
is $cookies[1]->value, 'works', 'right value';
is $cookies[2], undef, 'no third cookie';
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'foo',   'right name';
is $cookies[0]->value, 'bar',   'right value';
is $cookies[1]->name,  'just',  'right name';
is $cookies[1]->value, 'works', 'right value';
is $cookies[2], undef, 'no third cookie';

# Leading dot
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => '.kraih.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  )
);
@cookies = $jar->find(Mojo::URL->new('http://labs.kraih.com/foo'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'bar', 'right value';
is $cookies[1], undef, 'no second cookie';
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'bar', 'right value';
is $cookies[1], undef, 'no second cookie';

# "localhost"
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'localhost',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain => 'foo.localhost',
    path   => '/foo',
    name   => 'bar',
    value  => 'baz'
  )
);
@cookies = $jar->find(Mojo::URL->new('http://localhost/foo'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'bar', 'right value';
is $cookies[1], undef, 'no second cookie';
@cookies = $jar->find(Mojo::URL->new('http://foo.localhost/foo'));
is $cookies[0]->name,  'bar', 'right name';
is $cookies[0]->value, 'baz', 'right value';
is $cookies[1]->name,  'foo', 'right name';
is $cookies[1]->value, 'bar', 'right value';
is $cookies[2], undef, 'no third cookie';
@cookies = $jar->find(Mojo::URL->new('http://foo.bar.localhost/foo'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'bar', 'right value';
is $cookies[1], undef, 'no second cookie';
@cookies = $jar->find(Mojo::URL->new('http://bar.foo.localhost/foo'));
is $cookies[0]->name,  'bar', 'right name';
is $cookies[0]->value, 'baz', 'right value';
is $cookies[1]->name,  'foo', 'right name';
is $cookies[1]->value, 'bar', 'right value';
is $cookies[2], undef, 'no third cookie';

# Random top-level domain
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'bar',
    value  => 'baz'
  )
);
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'bar', 'right name';
is $cookies[0]->value, 'baz', 'right value';
is $cookies[1], undef, 'no second cookie';
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'bar', 'right name';
is $cookies[0]->value, 'baz', 'right value';
is $cookies[1], undef, 'no second cookie';

# Huge cookie
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain => 'www.kraih.com',
    path   => '/',
    name   => 'just',
    value  => 'works'
  ),
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'huge',
    value  => 'foo' x 4096
  )
);
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'bar', 'right value';
is $cookies[1], undef, 'no second cookie';

# Expired cookies
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain  => 'labs.kraih.com',
    path    => '/',
    name    => 'baz',
    value   => '24',
    max_age => -1
  )
);
my $expired = Mojo::Cookie::Response->new(
  domain => 'labs.kraih.com',
  path   => '/',
  name   => 'baz',
  value  => '23'
);
$jar->add($expired->expires(time - 1));
@cookies = $jar->find(Mojo::URL->new('http://labs.kraih.com/foo'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'bar', 'right value';
is $cookies[1], undef, 'no second cookie';

# Multiple cookies
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain  => 'labs.kraih.com',
    path    => '/',
    name    => 'baz',
    value   => 23,
    max_age => 60
  )
);
@cookies = $jar->find(Mojo::URL->new('http://labs.kraih.com/foo'));
is $cookies[0]->name,  'baz', 'right name';
is $cookies[0]->value, 23,    'right value';
is $cookies[1]->name,  'foo', 'right name';
is $cookies[1]->value, 'bar', 'right value';
is $cookies[2], undef, 'no third cookie';

# Multiple cookies with leading dot
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => '.kraih.com',
    path   => '/',
    name   => 'foo',
    value  => 'bar'
  ),
  Mojo::Cookie::Response->new(
    domain => '.labs.kraih.com',
    path   => '/',
    name   => 'baz',
    value  => 'yada'
  ),
  Mojo::Cookie::Response->new(
    domain => '.kraih.com',
    path   => '/',
    name   => 'this',
    value  => 'that'
  )
);
@cookies = $jar->find(Mojo::URL->new('http://labs.kraih.com/fo'));
is $cookies[0]->name,  'baz',  'right name';
is $cookies[0]->value, 'yada', 'right value';
is $cookies[1]->name,  'foo',  'right name';
is $cookies[1]->value, 'bar',  'right value';
is $cookies[2]->name,  'this', 'right name';
is $cookies[2]->value, 'that', 'right value';
is $cookies[3], undef, 'no fourth cookie';

# Replace cookie
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar1'
  ),
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar2'
  )
);
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'foo',  'right name';
is $cookies[0]->value, 'bar2', 'right value';
is $cookies[1], undef, 'no second cookie';

# Switch between secure and normal cookies
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'foo',
    secure => 1
  )
);
@cookies = $jar->find(Mojo::URL->new('https://kraih.com/foo'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'foo', 'right value';
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is @cookies, 0, 'no insecure cookie';
$jar->add(
  Mojo::Cookie::Response->new(
    domain => 'kraih.com',
    path   => '/foo',
    name   => 'foo',
    value  => 'bar'
  )
);
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'bar', 'right value';
@cookies = $jar->find(Mojo::URL->new('https://kraih.com/foo'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'bar', 'right value';
is $cookies[1], undef, 'no second cookie';

# "(" in path
$jar = Mojo::UserAgent::CookieJar->new;
$jar->add(
  Mojo::Cookie::Response->new(
    domain => '.kraih.com',
    path   => '/foo(bar',
    name   => 'foo',
    value  => 'bar'
  )
);
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo%28bar'));
is $cookies[0]->name,  'foo', 'right name';
is $cookies[0]->value, 'bar', 'right value';
is $cookies[1], undef, 'no second cookie';

