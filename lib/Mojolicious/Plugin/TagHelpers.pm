package Mojolicious::Plugin::TagHelpers;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::ByteStream;
use Mojo::Util 'xml_escape';

sub register {
  my ($self, $app) = @_;

  # Text field variations
  my @time = qw(date datetime month time week);
  for my $name (@time, qw(color email number range search tel text url)) {
    $app->helper("${name}_field" => sub { _input(@_, type => $name) });
  }

  $app->helper(check_box =>
      sub { _input(shift, shift, value => shift, @_, type => 'checkbox') });
  $app->helper(file_field =>
      sub { shift; _tag('input', name => shift, @_, type => 'file') });

  $app->helper(form_for     => \&_form_for);
  $app->helper(hidden_field => \&_hidden_field);
  $app->helper(image => sub { _tag('img', src => shift->url_for(shift), @_) });
  $app->helper(input_tag => sub { _input(@_) });
  $app->helper(javascript => \&_javascript);
  $app->helper(link_to    => \&_link_to);

  $app->helper(password_field =>
      sub { shift; _tag('input', name => shift, @_, type => 'password') });
  $app->helper(radio_button =>
      sub { _input(shift, shift, value => shift, @_, type => 'radio') });

  $app->helper(select_field  => \&_select_field);
  $app->helper(stylesheet    => \&_stylesheet);
  $app->helper(submit_button => \&_submit_button);

  # "t" is just a shortcut for the "tag" helper
  $app->helper($_ => sub { shift; _tag(@_) }) for qw(t tag);

  $app->helper(text_area => \&_text_area);
}

sub _form_for {
  my ($self, @url) = (shift, shift);
  push @url, shift if ref $_[0] eq 'HASH';

  # POST detection
  my @post;
  if (my $r = $self->app->routes->find($url[0])) {
    my %methods = (GET => 1, POST => 1);
    do {
      my @via = @{$r->via || []};
      %methods = map { $_ => 1 } grep { $methods{$_} } @via if @via;
    } while $r = $r->parent;
    @post = (method => 'POST') if $methods{POST} && !$methods{GET};
  }

  return _tag('form', action => $self->url_for(@url), @post, @_);
}

sub _hidden_field {
  my $self = shift;
  my %attrs = (name => shift, value => shift, @_, type => 'hidden');
  return _tag('input', %attrs);
}

sub _input {
  my ($self, $name) = (shift, shift);
  my %attrs = @_ % 2 ? (value => shift, @_) : @_;

  # Special selection value
  my @values = $self->param($name);
  my $type = $attrs{type} || '';
  if (@values && $type ne 'submit') {

    # Checkbox or radiobutton
    my $value = $attrs{value} // '';
    if ($type eq 'checkbox' || $type eq 'radio') {
      $attrs{value} = $value;
      $attrs{checked} = 'checked' if grep { $_ eq $value } @values;
    }

    # Others
    else { $attrs{value} = $values[0] }

    return _tag('input', name => $name, %attrs);
  }

  # Empty tag
  return _tag('input', name => $name, %attrs);
}

sub _javascript {
  my $self = shift;

  # CDATA
  my $cb = sub {''};
  if (ref $_[-1] eq 'CODE') {
    my $old = pop;
    $cb = sub { "//<![CDATA[\n" . $old->() . "\n//]]>" }
  }

  # URL
  my $src = @_ % 2 ? $self->url_for(shift) : undef;

  return _tag('script', @_, $src ? (src => $src) : (), $cb);
}

sub _link_to {
  my ($self, $content) = (shift, shift);
  my @url = ($content);

  # Content
  unless (defined $_[-1] && ref $_[-1] eq 'CODE') {
    @url = (shift);
    push @_, $content;
  }

  # Captures
  push @url, shift if ref $_[0] eq 'HASH';

  return _tag('a', href => $self->url_for(@url), @_);
}

