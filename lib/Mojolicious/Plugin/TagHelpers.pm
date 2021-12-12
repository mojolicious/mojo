package Mojolicious::Plugin::TagHelpers;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::ByteStream;
use Mojo::DOM::HTML qw(tag_to_html);
use Scalar::Util qw(blessed);

sub register {
  my ($self, $app) = @_;

  # Text field variations
  my @time = qw(date month time week);
  for my $name (@time, qw(color email number range search tel text url)) {
    $app->helper("${name}_field" => sub { _input(@_, type => $name) });
  }
  $app->helper(datetime_field => sub { _input(@_, type => 'datetime-local') });

  my @helpers = (
    qw(csrf_field form_for hidden_field javascript label_for link_to select_field stylesheet submit_button),
    qw(tag_with_error text_area)
  );
  $app->helper($_ => __PACKAGE__->can("_$_")) for @helpers;

  $app->helper(button_to      => sub { _button_to(0, @_) });
  $app->helper(check_box      => sub { _input(@_, type => 'checkbox') });
  $app->helper(csrf_button_to => sub { _button_to(1, @_) });
  $app->helper(file_field     => sub { _empty_field('file', @_) });
  $app->helper(image          => sub { _tag('img', src => shift->url_for(shift), @_) });
  $app->helper(input_tag      => sub { _input(@_) });
  $app->helper(password_field => sub { _empty_field('password', @_) });
  $app->helper(radio_button   => sub { _input(@_, type => 'radio') });

  # "t" is just a shortcut for the "tag" helper
  $app->helper($_ => sub { shift; _tag(@_) }) for qw(t tag);
}

sub _button_to {
  my ($csrf, $c, $text) = (shift, shift, shift);
  my $prefix = $csrf ? _csrf_field($c) : '';
  return _form_for($c, @_, sub { $prefix . _submit_button($c, $text) });
}

sub _csrf_field {
  my $c = shift;
  return _hidden_field($c, csrf_token => $c->helpers->csrf_token, @_);
}

sub _empty_field {
  my ($type, $c, $name) = (shift, shift, shift);
  return _validation($c, $name, 'input', name => $name, @_, type => $type);
}

sub _form_for {
  my ($c, @url) = (shift, shift);
  push @url, shift if ref $_[0] eq 'HASH';

  # Method detection
  my $r      = $c->app->routes->lookup($url[0]);
  my $method = $r               ? $r->suggested_method : 'GET';
  my @post   = $method ne 'GET' ? (method => 'POST')   : ();

  my $url = $c->url_for(@url);
  $url->query({_method => $method}) if @post && $method ne 'POST';
  return _tag('form', action => $url, @post, @_);
}

sub _hidden_field {
  my ($c, $name, $value) = (shift, shift, shift);
  return _tag('input', name => $name, value => $value, @_, type => 'hidden');
}

sub _input {
  my ($c, $name) = (shift, shift);
  my %attrs = @_ % 2 ? (value => shift, @_) : @_;

  if (my @values = @{$c->every_param($name)}) {

    # Checkbox or radiobutton
    my $type = $attrs{type} || '';
    if ($type eq 'checkbox' || $type eq 'radio') {
      my $value = $attrs{value} // 'on';
      delete $attrs{checked};
      $attrs{checked} = undef if grep { $_ eq $value } @values;
    }

    # Others
    else { $attrs{value} = $values[-1] }
  }

  return _validation($c, $name, 'input', name => $name, %attrs);
}

sub _javascript {
  my $c       = shift;
  my $content = ref $_[-1] eq 'CODE' ? "//<![CDATA[\n" . pop->() . "\n//]]>" : '';
  my @src     = @_ % 2               ? (src => $c->url_for(shift))           : ();
  return _tag('script', @src, @_, sub {$content});
}

sub _label_for {
  my ($c, $name) = (shift, shift);
  my $content = ref $_[-1] eq 'CODE' ? pop : shift;
  return _validation($c, $name, 'label', for => $name, @_, $content);
}

