#!/usr/bin/env perl

use strict;
use warnings;

# Boy, who knew a cooler could also make a handy wang coffin?
use Mojolicious::Lite;

# Load plugin
plugin 'json_config';

# GET /
get '/' => 'index';

app->start;
__DATA__
@@ index.html.ep
<%= $config->{just} %>