sub _select_field {
  my ($self, $name, $options, %attrs) = (shift, shift, shift, @_);

  # "option" callback
  my %values = map { $_ => 1 } $self->param($name);
  my $option = sub {

    # Pair
    my $pair = shift;
    $pair = [$pair => $pair] unless ref $pair eq 'ARRAY';

    # Attributes
    my %attrs = (value => $pair->[1]);
    $attrs{selected} = 'selected' if exists $values{$pair->[1]};
    %attrs = (%attrs, @$pair[2 .. $#$pair]);

    return _tag('option', %attrs, sub { xml_escape $pair->[0] });
  };

  # "optgroup" callback
  my $optgroup = sub {

    # Parts
    my $parts = '';
    for my $group (@$options) {

      # "optgroup" tag
      if (ref $group eq 'HASH') {
        my ($label, $values) = each %$group;
        my $content = join '', map { $option->($_) } @$values;
        $parts .= _tag('optgroup', label => $label, sub {$content});
      }

      # "option" tag
      else { $parts .= $option->($group) }
    }

    return $parts;
  };

  return _tag('select', name => $name, %attrs, $optgroup);
}

sub _stylesheet {
  my $self = shift;

  # CDATA
  my $cb;
  if (ref $_[-1] eq 'CODE') {
    my $old = pop;
    $cb = sub { "/*<![CDATA[*/\n" . $old->() . "\n/*]]>*/" }
  }

  # "link" or "style" tag
  my $href = @_ % 2 ? $self->url_for(shift) : undef;
  return $href
    ? _tag('link', rel => 'stylesheet', href => $href, media => 'screen', @_)
    : _tag('style', @_, $cb);
}

sub _submit_button {
  my $self = shift;
  return _tag('input', value => shift // 'Ok', @_, type => 'submit');
}

sub _tag {
  my $name = shift;

  # Content
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my $content = @_ % 2 ? pop : undef;

  # Start tag
  my $tag = "<$name";

  # Attributes
  my %attrs = @_;
  for my $key (sort keys %attrs) {
    $tag .= qq{ $key="} . xml_escape($attrs{$key} // '') . '"';
  }

  # End tag
  if ($cb || defined $content) {
    $tag .= '>' . ($cb ? $cb->() : xml_escape($content)) . "</$name>";
  }

  # Empty element
  else { $tag .= ' />' }

  # Prevent escaping
  return Mojo::ByteStream->new($tag);
}

sub _text_area {
  my ($self, $name) = (shift, shift);

  # Content
  my $cb = ref $_[-1] eq 'CODE' ? pop : sub {''};
  my $content = @_ % 2 ? shift : undef;

  # Make sure content is wrapped
  if (defined($content = $self->param($name) // $content)) {
    $cb = sub { xml_escape $content }
  }

  return _tag('textarea', name => $name, @_, $cb);
}

1;

=head1 NAME

Mojolicious::Plugin::TagHelpers - Tag helpers plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('TagHelpers');

  # Mojolicious::Lite
  plugin 'TagHelpers';

=head1 DESCRIPTION

L<Mojolicious::Plugin::TagHelpers> is a collection of HTML tag helpers for
L<Mojolicious>.

Most form helpers can automatically pick up previous input values and will
show them as default. You can also use
L<Mojolicious::Plugin::DefaultHelpers/"param"> to set them manually and let
necessary attributes always be generated automatically.

  % param country => 'germany' unless param 'country';
  <%= radio_button country => 'germany' %> Germany
  <%= radio_button country => 'france'  %> France
  <%= radio_button country => 'uk'      %> UK

This is a core plugin, that means it is always enabled and its code a good
example for learning how to build new plugins, you're welcome to fork it.

=head1 HELPERS

L<Mojolicious::Plugin::TagHelpers> implements the following helpers.

=head2 check_box

  %= check_box employed => 1
  %= check_box employed => 1, id => 'foo'

Generate checkbox input element. Previous input values will automatically get
picked up and shown as default.

  <input name="employed" type="checkbox" value="1" />
  <input id="foo" name="employed" type="checkbox" value="1" />

=head2 color_field

  %= color_field 'background'
  %= color_field background => '#ffffff'
  %= color_field background => '#ffffff', id => 'foo'

Generate color input element. Previous input values will automatically get
picked up and shown as default.

  <input name="background" type="color" />
  <input name="background" type="color" value="#ffffff" />
  <input id="foo" name="background" type="color" value="#ffffff" />

=head2 date_field

  %= date_field 'end'
  %= date_field end => '2012-12-21'
  %= date_field end => '2012-12-21', id => 'foo'

Generate date input element. Previous input values will automatically get
picked up and shown as default.

  <input name="end" type="date" />
  <input name="end" type="date" value="2012-12-21" />
  <input id="foo" name="end" type="date" value="2012-12-21" />

=head2 datetime_field

  %= datetime_field 'end'
  %= datetime_field end => '2012-12-21T23:59:59Z'
  %= datetime_field end => '2012-12-21T23:59:59Z', id => 'foo'

Generate datetime input element. Previous input values will automatically get
picked up and shown as default.

  <input name="end" type="datetime" />
  <input name="end" type="datetime" value="2012-12-21T23:59:59Z" />
  <input id="foo" name="end" type="datetime" value="2012-12-21T23:59:59Z" />

=head2 email_field

  %= email_field 'notify'
  %= email_field notify => 'nospam@example.com'
  %= email_field notify => 'nospam@example.com', id => 'foo'

Generate email input element. Previous input values will automatically get
picked up and shown as default.

  <input name="notify" type="email" />
  <input name="notify" type="email" value="nospam@example.com" />
  <input id="foo" name="notify" type="email" value="nospam@example.com" />

=head2 file_field

  %= file_field 'avatar'
  %= file_field 'avatar', id => 'foo'

Generate file input element.

  <input name="avatar" type="file" />
  <input id="foo" name="avatar" type="file" />

=head2 form_for

  %= form_for login => begin
    %= text_field 'first_name'
    %= submit_button
  % end
  %= form_for login => {format => 'txt'} => (method => 'POST') => begin
    %= text_field 'first_name'
    %= submit_button
  % end
  %= form_for '/login' => (method => 'POST') => begin
    %= text_field 'first_name'
    %= submit_button
  % end
  %= form_for 'http://example.com/login' => (method => 'POST') => begin
    %= text_field 'first_name'
    %= submit_button
  % end

Generate portable form for route, path or URL. For routes that allow C<POST>
but not C<GET>, a C<method> attribute will be automatically added.

  <form action="/path/to/login">
    <input name="first_name" />
    <input value="Ok" type="submit" />
  </form>
  <form action="/path/to/login.txt" method="POST">
    <input name="first_name" />
    <input value="Ok" type="submit" />
  </form>
  <form action="/login" method="POST">
    <input name="first_name" />
    <input value="Ok" type="submit" />
  </form>
  <form action="http://example.com/login" method="POST">
    <input name="first_name" />
    <input value="Ok" type="submit" />
  </form>

=head2 hidden_field

  %= hidden_field foo => 'bar'
  %= hidden_field foo => 'bar', id => 'bar'

Generate hidden input element.

  <input name="foo" type="hidden" value="bar" />
  <input id="bar" name="foo" type="hidden" value="bar" />

=head2 image

  %= image '/images/foo.png'
  %= image '/images/foo.png', alt => 'Foo'

Generate image tag.

  <img src="/images/foo.png" />
  <img alt="Foo" src="/images/foo.png" />

=head2 input_tag

  %= input_tag 'first_name'
  %= input_tag first_name => 'Default name'
  %= input_tag 'employed', type => 'checkbox'

Generate form input element. Previous input values will automatically get
picked up and shown as default.

  <input name="first_name" />
  <input name="first_name" value="Default name" />
  <input name="employed" type="checkbox" />

=head2 javascript

  %= javascript '/script.js'
  %= javascript begin
    var a = 'b';
  % end

Generate portable script tag for C<Javascript> asset.

  <script src="/script.js" />
  <script><![CDATA[
    var a = 'b';
  ]]></script>

=head2 link_to

  %= link_to Home => 'index'
  %= link_to Home => 'index' => {format => 'txt'} => (class => 'links')
  %= link_to index => {format => 'txt'} => (class => 'links') => begin
    Home
  % end
  %= link_to Contact => Mojo::URL->new('mailto:sri@example.com')
  <%= link_to index => begin %>Home<% end %>
  <%= link_to '/path/to/file' => begin %>File<% end %>
  <%= link_to 'http://mojolicio.us' => begin %>Mojolicious<% end %>
  <%= link_to url_for->query(foo => 'bar')->to_abs => begin %>Retry<% end %>

Generate portable link to route, path or URL, defaults to using the
capitalized link target as content.

  <a href="/path/to/index">Home</a>
  <a class="links" href="/path/to/index.txt">Home</a>
  <a class="links" href="/path/to/index.txt">
    Home
  </a>
  <a href="mailto:sri@example.com">Contact</a>
  <a href="/path/to/index">Home</a>
  <a href="/path/to/file">File</a>
  <a href="http://mojolicio.us">Mojolicious</a>
  <a href="http://127.0.0.1:3000/current/path?foo=bar">Retry</a>

=head2 month_field

  %= month_field 'vacation'
  %= month_field vacation => '2012-12'
  %= month_field vacation => '2012-12', id => 'foo'

Generate month input element. Previous input values will automatically get
picked up and shown as default.

  <input name="vacation" type="month" />
  <input name="vacation" type="month" value="2012-12" />
  <input id="foo" name="vacation" type="month" value="2012-12" />

=head2 number_field

  %= number_field 'age'
  %= number_field age => 25
  %= number_field age => 25, id => 'foo', min => 0, max => 200

Generate number input element. Previous input values will automatically get
picked up and shown as default.

  <input name="age" type="number" />
  <input name="age" type="number" value="25" />
  <input id="foo" max="200" min="0" name="age" type="number" value="25" />

=head2 password_field

  %= password_field 'pass'
  %= password_field 'pass', id => 'foo'

Generate password input element.

  <input name="pass" type="password" />
  <input id="foo" name="pass" type="password" />

=head2 radio_button

  %= radio_button country => 'germany'
  %= radio_button country => 'germany', id => 'foo'

Generate radio input element. Previous input values will automatically get
picked up and shown as default.

  <input name="country" type="radio" value="germany" />
  <input id="foo" name="country" type="radio" value="germany" />

=head2 range_field

  %= range_field 'age'
  %= range_field age => 25
  %= range_field age => 25, id => 'foo', min => 0, max => 200

Generate range input element. Previous input values will automatically get
picked up and shown as default.

  <input name="age" type="range" />
  <input name="age" type="range" value="25" />
  <input id="foo" max="200" min="200" name="age" type="range" value="25" />

=head2 search_field

  %= search_field 'q'
  %= search_field q => 'perl'
  %= search_field q => 'perl', id => 'foo'

Generate search input element. Previous input values will automatically get
picked up and shown as default.

  <input name="q" type="search" />
  <input name="q" type="search" value="perl" />
  <input id="foo" name="q" type="search" value="perl" />

=head2 select_field

  %= select_field language => [qw(de en)]
  %= select_field language => [qw(de en)], id => 'lang'
  %= select_field country => [[Germany => 'de'], 'en']
  %= select_field country => [{Europe => [[Germany => 'de'], 'en']}]
  %= select_field country => [[Germany => 'de', class => 'europe'], 'en']

Generate select, option and optgroup elements. Previous input values will
automatically get picked up and shown as default.

  <select name="language">
    <option value="de">de</option>
    <option value="en">en</option>
  </select>
  <select id="lang" name="language">
    <option value="de">de</option>
    <option value="en">en</option>
  </select>
  <select name="country">
    <option value="de">Germany</option>
    <option value="en">en</option>
  </select>
  <select id="lang" name="language">
    <optgroup label="Europe">
      <option value="de">Germany</option>
      <option value="en">en</option>
    </optgroup>
  </select>
  <select name="country">
    <option class="europe" value="de">Germany</option>
    <option value="en">en</option>
  </select>

=head2 stylesheet

  %= stylesheet '/foo.css'
  %= stylesheet begin
    body {color: #000}
  % end

Generate portable style or link tag for C<CSS> asset.

  <link href="/foo.css" media="screen" rel="stylesheet" />
  <style><![CDATA[
    body {color: #000}
  ]]></style>

=head2 submit_button

  %= submit_button
  %= submit_button 'Ok!', id => 'foo'

Generate submit input element.

  <input type="submit" value="Ok" />
  <input id="foo" type="submit" value="Ok!" />

=head2 t

  %=t div => 'some & content'

Alias for C<tag>.

  <div>some &amp; content</div>

=head2 tag

  %= tag 'div'
  %= tag 'div', id => 'foo'
  %= tag div => 'some & content'
  <%= tag div => begin %>some & content<% end %>

HTML tag generator.

  <div />
  <div id="foo" />
  <div>some &amp; content</div>
  <div>some & content</div>

Very useful for reuse in more specific tag helpers.

  $self->tag('div');
  $self->tag('div', id => 'foo');
  $self->tag(div => sub { 'Content' });

Results are automatically wrapped in L<Mojo::ByteStream> objects to prevent
accidental double escaping.

=head2 tel_field

  %= tel_field 'work'
  %= tel_field work => '123456789'
  %= tel_field work => '123456789', id => 'foo'

Generate tel input element. Previous input values will automatically get
picked up and shown as default.

  <input name="work" type="tel" />
  <input name="work" type="tel" value="123456789" />
  <input id="foo" name="work" type="tel" value="123456789" />

=head2 text_area

  %= text_area 'foo'
  %= text_area 'foo', cols => 40
  %= text_area foo => 'Default!', cols => 40
  %= text_area foo => (cols => 40) => begin
    Default!
  % end

Generate textarea element. Previous input values will automatically get picked
up and shown as default.

  <textarea name="foo"></textarea>
  <textarea cols="40" name="foo"></textarea>
  <textarea cols="40" name="foo">Default!</textarea>
  <textarea cols="40" name="foo">
    Default!
  </textarea>

=head2 text_field

  %= text_field 'first_name'
  %= text_field first_name => 'Default name'
  %= text_field first_name => 'Default name', class => 'user'

Generate text input element. Previous input values will automatically get
picked up and shown as default.

  <input name="first_name" type="text" />
  <input name="first_name" type="text" value="Default name" />
  <input class="user" name="first_name" type="text" value="Default name" />

=head2 time_field

  %= time_field 'start'
  %= time_field start => '23:59:59'
  %= time_field start => '23:59:59', id => 'foo'

Generate time input element. Previous input values will automatically get
picked up and shown as default.

  <input name="start" type="time" />
  <input name="start" type="time" value="23:59:59" />
  <input id="foo" name="start" type="time" value="23:59:59" />

=head2 url_field

  %= url_field 'address'
  %= url_field address => 'http://mojolicio.us'
  %= url_field address => 'http://mojolicio.us', id => 'foo'

Generate url input element. Previous input values will automatically get
picked up and shown as default.

  <input name="address" type="url" />
  <input name="address" type="url" value="http://mojolicio.us" />
  <input id="foo" name="address" type="url" value="http://mojolicio.us" />

=head2 week_field

  %= week_field 'vacation'
  %= week_field vacation => '2012-W17'
  %= week_field vacation => '2012-W17', id => 'foo'

Generate week input element. Previous input values will automatically get
picked up and shown as default.

  <input name="vacation" type="week" />
  <input name="vacation" type="week" value="2012-W17" />
  <input id="foo" name="vacation" type="week" value="2012-W17" />

=head1 METHODS

L<Mojolicious::Plugin::TagHelpers> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