sub _link_to {
  my ($c, $content) = (shift, shift);
  my @url = ($content);

  # Content
  unless (ref $_[-1] eq 'CODE') {
    @url = (shift);
    push @_, $content;
  }

  # Captures
  push @url, shift if ref $_[0] eq 'HASH';

  return _tag('a', href => $c->url_for(@url), @_);
}

sub _option {
  my ($values, $pair) = @_;

  $pair = [$pair => $pair] unless ref $pair eq 'ARRAY';
  my %attrs = (value => $pair->[1], @$pair[2 .. $#$pair]);
  delete $attrs{selected}  if keys %$values;
  $attrs{selected} = undef if $values->{$pair->[1]};

  return _tag('option', %attrs, $pair->[0]);
}

sub _select_field {
  my ($c, $name, $options, %attrs) = (shift, shift, shift, @_);

  my %values = map { $_ => 1 } grep {defined} @{$c->every_param($name)};

  my $groups = '';
  for my $group (@$options) {

    # "optgroup" tag
    if (blessed $group && $group->isa('Mojo::Collection')) {
      my ($label, $values, %attrs) = @$group;
      my $content = join '', map { _option(\%values, $_) } @$values;
      $groups .= _tag('optgroup', label => $label, %attrs, sub {$content});
    }

    # "option" tag
    else { $groups .= _option(\%values, $group) }
  }

  return _validation($c, $name, 'select', name => $name, %attrs, sub {$groups});
}

sub _stylesheet {
  my $c       = shift;
  my $content = ref $_[-1] eq 'CODE' ? "/*<![CDATA[*/\n" . pop->() . "\n/*]]>*/" : '';
  return _tag('style', @_, sub {$content}) unless @_ % 2;
  return _tag('link', rel => 'stylesheet', href => $c->url_for(shift), @_);
}

sub _submit_button {
  my ($c, $value) = (shift, shift // 'Ok');
  return _tag('input', value => $value, @_, type => 'submit');
}

sub _tag { Mojo::ByteStream->new(tag_to_html(@_)) }

sub _tag_with_error {
  my ($c, $tag) = (shift, shift);
  my ($content, %attrs) = (@_ % 2 ? pop : undef, @_);
  $attrs{class} .= $attrs{class} ? ' field-with-error' : 'field-with-error';
  return _tag($tag, %attrs, defined $content ? $content : ());
}

sub _text_area {
  my ($c, $name) = (shift, shift);

  my $cb      = ref $_[-1] eq 'CODE' ? pop   : undef;
  my $content = @_ % 2               ? shift : undef;
  $content = $c->param($name) // $content // $cb // '';

  return _validation($c, $name, 'textarea', name => $name, @_, $content);
}

sub _validation {
  my ($c, $name) = (shift, shift);
  return _tag(@_) unless $c->helpers->validation->has_error($name);
  return $c->helpers->tag_with_error(@_);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::TagHelpers - Tag helpers plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('TagHelpers');

  # Mojolicious::Lite
  plugin 'TagHelpers';

=head1 DESCRIPTION

L<Mojolicious::Plugin::TagHelpers> is a collection of HTML tag helpers for L<Mojolicious>, based on the L<HTML Living
Standard|https://html.spec.whatwg.org>.

Most form helpers can automatically pick up previous input values and will show them as default. You can also use
L<Mojolicious::Plugin::DefaultHelpers/"param"> to set them manually and let necessary attributes always be generated
automatically.

  % param country => 'germany' unless param 'country';
  <%= radio_button country => 'germany' %> Germany
  <%= radio_button country => 'france'  %> France
  <%= radio_button country => 'uk'      %> UK

For fields that failed validation with L<Mojolicious::Plugin::DefaultHelpers/"validation"> the C<field-with-error>
class will be automatically added through L</"tag_with_error">, to make styling with CSS easier.

  <input class="field-with-error" name="age" type="text" value="250">

This is a core plugin, that means it is always enabled and its code a good example for learning how to build new
plugins, you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available by default.

=head1 HELPERS

L<Mojolicious::Plugin::TagHelpers> implements the following helpers.

=head2 button_to

  %= button_to Test => 'some_get_route'
  %= button_to Test => some_get_route => {id => 23} => (class => 'menu')
  %= button_to Test => 'http://example.com/test' => (class => 'menu')
  %= button_to Remove => 'some_delete_route'

Generate portable C<form> tag with L</"form_for">, containing a single button.

  <form action="/path/to/get/route">
    <input type="submit" value="Test">
  </form>
  <form action="/path/to/get/route/23" class="menu">
    <input type="submit" value="Test">
  </form>
  <form action="http://example.com/test" class="menu">
    <input type="submit" value="Test">
  </form>
  <form action="/path/to/delete/route?_method=DELETE" method="POST">
    <input type="submit" value="Remove">
  </form>

=head2 check_box

  %= check_box 'employed'
  %= check_box employed => 1
  %= check_box employed => 1, checked => undef, id => 'foo'

Generate C<input> tag of type C<checkbox>. Previous input values will automatically get picked up and shown as default.

  <input name="employed" type="checkbox">
  <input name="employed" type="checkbox" value="1">
  <input checked id="foo" name="employed" type="checkbox" value="1">

=head2 color_field

  %= color_field 'background'
  %= color_field background => '#ffffff'
  %= color_field background => '#ffffff', id => 'foo'

Generate C<input> tag of type C<color>. Previous input values will automatically get picked up and shown as default.

  <input name="background" type="color">
  <input name="background" type="color" value="#ffffff">
  <input id="foo" name="background" type="color" value="#ffffff">

=head2 csrf_button_to

  %= csrf_button_to Remove => 'some_delete_route'

Same as L</"button_to">, but also includes a L</"csrf_field">.

  <form action="/path/to/delete/route?_method=DELETE" method="POST">
    <input name="csrf_token" type="hidden" value="fa6a08...">
    <input type="submit" value="Remove">
  </form>

=head2 csrf_field

  %= csrf_field

Generate C<input> tag of type C<hidden> with L<Mojolicious::Plugin::DefaultHelpers/"csrf_token">.

  <input name="csrf_token" type="hidden" value="fa6a08...">

=head2 date_field

  %= date_field 'end'
  %= date_field end => '2012-12-21'
  %= date_field end => '2012-12-21', id => 'foo'

Generate C<input> tag of type C<date>. Previous input values will automatically get picked up and shown as default.

  <input name="end" type="date">
  <input name="end" type="date" value="2012-12-21">
  <input id="foo" name="end" type="date" value="2012-12-21">

=head2 datetime_field

  %= datetime_field 'end'
  %= datetime_field end => '2012-12-21T23:59:59'
  %= datetime_field end => '2012-12-21T23:59:59', id => 'foo'

Generate C<input> tag of type C<datetime-local>. Previous input values will automatically get picked up and shown as
default.

  <input name="end" type="datetime-local">
  <input name="end" type="datetime-local" value="2012-12-21T23:59:59">
  <input id="foo" name="end" type="datetime-local" value="2012-12-21T23:59:59">

=head2 email_field

  %= email_field 'notify'
  %= email_field notify => 'nospam@example.com'
  %= email_field notify => 'nospam@example.com', id => 'foo'

Generate C<input> tag of type C<email>. Previous input values will automatically get picked up and shown as default.

  <input name="notify" type="email">
  <input name="notify" type="email" value="nospam@example.com">
  <input id="foo" name="notify" type="email" value="nospam@example.com">

=head2 file_field

  %= file_field 'avatar'
  %= file_field 'avatar', id => 'foo'

Generate C<input> tag of type C<file>.

  <input name="avatar" type="file">
  <input id="foo" name="avatar" type="file">

=head2 form_for

  %= form_for login => begin
    %= text_field 'first_name'
    %= submit_button
  % end
  %= form_for login => {format => 'txt'} => (method => 'POST') => begin
    %= text_field 'first_name'
    %= submit_button
  % end
  %= form_for '/login' => (enctype => 'multipart/form-data') => begin
    %= text_field 'first_name', disabled => 'disabled'
    %= submit_button
  % end
  %= form_for 'http://example.com/login' => (method => 'POST') => begin
    %= text_field 'first_name'
    %= submit_button
  % end
  %= form_for some_delete_route => begin
    %= submit_button 'Remove'
  % end

Generate portable C<form> tag with L<Mojolicious::Controller/"url_for">. For routes that do not allow C<GET>, a
C<method> attribute with the value C<POST> will be automatically added. And for methods other than C<GET> or C<POST>,
an C<_method> query parameter will be added as well.

  <form action="/path/to/login">
    <input name="first_name" type="text">
    <input type="submit" value="Ok">
  </form>
  <form action="/path/to/login.txt" method="POST">
    <input name="first_name" type="text">
    <input type="submit" value="Ok">
  </form>
  <form action="/path/to/login" enctype="multipart/form-data">
    <input disabled="disabled" name="first_name" type="text">
    <input type="submit" value="Ok">
  </form>
  <form action="http://example.com/login" method="POST">
    <input name="first_name" type="text">
    <input type="submit" value="Ok">
  </form>
  <form action="/path/to/delete/route?_method=DELETE" method="POST">
    <input type="submit" value="Remove">
  </form>

=head2 hidden_field

  %= hidden_field foo => 'bar'
  %= hidden_field foo => 'bar', id => 'bar'

Generate C<input> tag of type C<hidden>.

  <input name="foo" type="hidden" value="bar">
  <input id="bar" name="foo" type="hidden" value="bar">

=head2 image

  %= image '/images/foo.png'
  %= image '/images/foo.png', alt => 'Foo'

Generate portable C<img> tag.

  <img src="/path/to/images/foo.png">
  <img alt="Foo" src="/path/to/images/foo.png">

=head2 input_tag

  %= input_tag 'first_name'
  %= input_tag first_name => 'Default'
  %= input_tag 'employed', type => 'checkbox'

Generate C<input> tag. Previous input values will automatically get picked up and shown as default.

  <input name="first_name">
  <input name="first_name" value="Default">
  <input name="employed" type="checkbox">

=head2 javascript

  %= javascript '/script.js'
  %= javascript '/script.js', defer => undef
  %= javascript begin
    const a = 'b';
  % end

Generate portable C<script> tag for JavaScript asset.

  <script src="/path/to/script.js"></script>
  <script defer src="/path/to/script.js"></script>
  <script><![CDATA[
    const a = 'b';
  ]]></script>

=head2 label_for

  %= label_for first_name => 'First name'
  %= label_for first_name => 'First name', class => 'user'
  %= label_for first_name => begin
    First name
  % end
  %= label_for first_name => (class => 'user') => begin
    First name
  % end

Generate C<label> tag.

  <label for="first_name">First name</label>
  <label class="user" for="first_name">First name</label>
  <label for="first_name">
    First name
  </label>
  <label class="user" for="first_name">
    First name
  </label>

=head2 link_to

  %= link_to Home => 'index'
  %= link_to Home => 'index' => {format => 'txt'} => (class => 'menu')
  %= link_to index => {format => 'txt'} => (class => 'menu') => begin
    Home
  % end
  %= link_to Contact => 'mailto:sri@example.com'
  <%= link_to index => begin %>Home<% end %>
  <%= link_to '/file.txt' => begin %>File<% end %>
  <%= link_to 'https://mojolicious.org' => begin %>Mojolicious<% end %>
  <%= link_to url_for->query(foo => 'bar')->to_abs => begin %>Retry<% end %>

Generate portable C<a> tag with L<Mojolicious::Controller/"url_for">, defaults to using the capitalized link target as
content.

  <a href="/path/to/index">Home</a>
  <a class="menu" href="/path/to/index.txt">Home</a>
  <a class="menu" href="/path/to/index.txt">
    Home
  </a>
  <a href="mailto:sri@example.com">Contact</a>
  <a href="/path/to/index">Home</a>
  <a href="/path/to/file.txt">File</a>
  <a href="https://mojolicious.org">Mojolicious</a>
  <a href="http://127.0.0.1:3000/current/path?foo=bar">Retry</a>

=head2 month_field

  %= month_field 'vacation'
  %= month_field vacation => '2012-12'
  %= month_field vacation => '2012-12', id => 'foo'

Generate C<input> tag of type C<month>. Previous input values will automatically get picked up and shown as default.

  <input name="vacation" type="month">
  <input name="vacation" type="month" value="2012-12">
  <input id="foo" name="vacation" type="month" value="2012-12">

=head2 number_field

  %= number_field 'age'
  %= number_field age => 25
  %= number_field age => 25, id => 'foo', min => 0, max => 200

Generate C<input> tag of type C<number>. Previous input values will automatically get picked up and shown as default.

  <input name="age" type="number">
  <input name="age" type="number" value="25">
  <input id="foo" max="200" min="0" name="age" type="number" value="25">

=head2 password_field

  %= password_field 'pass'
  %= password_field 'pass', id => 'foo'

Generate C<input> tag of type C<password>.

  <input name="pass" type="password">
  <input id="foo" name="pass" type="password">

=head2 radio_button

  %= radio_button 'test'
  %= radio_button country => 'germany'
  %= radio_button country => 'germany', checked => undef, id => 'foo'

Generate C<input> tag of type C<radio>. Previous input values will automatically get picked up and shown as default.

  <input name="test" type="radio">
  <input name="country" type="radio" value="germany">
  <input checked id="foo" name="country" type="radio" value="germany">

=head2 range_field

  %= range_field 'age'
  %= range_field age => 25
  %= range_field age => 25, id => 'foo', min => 0, max => 200

Generate C<input> tag of type C<range>. Previous input values will automatically get picked up and shown as default.

  <input name="age" type="range">
  <input name="age" type="range" value="25">
  <input id="foo" max="200" min="200" name="age" type="range" value="25">

=head2 search_field

  %= search_field 'q'
  %= search_field q => 'perl'
  %= search_field q => 'perl', id => 'foo'

Generate C<input> tag of type C<search>. Previous input values will automatically get picked up and shown as default.

  <input name="q" type="search">
  <input name="q" type="search" value="perl">
  <input id="foo" name="q" type="search" value="perl">

=head2 select_field

  %= select_field country => ['de', 'en']
  %= select_field country => [[Germany => 'de'], 'en'], id => 'eu'
  %= select_field country => [[Germany => 'de', selected => 'selected'], 'en']
  %= select_field country => [c(EU => [[Germany => 'de'], 'en'], id => 'eu')]
  %= select_field country => [c(EU => ['de', 'en']), c(Asia => ['cn', 'jp'])]

Generate C<select> and C<option> tags from array references and C<optgroup> tags from L<Mojo::Collection> objects.
Previous input values will automatically get picked up and shown as default.

  <select name="country">
    <option value="de">de</option>
    <option value="en">en</option>
  </select>
  <select id="eu" name="country">
    <option value="de">Germany</option>
    <option value="en">en</option>
  </select>
  <select name="country">
    <option selected="selected" value="de">Germany</option>
    <option value="en">en</option>
  </select>
  <select name="country">
    <optgroup id="eu" label="EU">
      <option value="de">Germany</option>
      <option value="en">en</option>
    </optgroup>
  </select>
  <select name="country">
    <optgroup label="EU">
      <option value="de">de</option>
      <option value="en">en</option>
    </optgroup>
    <optgroup label="Asia">
      <option value="cn">cn</option>
      <option value="jp">jp</option>
    </optgroup>
  </select>

=head2 stylesheet

  %= stylesheet '/foo.css'
  %= stylesheet '/foo.css', title => 'Foo style'
  %= stylesheet begin
    body {color: #000}
  % end

Generate portable C<style> or C<link> tag for CSS asset.

  <link href="/path/to/foo.css" rel="stylesheet">
  <link href="/path/to/foo.css" rel="stylesheet" title="Foo style">
  <style><![CDATA[
    body {color: #000}
  ]]></style>

=head2 submit_button

  %= submit_button
  %= submit_button 'Ok!', id => 'foo'

Generate C<input> tag of type C<submit>.

  <input type="submit" value="Ok">
  <input id="foo" type="submit" value="Ok!">

=head2 t

  %= t div => 'test & 123'

Alias for L</"tag">.

  <div>test &amp; 123</div>

=head2 tag

  %= tag 'br'
  %= tag 'div'
  %= tag 'div', id => 'foo', hidden => undef
  %= tag 'div', 'test & 123'
  %= tag 'div', id => 'foo', 'test & 123'
  %= tag 'div', data => {my_id => 1, Name => 'test'}, 'test & 123'
  %= tag div => begin
    test & 123
  % end
  <%= tag div => (id => 'foo') => begin %>test & 123<% end %>

Alias for L<Mojo::DOM/"new_tag">.

  <br>
  <div></div>
  <div id="foo" hidden></div>
  <div>test &amp; 123</div>
  <div id="foo">test &amp; 123</div>
  <div data-my-id="1" data-name="test">test &amp; 123</div>
  <div>
    test & 123
  </div>
  <div id="foo">test & 123</div>

Very useful for reuse in more specific tag helpers.

  my $output = $c->tag('meta');
  my $output = $c->tag('meta', charset => 'UTF-8');
  my $output = $c->tag('div', '<p>This will be escaped</p>');
  my $output = $c->tag('div', sub { '<p>This will not be escaped</p>' });

Results are automatically wrapped in L<Mojo::ByteStream> objects to prevent accidental double escaping in C<ep>
templates.

=head2 tag_with_error

  %= tag_with_error 'input', class => 'foo'

Same as L</"tag">, but adds the class C<field-with-error>.

  <input class="foo field-with-error">

=head2 tel_field

  %= tel_field 'work'
  %= tel_field work => '123456789'
  %= tel_field work => '123456789', id => 'foo'

Generate C<input> tag of type C<tel>. Previous input values will automatically get picked up and shown as default.

  <input name="work" type="tel">
  <input name="work" type="tel" value="123456789">
  <input id="foo" name="work" type="tel" value="123456789">

=head2 text_area

  %= text_area 'story'
  %= text_area 'story', cols => 40
  %= text_area story => 'Default', cols => 40
  %= text_area story => (cols => 40) => begin
    Default
  % end

Generate C<textarea> tag. Previous input values will automatically get picked up and shown as default.

  <textarea name="story"></textarea>
  <textarea cols="40" name="story"></textarea>
  <textarea cols="40" name="story">Default</textarea>
  <textarea cols="40" name="story">
    Default
  </textarea>

=head2 text_field

  %= text_field 'first_name'
  %= text_field first_name => 'Default'
  %= text_field first_name => 'Default', class => 'user'

Generate C<input> tag of type C<text>. Previous input values will automatically get picked up and shown as default.

  <input name="first_name" type="text">
  <input name="first_name" type="text" value="Default">
  <input class="user" name="first_name" type="text" value="Default">

=head2 time_field

  %= time_field 'start'
  %= time_field start => '23:59:59'
  %= time_field start => '23:59:59', id => 'foo'

Generate C<input> tag of type C<time>. Previous input values will automatically get picked up and shown as default.

  <input name="start" type="time">
  <input name="start" type="time" value="23:59:59">
  <input id="foo" name="start" type="time" value="23:59:59">

=head2 url_field

  %= url_field 'address'
  %= url_field address => 'https://mojolicious.org'
  %= url_field address => 'https://mojolicious.org', id => 'foo'

Generate C<input> tag of type C<url>. Previous input values will automatically get picked up and shown as default.

  <input name="address" type="url">
  <input name="address" type="url" value="https://mojolicious.org">
  <input id="foo" name="address" type="url" value="https://mojolicious.org">

=head2 week_field

  %= week_field 'vacation'
  %= week_field vacation => '2012-W17'
  %= week_field vacation => '2012-W17', id => 'foo'

Generate C<input> tag of type C<week>. Previous input values will automatically get picked up and shown as default.

  <input name="vacation" type="week">
  <input name="vacation" type="week" value="2012-W17">
  <input id="foo" name="vacation" type="week" value="2012-W17">

=head1 METHODS

L<Mojolicious::Plugin::TagHelpers> inherits all methods from L<Mojolicious::Plugin> and implements the following new
ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
