package Mojolicious::Static;

use strict;
use warnings;

use base 'Mojo::Base';

use File::stat;
use File::Spec;
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Command;
use Mojo::Content::Single;
use Mojo::Path;

__PACKAGE__->attr([qw/default_static_class prefix root/]);

# Valentine's Day's coming? Aw crap! I forgot to get a girlfriend again!
sub dispatch {
    my ($self, $c) = @_;

    # Already rendered
    return if $c->res->code;

    # Canonical path
    my $path = $c->req->url->path->clone->canonicalize->to_string;

    # Prefix
    if (my $prefix = $self->prefix) {
        return 1 unless $path =~ s/^$prefix//;
    }

    # Parts
    my @parts = @{Mojo::Path->new->parse($path)->parts};

    # Shortcut
    return 1 unless @parts;

    # Prevent directory traversal
    return 1 if $parts[0] eq '..';

    # Serve static file
    unless ($self->serve($c, join('/', @parts))) {

        # Resume
        $c->tx->resume;

        return;
    }

    return 1;
}

sub serve {
    my ($self, $c, $rel) = @_;

    # Append path to root
    my $path = File::Spec->catfile($self->root, split('/', $rel));

    # Extension
    $path =~ /\.(\w+)$/;
    my $ext = $1;

    # Type
    my $type = $c->app->types->type($ext) || 'text/plain';

    # Response
    my $res = $c->res;

    # Asset
    my $asset;

    # Modified
    my $modified = $self->{_modified} ||= time;

    # Size
    my $size = 0;

    # File
    if (-f $path) {

        # Readable
        if (-r $path) {

            # Modified
            my $stat = stat($path);
            $modified = $stat->mtime;

            # Size
            $size = $stat->size;

            # Content
            $asset = Mojo::Asset::File->new(path => $path);
        }

        # Exists, but is forbidden
        else {
            $c->app->log->debug('File forbidden.');
            $res->code(403) and return;
        }
    }

    # Inline file
    elsif (defined(my $file = $self->_get_inline_file($c, $rel))) {
        $size  = length $file;
        $asset = Mojo::Asset::Memory->new->add_chunk($file);
    }

    # Found
    if ($asset) {

        # Log
        $c->app->log->debug(qq/Serving static file "$rel"./);

        # Request
        my $req = $c->req;

        # Request headers
        my $rqh = $req->headers;

        # Response headers
        my $rsh = $res->headers;

        # If modified since
        if (my $date = $rqh->if_modified_since) {

            # Not modified
            my $since = Mojo::Date->new($date)->epoch;
            if (defined $since && $since == $modified) {
                $c->app->log->debug('File not modified.');
                $res->code(304);
                $rsh->remove('Content-Type');
                $rsh->remove('Content-Length');
                $rsh->remove('Content-Disposition');
                return;
            }
        }

        # Start and end
        my $start = 0;
        my $end = $size - 1 >= 0 ? $size - 1 : 0;

        # Range
        if (my $range = $rqh->range) {
            if ($range =~ m/^bytes=(\d+)\-(\d+)?/ && $1 <= $end) {
                $start = $1;
                $end = $2 if defined $2 && $2 <= $end;
                $res->code(206);
                $rsh->content_length($end - $start + 1);
                $rsh->content_range("bytes $start-$end/$size");
                $c->app->log->debug("Range request: $start-$end/$size.");
            }
            else {

                # Not satisfiable
                $res->code(416);
                return;
            }
        }
        $asset->start_range($start);
        $asset->end_range($end);

        # Response
        $res->code(200) unless $res->code;
        $res->content->asset($asset);
        $rsh->content_type($type);
        $rsh->accept_ranges('bytes');
        $rsh->last_modified(Mojo::Date->new($modified));
        return;
    }

    return 1;
}

sub _get_inline_file {
    my ($self, $c, $rel) = @_;

    # Protect templates
    return if $rel =~ /\.\w+\.\w+$/;

    # Class
    my $class =
         $c->stash->{static_class}
      || $ENV{MOJO_STATIC_CLASS}
      || $self->default_static_class
      || 'main';

    # Inline files
    my $inline = $self->{_inline_files}->{$class}
      ||= [keys %{Mojo::Command->new->get_all_data($class) || {}}];

    # Find inline file
    for my $path (@$inline) {
        return Mojo::Command->new->get_data($path, $class) if $path eq $rel;
    }

    # Bundled files
    my $bundled = $self->{_bundled_files}
      ||= [keys %{Mojo::Command->new->get_all_data(ref $self) || {}}];

    # Find bundled file
    for my $path (@$bundled) {
        return Mojo::Command->new->get_data($path, ref $self)
          if $path eq $rel;
    }

    # Nothing
    return;
}

1;
__DATA__

@@ favicon.ico (base64)
AAABAAIAGBgAAAEAIAC4CQAAJgAAABAQAAABACAAaAQAAN4JAAAoAAAAGAAAADAAAAABACAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAA////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5+QL5+fkC+fn5Avn5
+QH5+fkA+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA////AP///wD///8A////
Af///wT///8F////Bf///wL///8C////BP///wD///8A////AP///wL///8E////Af///wL///8D
////A////wL///8A////AP///wD///8Af39/AICAgACAgIAEhoaGAICAgAB5eXkAfHx8AIaGhgCH
h4cAenp6AG1tbQxtbW0gbGxsGnNzcwCAgIAAh4eHAIWFhQCCgoIAgoKCAIWFhQCHh4cEgICAB39/
fwCAgIAAAAAAAAAAAAIAAAAAAAAAAwAAAE0CAgJiAAAAYgAAABQAAAAQAAAAcTU1NalHR0e9QUFB
txwcHJAAAABJAAAAAgAAABMAAAAwAAAALQAAABcAAAAAAAAAAAAAAAYAAAAABgYGAwcHBwIAAAAb
PT09n5ubm+m6urr+tLS0/0xMTK1PT0+rvLy8/+zs7P/5+fn/9fX1/9nZ2f+RkZHmR0dHnF1dXbB/
f3/OfHx8y2JiYrQuLi6DAAAAJgkJCQAHBwcDAgICBgEBAQAeHh6P0tLS//////n39/f/////+tzc
3P/i4uL//v7++uzs7Pfo6Oj16enp9vT09Pj7+/v/3t3e/+vr6//6+vr/+fn5/+7u7v/Kysr/Xl5e
xAAAADMBAQEACQkJAgAAAABlZWXe////+tnZ2fPn5+f94ODg+fPz8/jy8vL34eHh++bm5v/o6Oj/
5+fn/+Pj4//l5eX49fT1+O7u7vfm5ub26Ojo9e7u7vj4+Pj29PT0/0tLS80AAAANBQUFBQAAAAE+
Pj6s5+fn/+vr6/rx8fH/8PDw/ufn5//o6Oj/8PDw/+/v7/7u7u7+7u7u/vDw8P7u7u7/5+fn/+np
6f/t7e3/7Ozs/+3u7f/e3t7+/Pz88729vf8CAgJHAAAACAAAAAAAAABuv7+///r6+vXq6ur/8fHx
/fHx8f7y8vL+7+/v/u/v7//v7+//7+/v/+/v7/7w8PD+8/Pz/vLy8v7w8PD+8PDw/vPy8/3y8vL/
8PDw9tra2vsEBARqBQUFAwAAAAxNTU2/4+Pj/+/v7/zz8/P/8vLy//Hx8f/x8fH/8/Pz//Pz8//z
8/P/8/Pz//Pz8//y8vL/8fHx//Ly8v/y8vL/8fHx//b29v/q6ur/////+rm5uf8AAAA+BgYGAAAA
ADu5ubn//////PDw8P/5+fn+9/f3/vb29v/29vb/9vb2//X19f/19fX/9fX1//X19f/29vb/9vb2
//b29v/19fX/9vb2/vX19f/19fX83dzd/zw8PK8CAgIIBAQEAAAAAErGxsb/+fn59fHx8f/6+vr+
9PT0//j4+P/4+Pj++Pj4//n5+f/5+fn/+fn5//n5+f/4+Pj/9/f3/vf39//39/f/+/v7/vPz8///
///3vLu8/wAAAFYCAgIABwcHAgAAABiAgIDy////+vLy8vP6+vr3+/v79vn5+f38/Pz/+/v7/vr6
+v/7+/v/+/v7//r6+v77+/v+/f39//39/f77+/v++/v7/fz8/P/8/Pz37e3t/zAwMJsAAAABAwMD
AwICAgAXFxdwsrKy////////////8PDw//j4+Pr8/Pz+/f39//7+/v7+/v7+/v7+/v7+/v79/f3/
9/f3/fr6+v7//////f39/v/////y8vL5/////VlZWcwAAAAAAAAAAQICAgMAAAABFhYWbGpqarqF
hYXGUVFRrri4uP7////58PDw+fv7+//7+/v/+/v7//f39/75+fn4////+/////j4+Pj3+Pj4+Pb2
9vr6+vrv/Pz8/yYmJpoAAAAAAAAAAAAAAAEEBAQDAAAAAAAAABoAAAAtAAAADy8vL6Db29v/////
+fz8/Pj6+vr1+vr69/////j/////s7Oz/+zs7P/////////////////6+vr/fHx84wAAACsBAQEC
AAAAAAAAAAAAAAADBQUFBwcHBwADAwMACgoKAgAAABY+Pj6isLCw/e7u7v///////////97e3v+K
iorgFRUVclBQUKKWlpbfqKio7Zubm+BdXV2vAQEBRgICAgABAQECBgYGAAYGBgAGBgYABgYGAAYG
BggHBwcHBQUFBw0NDQAAAAAGFxcXYltbW6BxcXG5bW1ts0ZGRo8BAQFCBgYGAAAAAAoAAABAFBQU
TwMDA0UAAAAQCgoKAAcHBwUGBgYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAC
AAAAAAAAAAQAAAAcAAAAFgAAAAAAAAAAAAAABwAAAAEAAAAAAAAAAAAAAAAAAAAAAAAABwAAAAAA
AAAAf39/AH9/fwB/f38Af39/AH9/fwGAgIABf39/AYCAgAB/f38EhoaGB4iIiACFhYUAhoaGAImJ
iQKCgoIIf39/AX9/fwWDg4MJhYWFCIODgwl/f38Gf39/AICAgAB/f38A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wH///8C////Av///wH///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5+QD5
+fkA+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5
+QD5+fkA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAKAAAABAAAAAgAAAAAQAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
APn5+QD5+fkA+fn5APn5+QL5+fkC+fn5APr6+gP7+/sF+/v7Bfr6+gP5+fkA+fn5Afn5+QH5+fkA
+fn5APn5+QD///8A////Af///wP///8A////AP///wP///8A////AP///wD///8A////A////wH/
//8A////BP///wP///8Af39/AYGBgQB0dHQAdXV1IHh4eB5xcXEAfHx8J6GhoVehoaFWfHx8KnBw
cABtbW0Aa2trBHBwcACAgIAAgYGBBQAAAAEAAAAFFRUVe2lpab9eXl65JCQkgmlpacSioqL0oKCg
8mxsbMcoKCiBOzs7l0NDQ6AnJyeBAAAAMQAAAAAICAgAGRkZTNnZ2f///////f39/+Pj4///////
/////f////3/////5+fn//T09P/5+fn/6enp/5CQkM0LCwstAQEBABAQEEzX19f87Ozs8Obm5vn5
+fn56Ojo9+Tk5Pnl5eX55+fn9vb29vnx8fH37+/v+fLy8vL/////TExMogICAgAFBQU/vr6+/v7+
/v3w8PD/7Ozs/fDw8P/19fX/9fX1//Hx8f/q6ur96+vr/fPz8//g4OD1/////GlpabwAAAAAS0tL
mfj4+Pzp6enz8vLy/fj4+P/29vb98vLy/fLy8v319fX9+vr6//r6+v309PT++/v7+9HR0f0ZGRlU
AAAAAEVFRZj/////+Pj48v/////19fX5+fn5//39/f/8/Pz/+vr6//Ly8vz5+fn+9fX1//39/fy+
vr76BAQELgICAgEFBQUpkZGRzd/f3//IyMj+//////j4+Pf19fX5+Pj4+ff39/b////7/Pz89/j4
+Pj7+/vw+/v7/xQUFFsCAgIBAAAAAAMDAzBBQUFsKSkpYaWlper/////////+/////7/////0tLS
//39/f///////////52dneEEBAQiBgYGAAkJCQQJCQkAAAAAAAMDAwAfHx9PlpaWwMrKyvDMzMzz
mpqayDk5OW5qamqakJCQt3V1daEZGRlFBgYGAAAAAAAAAAAAAAAABwAAAAYAAAAHAAAAAAAAACML
CwtWDQ0NVgAAACoAAAAAAAAAAQAAABwAAAAEAAAAAAAAAAR/f38AgICAAH9/fwB+fn4Afn5+AIWF
hQaCgoIAd3d3AHZ2dgCAgIAAiIiIBoaGhgCCgoIAhoaGAISEhAd/f38A////AP///wD///8A////
AP///wD///8A////A////wX///8F////A////wD///8B////Av///wH///8A////APn5+QD5+fkA
+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5+QD5+fkA+fn5APn5+QAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAA

@@ mojolicious-black.png (base64)
iVBORw0KGgoAAAANSUhEUgAAAHAAAAAdCAYAAAByiujPAAAC7mlDQ1BJQ0MgUHJvZmlsZQAAeAGF
VM9rE0EU/jZuqdAiCFprDrJ4kCJJWatoRdQ2/RFiawzbH7ZFkGQzSdZuNuvuJrWliOTi0SreRe2h
B/+AHnrwZC9KhVpFKN6rKGKhFy3xzW5MtqXqwM5+8943731vdt8ADXLSNPWABOQNx1KiEWlsfEJq
/IgAjqIJQTQlVdvsTiQGQYNz+Xvn2HoPgVtWw3v7d7J3rZrStpoHhP1A4Eea2Sqw7xdxClkSAog8
36Epx3QI3+PY8uyPOU55eMG1Dys9xFkifEA1Lc5/TbhTzSXTQINIOJT1cVI+nNeLlNcdB2luZsbI
EL1PkKa7zO6rYqGcTvYOkL2d9H5Os94+wiHCCxmtP0a4jZ71jNU/4mHhpObEhj0cGDX0+GAVtxqp
+DXCFF8QTSeiVHHZLg3xmK79VvJKgnCQOMpkYYBzWkhP10xu+LqHBX0m1xOv4ndWUeF5jxNn3tTd
70XaAq8wDh0MGgyaDUhQEEUEYZiwUECGPBoxNLJyPyOrBhuTezJ1JGq7dGJEsUF7Ntw9t1Gk3Tz+
KCJxlEO1CJL8Qf4qr8lP5Xn5y1yw2Fb3lK2bmrry4DvF5Zm5Gh7X08jjc01efJXUdpNXR5aseXq8
muwaP+xXlzHmgjWPxHOw+/EtX5XMlymMFMXjVfPqS4R1WjE3359sfzs94i7PLrXWc62JizdWm5dn
/WpI++6qvJPmVflPXvXx/GfNxGPiKTEmdornIYmXxS7xkthLqwviYG3HCJ2VhinSbZH6JNVgYJq8
9S9dP1t4vUZ/DPVRlBnM0lSJ93/CKmQ0nbkOb/qP28f8F+T3iuefKAIvbODImbptU3HvEKFlpW5z
rgIXv9F98LZua6N+OPwEWDyrFq1SNZ8gvAEcdod6HugpmNOWls05Uocsn5O66cpiUsxQ20NSUtcl
12VLFrOZVWLpdtiZ0x1uHKE5QvfEp0plk/qv8RGw/bBS+fmsUtl+ThrWgZf6b8C8/UXAeIuJAAAA
CXBIWXMAAAsTAAALEwEAmpwYAAAJr0lEQVRoBe2af2yVVxnH33spbYHZFt3ari2FljGnIA1LWcJW
yFhAs1nNmBNcpxapkgWmlQFmZNa2DFiUTN3cWCCgiyaYNYtzROawow5ryhSQYTEoUEoLlBLQQhmw
/rh9/Xzfvuf23fVeesvF+9c9ydPnOc95nuec93zP71vLtm0rQfHtA8uyfNAoaLT6vqamJgn529Ch
5OTkD+Ct0CvQRJWTiqDHoIehLC9eCfDiPIABYJQXgPT09PHoGubPn2/v2LHDPnbsmL1v3z67srJS
yAnIN/Pz83sWLFhgy2b06NH/RvddEyMBYBwBpON97oxKQ54NfQratXz5ctR2LxSQQBqA+rZs2WKr
7OLFi9KpLCBwJ02aJHCXkLcSAMYRQKfDWQp9Pl/7nDlz+jIyMq5MnTrVHiBRZvf29kq2+/v7HY5K
oPVDA4FAwIYcYHfu3CkAm1l6/QkA4wggnT4vMzPTbmhoABPbbmlpsZubmx3wBJA3CUiRC5xT5NoM
XLp0yU5LS7tMvPEJAOML4Dtbt24VGL2AI+DCgueg5f4ZNBvMuAAGdu3apRl4ABql008ixakHOIBM
KykpUW1JAMNKqsOoZfn9foeH+2NsgNAU29u2bZPcjC4Q2dOYJ/hN64G+vr7OEydOKJ6WxmBctjZL
eUOAa4WSAJSO5K+qqrKysrK+ArjFCQCD3RgX4YWVK1daApHZaAGoxYEF4ERDIEoXjgTgtWvXfNOm
TesvKytLocVfTAAYF9yClfyzo6Nj4Ny5c35mjzMLh2ZdIDjrjM5wASdZXKArjR+v66N1S2IPVDfE
L82rqKjwz5o1q7+rqyuJ5Ox/Wh5F3r3Q6LQHCjjDU1NTKbKt+vp6tfpAAsD4gaeaes6cOSMeGDNm
zCiSZtSAOEuq//Llyz6BJSApt1NSUsgO2C6wOvHYslm1alVSY2NjE/fA18zLgIL+3xNPQjms7T9k
NKXQ6DXt7e0tI6jUl5ub2+SxX0ZnHCwoKMjgArwRfSYfWnXq1Km/e2wiihMmTHiEzllGW949ffr0
uoiGN7GAuvIIt3f16tV55eXlFgBZ69evt86ePWutXbvWmjlzZgAb57h5/PjxpM2bN1tHjhyxZs+e
bfHkZrW1tVlc4i3ujn8gTjkzsTOuAALAD6i0Vn1CQ18CAD3gRpVqa2v9fFDw6MYAuB+w9uTl5T0B
EHr4Vcw6Yi6KJmBOTk4ndlmy5QH50ydPnjwSjV+sNrTxTmI8B3glfEPK1atX3yDfPnbs2MrS0tJ0
BpbV2dlp7d69OwDfTtmfoXugj0Gavrvpw51wfa8/3kvoXirVm5828UY1ItYEePuIdY2YOpXtiTYe
PnvwWYh9G3JrtH6x2FGPnzqPEuNLyHoP1cN2l2KS/2VdXd1DiLnQf6B6yg7ClbYMsqG/bqyBiKdQ
jfgh80Fp4cKF+gnkusn1G7yhhlgyO+pZ5m5ntOWybNWFFDvZ6/mHs+dUd4B42YzmfOJvCmcj3dy5
cz8yWDVT8bmTi/Xk1tbWD8P5hfqEsxmJDkBsExOxG3LAUwzkFuhn0NPQjyADXtgqKHcuhb7p06eP
u3DhwvtukAaQbUBeAd2N0SE+cgmjXB//ElQMnYeq6IBfwJ1UXFw8mnX8KTL6zeou/HqJ0wxY61jm
fj9oxdBiCUX+mpvfRYwnJUfjH2kJZSmspC4nDvW+B6AmvsVylEvb11HFLMomY3cFefvSpUuf5KX/
X6pbiXY+Tjv/Khmfz+CzHrEYn2x4K35vs8w+A9AXZcM9LJlT5D8ku2kR3/I3lvMV+CyTDt5EW8ol
E/NBYurbi9CnEK8D/jzlP1V5LCmpu7tbr6h3uEH0Y+G3kM0MKqbit9Fput/i2miK/5zGHmQWva9Z
CXh/xOY+t1wshfy93F3ewu4p7H7ilt2G3qmLj2iWboT+bpghRpxPmJhoT5sSBksJ+rfIa+9wEvl0
BGe2eXxUNkZ/8PkC+t8gJinvpkJ0yzgolRYUFBQJxJ6eHp0dTJ9p+Ut1bW81enRt0hFzHrrfIQZX
NPJ5lGvJjzn5Fy9e3OuJoo89SXDnkiE9leW45a+jD9qiL5O+qanpO8gGvG5sHodedH3kv6GwsHCi
yYfyWP1D4yk/ZcoUdY5WCAc82nMR2gTVcPf6rWxCU1FR0Th0myEHPGxfQ34E7gwKviMfEDeE+kWR
r8DGgLeF+u9hxj8BF6gxJ391dbXWUpFJ5SwHn6XhwSM+Fb7IdP8yH/GqMYJPkoyuVFwJn9fx3c6e
9D2y/dJRnsqHz5EcLsXqHy4mJ7uZxPXOkEdp13KolqvLn8L5nD9/XlvG7Z6y1XzzG+heNTrkzxl5
BFxbjkllXKO+ybbUyJXAuwSb8hFzMzKCjoBgKjxulDT8nGSAPGp08LGu/EmPzjmK828BPcRpNXr8
C40chsfqHyakdZdR0o4PmZF7TD4Sx87bjiuAfUq26L3Xi4nhDncyixSXC/orxNCpUknb0FIu781s
LYuliDX9D4AmIJ1uG9nDvTPVqJ0lRhlcnFGvQwnZfGMA9wLvUTtirP6h8TTQOoySNqUePXr0AZOP
xPEJtgObcex3OsAIwMnGB7lFK9aMGTO0ugT7wthwXnD2UmMvrvsl5UWIP4Z3uWW6TnzflWNiEQEc
QdRGj+0CNu2HOdSspYEprr6fUfiexyZUjNU/NJ6epQ7QWT2eAh26NtC2ZTpUePRBkc7fj0/wOsFB
ZSM+D/AdXw8aWZbTVu5rejHRpdpJ+FZzGl6HbonR4ZckmRiPor+fPU978Oc95YWcZs3B0KhHzGMG
kP3uWWp1TlzwTBqufeNpT0uqGYXOcoo+2eiRnRk+En/jOxzn5xot+VXGjqp0nVgDfxndIqP3cpbM
C5R72/1VfPTqcYfs6HzNam/5mx7/QuRnoOAMxN75VmJUcBr/FXvfceQm40P5u4cPH/7A5G+Uxwwg
+103o+teGrQd6jUNQW5nWfoGB4HnPLoMj6ynLGsk/sY3Gg4gG2lDGRTcy+UHIM7vMOFi0NYX5EPZ
SU95P7o67oH3CWSjR1cDvePJHyL/oMlTjxmsV9EFjF4ydr/mKe0xj+6GxZv6FqpXBh5hCxhpXd6P
Veu4zH6ckagDQabb2hV02Ecustfzd31uiGmp4uKdCwiXuMc5A2e4QGovINyanZ3dun///r5I9hyQ
bmN2jbpeXPbTVL49l3g+HqXbmXnBgR4pbrT6mwpgpErZH9Yw6qr5gOC+yFH6bl4/nMt8JL+Efvge
iHkJHb4KZ/9I84Cn/eTZBHjR9NzwNs5JaXiz2CwA7zCg7YUfY+ZtAry/xBYx4W164L8WukvaCHAF
9QAAAABJRU5ErkJggg==

@@ css/prettify.css (base64)
LnN0cntjb2xvcjojMDgwfS5rd2R7Y29sb3I6IzAwOH0uY29te2NvbG9yOiM4MDB9LnR5cHtjb2xv
cjojNjA2fS5saXR7Y29sb3I6IzA2Nn0ucHVue2NvbG9yOiM2NjB9LnBsbntjb2xvcjojMDAwfS50
YWd7Y29sb3I6IzAwOH0uYXRue2NvbG9yOiM2MDZ9LmF0dntjb2xvcjojMDgwfS5kZWN7Y29sb3I6
IzYwNn1wcmUucHJldHR5cHJpbnR7cGFkZGluZzoycHg7Ym9yZGVyOjFweCBzb2xpZCAjODg4fW9s
LmxpbmVudW1ze21hcmdpbi10b3A6MDttYXJnaW4tYm90dG9tOjB9bGkuTDAsbGkuTDEsbGkuTDIs
bGkuTDMsbGkuTDUsbGkuTDYsbGkuTDcsbGkuTDh7bGlzdC1zdHlsZTpub25lfWxpLkwxLGxpLkwz
LGxpLkw1LGxpLkw3LGxpLkw5e2JhY2tncm91bmQ6I2VlZX1AbWVkaWEgcHJpbnR7LnN0cntjb2xv
cjojMDYwfS5rd2R7Y29sb3I6IzAwNjtmb250LXdlaWdodDpib2xkfS5jb217Y29sb3I6IzYwMDtm
b250LXN0eWxlOml0YWxpY30udHlwe2NvbG9yOiM0MDQ7Zm9udC13ZWlnaHQ6Ym9sZH0ubGl0e2Nv
bG9yOiMwNDR9LnB1bntjb2xvcjojNDQwfS5wbG57Y29sb3I6IzAwMH0udGFne2NvbG9yOiMwMDY7
Zm9udC13ZWlnaHQ6Ym9sZH0uYXRue2NvbG9yOiM0MDR9LmF0dntjb2xvcjojMDYwfX0=

@@ css/prettify-mojo.css (base64)
LnN0ciB7IGNvbG9yOiAjOWRhYTdlOyB9Ci5rd2QgeyBjb2xvcjogI2Q1YjU3YzsgfQouY29tIHsg
Y29sb3I6ICM3MjZkNzM7IH0KLnR5cCB7IGNvbG9yOiAjZGQ3ZTVlOyB9Ci5saXQgeyBjb2xvcjog
I2ZjZjBhNDsgfQoucHVuLCAub3BuLCAuY2xvIHsgY29sb3I6ICNhNzgzNTM7IH0KLnBsbiB7IGNv
bG9yOiAjODg5ZGJjOyB9Ci50YWcgeyBjb2xvcjogI2Q1YjU3YzsgfQouYXRuIHsgY29sb3I6ICNk
ZDdlNWU7IH0KLmF0diB7IGNvbG9yOiAjOWRhYTdlOyB9Ci5kZWMgeyBjb2xvcjogI2RkN2U1ZTsg
fQ==

@@ js/jquery.js (base64)
LyohCiAqIGpRdWVyeSBKYXZhU2NyaXB0IExpYnJhcnkgdjEuNC40CiAqIGh0dHA6Ly9qcXVlcnku
Y29tLwogKgogKiBDb3B5cmlnaHQgMjAxMCwgSm9obiBSZXNpZwogKiBEdWFsIGxpY2Vuc2VkIHVu
ZGVyIHRoZSBNSVQgb3IgR1BMIFZlcnNpb24gMiBsaWNlbnNlcy4KICogaHR0cDovL2pxdWVyeS5v
cmcvbGljZW5zZQogKgogKiBJbmNsdWRlcyBTaXp6bGUuanMKICogaHR0cDovL3NpenpsZWpzLmNv
bS8KICogQ29weXJpZ2h0IDIwMTAsIFRoZSBEb2pvIEZvdW5kYXRpb24KICogUmVsZWFzZWQgdW5k
ZXIgdGhlIE1JVCwgQlNELCBhbmQgR1BMIExpY2Vuc2VzLgogKgogKiBEYXRlOiBUaHUgTm92IDEx
IDE5OjA0OjUzIDIwMTAgLTA1MDAKICovCihmdW5jdGlvbihFLEIpe2Z1bmN0aW9uIGthKGEsYixk
KXtpZihkPT09QiYmYS5ub2RlVHlwZT09PTEpe2Q9YS5nZXRBdHRyaWJ1dGUoImRhdGEtIitiKTtp
Zih0eXBlb2YgZD09PSJzdHJpbmciKXt0cnl7ZD1kPT09InRydWUiP3RydWU6ZD09PSJmYWxzZSI/
ZmFsc2U6ZD09PSJudWxsIj9udWxsOiFjLmlzTmFOKGQpP3BhcnNlRmxvYXQoZCk6SmEudGVzdChk
KT9jLnBhcnNlSlNPTihkKTpkfWNhdGNoKGUpe31jLmRhdGEoYSxiLGQpfWVsc2UgZD1CfXJldHVy
biBkfWZ1bmN0aW9uIFUoKXtyZXR1cm4gZmFsc2V9ZnVuY3Rpb24gY2EoKXtyZXR1cm4gdHJ1ZX1m
dW5jdGlvbiBsYShhLGIsZCl7ZFswXS50eXBlPWE7cmV0dXJuIGMuZXZlbnQuaGFuZGxlLmFwcGx5
KGIsZCl9ZnVuY3Rpb24gS2EoYSl7dmFyIGIsZCxlLGYsaCxsLGssbyx4LHIsQSxDPVtdO2Y9W107
aD1jLmRhdGEodGhpcyx0aGlzLm5vZGVUeXBlPyJldmVudHMiOiJfX2V2ZW50c19fIik7aWYodHlw
ZW9mIGg9PT0iZnVuY3Rpb24iKWg9CmguZXZlbnRzO2lmKCEoYS5saXZlRmlyZWQ9PT10aGlzfHwh
aHx8IWgubGl2ZXx8YS5idXR0b24mJmEudHlwZT09PSJjbGljayIpKXtpZihhLm5hbWVzcGFjZSlB
PVJlZ0V4cCgiKF58XFwuKSIrYS5uYW1lc3BhY2Uuc3BsaXQoIi4iKS5qb2luKCJcXC4oPzouKlxc
Lik/IikrIihcXC58JCkiKTthLmxpdmVGaXJlZD10aGlzO3ZhciBKPWgubGl2ZS5zbGljZSgwKTtm
b3Ioaz0wO2s8Si5sZW5ndGg7aysrKXtoPUpba107aC5vcmlnVHlwZS5yZXBsYWNlKFgsIiIpPT09
YS50eXBlP2YucHVzaChoLnNlbGVjdG9yKTpKLnNwbGljZShrLS0sMSl9Zj1jKGEudGFyZ2V0KS5j
bG9zZXN0KGYsYS5jdXJyZW50VGFyZ2V0KTtvPTA7Zm9yKHg9Zi5sZW5ndGg7bzx4O28rKyl7cj1m
W29dO2ZvcihrPTA7azxKLmxlbmd0aDtrKyspe2g9SltrXTtpZihyLnNlbGVjdG9yPT09aC5zZWxl
Y3RvciYmKCFBfHxBLnRlc3QoaC5uYW1lc3BhY2UpKSl7bD1yLmVsZW07ZT1udWxsO2lmKGgucHJl
VHlwZT09PSJtb3VzZWVudGVyInx8CmgucHJlVHlwZT09PSJtb3VzZWxlYXZlIil7YS50eXBlPWgu
cHJlVHlwZTtlPWMoYS5yZWxhdGVkVGFyZ2V0KS5jbG9zZXN0KGguc2VsZWN0b3IpWzBdfWlmKCFl
fHxlIT09bClDLnB1c2goe2VsZW06bCxoYW5kbGVPYmo6aCxsZXZlbDpyLmxldmVsfSl9fX1vPTA7
Zm9yKHg9Qy5sZW5ndGg7bzx4O28rKyl7Zj1DW29dO2lmKGQmJmYubGV2ZWw+ZClicmVhazthLmN1
cnJlbnRUYXJnZXQ9Zi5lbGVtO2EuZGF0YT1mLmhhbmRsZU9iai5kYXRhO2EuaGFuZGxlT2JqPWYu
aGFuZGxlT2JqO0E9Zi5oYW5kbGVPYmoub3JpZ0hhbmRsZXIuYXBwbHkoZi5lbGVtLGFyZ3VtZW50
cyk7aWYoQT09PWZhbHNlfHxhLmlzUHJvcGFnYXRpb25TdG9wcGVkKCkpe2Q9Zi5sZXZlbDtpZihB
PT09ZmFsc2UpYj1mYWxzZTtpZihhLmlzSW1tZWRpYXRlUHJvcGFnYXRpb25TdG9wcGVkKCkpYnJl
YWt9fXJldHVybiBifX1mdW5jdGlvbiBZKGEsYil7cmV0dXJuKGEmJmEhPT0iKiI/YSsiLiI6IiIp
K2IucmVwbGFjZShMYSwKImAiKS5yZXBsYWNlKE1hLCImIil9ZnVuY3Rpb24gbWEoYSxiLGQpe2lm
KGMuaXNGdW5jdGlvbihiKSlyZXR1cm4gYy5ncmVwKGEsZnVuY3Rpb24oZixoKXtyZXR1cm4hIWIu
Y2FsbChmLGgsZik9PT1kfSk7ZWxzZSBpZihiLm5vZGVUeXBlKXJldHVybiBjLmdyZXAoYSxmdW5j
dGlvbihmKXtyZXR1cm4gZj09PWI9PT1kfSk7ZWxzZSBpZih0eXBlb2YgYj09PSJzdHJpbmciKXt2
YXIgZT1jLmdyZXAoYSxmdW5jdGlvbihmKXtyZXR1cm4gZi5ub2RlVHlwZT09PTF9KTtpZihOYS50
ZXN0KGIpKXJldHVybiBjLmZpbHRlcihiLGUsIWQpO2Vsc2UgYj1jLmZpbHRlcihiLGUpfXJldHVy
biBjLmdyZXAoYSxmdW5jdGlvbihmKXtyZXR1cm4gYy5pbkFycmF5KGYsYik+PTA9PT1kfSl9ZnVu
Y3Rpb24gbmEoYSxiKXt2YXIgZD0wO2IuZWFjaChmdW5jdGlvbigpe2lmKHRoaXMubm9kZU5hbWU9
PT0oYVtkXSYmYVtkXS5ub2RlTmFtZSkpe3ZhciBlPWMuZGF0YShhW2QrK10pLGY9Yy5kYXRhKHRo
aXMsCmUpO2lmKGU9ZSYmZS5ldmVudHMpe2RlbGV0ZSBmLmhhbmRsZTtmLmV2ZW50cz17fTtmb3Io
dmFyIGggaW4gZSlmb3IodmFyIGwgaW4gZVtoXSljLmV2ZW50LmFkZCh0aGlzLGgsZVtoXVtsXSxl
W2hdW2xdLmRhdGEpfX19KX1mdW5jdGlvbiBPYShhLGIpe2Iuc3JjP2MuYWpheCh7dXJsOmIuc3Jj
LGFzeW5jOmZhbHNlLGRhdGFUeXBlOiJzY3JpcHQifSk6Yy5nbG9iYWxFdmFsKGIudGV4dHx8Yi50
ZXh0Q29udGVudHx8Yi5pbm5lckhUTUx8fCIiKTtiLnBhcmVudE5vZGUmJmIucGFyZW50Tm9kZS5y
ZW1vdmVDaGlsZChiKX1mdW5jdGlvbiBvYShhLGIsZCl7dmFyIGU9Yj09PSJ3aWR0aCI/YS5vZmZz
ZXRXaWR0aDphLm9mZnNldEhlaWdodDtpZihkPT09ImJvcmRlciIpcmV0dXJuIGU7Yy5lYWNoKGI9
PT0id2lkdGgiP1BhOlFhLGZ1bmN0aW9uKCl7ZHx8KGUtPXBhcnNlRmxvYXQoYy5jc3MoYSwicGFk
ZGluZyIrdGhpcykpfHwwKTtpZihkPT09Im1hcmdpbiIpZSs9cGFyc2VGbG9hdChjLmNzcyhhLAoi
bWFyZ2luIit0aGlzKSl8fDA7ZWxzZSBlLT1wYXJzZUZsb2F0KGMuY3NzKGEsImJvcmRlciIrdGhp
cysiV2lkdGgiKSl8fDB9KTtyZXR1cm4gZX1mdW5jdGlvbiBkYShhLGIsZCxlKXtpZihjLmlzQXJy
YXkoYikmJmIubGVuZ3RoKWMuZWFjaChiLGZ1bmN0aW9uKGYsaCl7ZHx8UmEudGVzdChhKT9lKGEs
aCk6ZGEoYSsiWyIrKHR5cGVvZiBoPT09Im9iamVjdCJ8fGMuaXNBcnJheShoKT9mOiIiKSsiXSIs
aCxkLGUpfSk7ZWxzZSBpZighZCYmYiE9bnVsbCYmdHlwZW9mIGI9PT0ib2JqZWN0IiljLmlzRW1w
dHlPYmplY3QoYik/ZShhLCIiKTpjLmVhY2goYixmdW5jdGlvbihmLGgpe2RhKGErIlsiK2YrIl0i
LGgsZCxlKX0pO2Vsc2UgZShhLGIpfWZ1bmN0aW9uIFMoYSxiKXt2YXIgZD17fTtjLmVhY2gocGEu
Y29uY2F0LmFwcGx5KFtdLHBhLnNsaWNlKDAsYikpLGZ1bmN0aW9uKCl7ZFt0aGlzXT1hfSk7cmV0
dXJuIGR9ZnVuY3Rpb24gcWEoYSl7aWYoIWVhW2FdKXt2YXIgYj1jKCI8IisKYSsiPiIpLmFwcGVu
ZFRvKCJib2R5IiksZD1iLmNzcygiZGlzcGxheSIpO2IucmVtb3ZlKCk7aWYoZD09PSJub25lInx8
ZD09PSIiKWQ9ImJsb2NrIjtlYVthXT1kfXJldHVybiBlYVthXX1mdW5jdGlvbiBmYShhKXtyZXR1
cm4gYy5pc1dpbmRvdyhhKT9hOmEubm9kZVR5cGU9PT05P2EuZGVmYXVsdFZpZXd8fGEucGFyZW50
V2luZG93OmZhbHNlfXZhciB0PUUuZG9jdW1lbnQsYz1mdW5jdGlvbigpe2Z1bmN0aW9uIGEoKXtp
ZighYi5pc1JlYWR5KXt0cnl7dC5kb2N1bWVudEVsZW1lbnQuZG9TY3JvbGwoImxlZnQiKX1jYXRj
aChqKXtzZXRUaW1lb3V0KGEsMSk7cmV0dXJufWIucmVhZHkoKX19dmFyIGI9ZnVuY3Rpb24oaixz
KXtyZXR1cm4gbmV3IGIuZm4uaW5pdChqLHMpfSxkPUUualF1ZXJ5LGU9RS4kLGYsaD0vXig/Olte
PF0qKDxbXHdcV10rPilbXj5dKiR8IyhbXHdcLV0rKSQpLyxsPS9cUy8saz0vXlxzKy8sbz0vXHMr
JC8seD0vXFcvLHI9L1xkLyxBPS9ePChcdyspXHMqXC8/Pig/OjxcL1wxPik/JC8sCkM9L15bXF0s
Ont9XHNdKiQvLEo9L1xcKD86WyJcXFwvYmZucnRdfHVbMC05YS1mQS1GXXs0fSkvZyx3PS8iW14i
XFxcblxyXSoifHRydWV8ZmFsc2V8bnVsbHwtP1xkKyg/OlwuXGQqKT8oPzpbZUVdWytcLV0/XGQr
KT8vZyxJPS8oPzpefDp8LCkoPzpccypcWykrL2csTD0vKHdlYmtpdClbIFwvXShbXHcuXSspLyxn
PS8ob3BlcmEpKD86Lip2ZXJzaW9uKT9bIFwvXShbXHcuXSspLyxpPS8obXNpZSkgKFtcdy5dKykv
LG49Lyhtb3ppbGxhKSg/Oi4qPyBydjooW1x3Ll0rKSk/LyxtPW5hdmlnYXRvci51c2VyQWdlbnQs
cD1mYWxzZSxxPVtdLHUseT1PYmplY3QucHJvdG90eXBlLnRvU3RyaW5nLEY9T2JqZWN0LnByb3Rv
dHlwZS5oYXNPd25Qcm9wZXJ0eSxNPUFycmF5LnByb3RvdHlwZS5wdXNoLE49QXJyYXkucHJvdG90
eXBlLnNsaWNlLE89U3RyaW5nLnByb3RvdHlwZS50cmltLEQ9QXJyYXkucHJvdG90eXBlLmluZGV4
T2YsUj17fTtiLmZuPWIucHJvdG90eXBlPXtpbml0OmZ1bmN0aW9uKGosCnMpe3ZhciB2LHosSDtp
ZighailyZXR1cm4gdGhpcztpZihqLm5vZGVUeXBlKXt0aGlzLmNvbnRleHQ9dGhpc1swXT1qO3Ro
aXMubGVuZ3RoPTE7cmV0dXJuIHRoaXN9aWYoaj09PSJib2R5IiYmIXMmJnQuYm9keSl7dGhpcy5j
b250ZXh0PXQ7dGhpc1swXT10LmJvZHk7dGhpcy5zZWxlY3Rvcj0iYm9keSI7dGhpcy5sZW5ndGg9
MTtyZXR1cm4gdGhpc31pZih0eXBlb2Ygaj09PSJzdHJpbmciKWlmKCh2PWguZXhlYyhqKSkmJih2
WzFdfHwhcykpaWYodlsxXSl7SD1zP3Mub3duZXJEb2N1bWVudHx8czp0O2lmKHo9QS5leGVjKGop
KWlmKGIuaXNQbGFpbk9iamVjdChzKSl7aj1bdC5jcmVhdGVFbGVtZW50KHpbMV0pXTtiLmZuLmF0
dHIuY2FsbChqLHMsdHJ1ZSl9ZWxzZSBqPVtILmNyZWF0ZUVsZW1lbnQoelsxXSldO2Vsc2V7ej1i
LmJ1aWxkRnJhZ21lbnQoW3ZbMV1dLFtIXSk7aj0oei5jYWNoZWFibGU/ei5mcmFnbWVudC5jbG9u
ZU5vZGUodHJ1ZSk6ei5mcmFnbWVudCkuY2hpbGROb2Rlc31yZXR1cm4gYi5tZXJnZSh0aGlzLApq
KX1lbHNle2lmKCh6PXQuZ2V0RWxlbWVudEJ5SWQodlsyXSkpJiZ6LnBhcmVudE5vZGUpe2lmKHou
aWQhPT12WzJdKXJldHVybiBmLmZpbmQoaik7dGhpcy5sZW5ndGg9MTt0aGlzWzBdPXp9dGhpcy5j
b250ZXh0PXQ7dGhpcy5zZWxlY3Rvcj1qO3JldHVybiB0aGlzfWVsc2UgaWYoIXMmJiF4LnRlc3Qo
aikpe3RoaXMuc2VsZWN0b3I9ajt0aGlzLmNvbnRleHQ9dDtqPXQuZ2V0RWxlbWVudHNCeVRhZ05h
bWUoaik7cmV0dXJuIGIubWVyZ2UodGhpcyxqKX1lbHNlIHJldHVybiFzfHxzLmpxdWVyeT8oc3x8
ZikuZmluZChqKTpiKHMpLmZpbmQoaik7ZWxzZSBpZihiLmlzRnVuY3Rpb24oaikpcmV0dXJuIGYu
cmVhZHkoaik7aWYoai5zZWxlY3RvciE9PUIpe3RoaXMuc2VsZWN0b3I9ai5zZWxlY3Rvcjt0aGlz
LmNvbnRleHQ9ai5jb250ZXh0fXJldHVybiBiLm1ha2VBcnJheShqLHRoaXMpfSxzZWxlY3Rvcjoi
IixqcXVlcnk6IjEuNC40IixsZW5ndGg6MCxzaXplOmZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMubGVu
Z3RofSwKdG9BcnJheTpmdW5jdGlvbigpe3JldHVybiBOLmNhbGwodGhpcywwKX0sZ2V0OmZ1bmN0
aW9uKGope3JldHVybiBqPT1udWxsP3RoaXMudG9BcnJheSgpOmo8MD90aGlzLnNsaWNlKGopWzBd
OnRoaXNbal19LHB1c2hTdGFjazpmdW5jdGlvbihqLHMsdil7dmFyIHo9YigpO2IuaXNBcnJheShq
KT9NLmFwcGx5KHosaik6Yi5tZXJnZSh6LGopO3oucHJldk9iamVjdD10aGlzO3ouY29udGV4dD10
aGlzLmNvbnRleHQ7aWYocz09PSJmaW5kIil6LnNlbGVjdG9yPXRoaXMuc2VsZWN0b3IrKHRoaXMu
c2VsZWN0b3I/IiAiOiIiKSt2O2Vsc2UgaWYocyl6LnNlbGVjdG9yPXRoaXMuc2VsZWN0b3IrIi4i
K3MrIigiK3YrIikiO3JldHVybiB6fSxlYWNoOmZ1bmN0aW9uKGoscyl7cmV0dXJuIGIuZWFjaCh0
aGlzLGoscyl9LHJlYWR5OmZ1bmN0aW9uKGope2IuYmluZFJlYWR5KCk7aWYoYi5pc1JlYWR5KWou
Y2FsbCh0LGIpO2Vsc2UgcSYmcS5wdXNoKGopO3JldHVybiB0aGlzfSxlcTpmdW5jdGlvbihqKXty
ZXR1cm4gaj09PQotMT90aGlzLnNsaWNlKGopOnRoaXMuc2xpY2UoaiwraisxKX0sZmlyc3Q6ZnVu
Y3Rpb24oKXtyZXR1cm4gdGhpcy5lcSgwKX0sbGFzdDpmdW5jdGlvbigpe3JldHVybiB0aGlzLmVx
KC0xKX0sc2xpY2U6ZnVuY3Rpb24oKXtyZXR1cm4gdGhpcy5wdXNoU3RhY2soTi5hcHBseSh0aGlz
LGFyZ3VtZW50cyksInNsaWNlIixOLmNhbGwoYXJndW1lbnRzKS5qb2luKCIsIikpfSxtYXA6ZnVu
Y3Rpb24oail7cmV0dXJuIHRoaXMucHVzaFN0YWNrKGIubWFwKHRoaXMsZnVuY3Rpb24ocyx2KXty
ZXR1cm4gai5jYWxsKHMsdixzKX0pKX0sZW5kOmZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMucHJldk9i
amVjdHx8YihudWxsKX0scHVzaDpNLHNvcnQ6W10uc29ydCxzcGxpY2U6W10uc3BsaWNlfTtiLmZu
LmluaXQucHJvdG90eXBlPWIuZm47Yi5leHRlbmQ9Yi5mbi5leHRlbmQ9ZnVuY3Rpb24oKXt2YXIg
aixzLHYseixILEc9YXJndW1lbnRzWzBdfHx7fSxLPTEsUT1hcmd1bWVudHMubGVuZ3RoLGdhPWZh
bHNlOwppZih0eXBlb2YgRz09PSJib29sZWFuIil7Z2E9RztHPWFyZ3VtZW50c1sxXXx8e307Sz0y
fWlmKHR5cGVvZiBHIT09Im9iamVjdCImJiFiLmlzRnVuY3Rpb24oRykpRz17fTtpZihRPT09Syl7
Rz10aGlzOy0tS31mb3IoO0s8UTtLKyspaWYoKGo9YXJndW1lbnRzW0tdKSE9bnVsbClmb3IocyBp
biBqKXt2PUdbc107ej1qW3NdO2lmKEchPT16KWlmKGdhJiZ6JiYoYi5pc1BsYWluT2JqZWN0KHop
fHwoSD1iLmlzQXJyYXkoeikpKSl7aWYoSCl7SD1mYWxzZTt2PXYmJmIuaXNBcnJheSh2KT92Oltd
fWVsc2Ugdj12JiZiLmlzUGxhaW5PYmplY3Qodik/djp7fTtHW3NdPWIuZXh0ZW5kKGdhLHYseil9
ZWxzZSBpZih6IT09QilHW3NdPXp9cmV0dXJuIEd9O2IuZXh0ZW5kKHtub0NvbmZsaWN0OmZ1bmN0
aW9uKGope0UuJD1lO2lmKGopRS5qUXVlcnk9ZDtyZXR1cm4gYn0saXNSZWFkeTpmYWxzZSxyZWFk
eVdhaXQ6MSxyZWFkeTpmdW5jdGlvbihqKXtqPT09dHJ1ZSYmYi5yZWFkeVdhaXQtLTsKaWYoIWIu
cmVhZHlXYWl0fHxqIT09dHJ1ZSYmIWIuaXNSZWFkeSl7aWYoIXQuYm9keSlyZXR1cm4gc2V0VGlt
ZW91dChiLnJlYWR5LDEpO2IuaXNSZWFkeT10cnVlO2lmKCEoaiE9PXRydWUmJi0tYi5yZWFkeVdh
aXQ+MCkpaWYocSl7dmFyIHM9MCx2PXE7Zm9yKHE9bnVsbDtqPXZbcysrXTspai5jYWxsKHQsYik7
Yi5mbi50cmlnZ2VyJiZiKHQpLnRyaWdnZXIoInJlYWR5IikudW5iaW5kKCJyZWFkeSIpfX19LGJp
bmRSZWFkeTpmdW5jdGlvbigpe2lmKCFwKXtwPXRydWU7aWYodC5yZWFkeVN0YXRlPT09ImNvbXBs
ZXRlIilyZXR1cm4gc2V0VGltZW91dChiLnJlYWR5LDEpO2lmKHQuYWRkRXZlbnRMaXN0ZW5lcil7
dC5hZGRFdmVudExpc3RlbmVyKCJET01Db250ZW50TG9hZGVkIix1LGZhbHNlKTtFLmFkZEV2ZW50
TGlzdGVuZXIoImxvYWQiLGIucmVhZHksZmFsc2UpfWVsc2UgaWYodC5hdHRhY2hFdmVudCl7dC5h
dHRhY2hFdmVudCgib25yZWFkeXN0YXRlY2hhbmdlIix1KTtFLmF0dGFjaEV2ZW50KCJvbmxvYWQi
LApiLnJlYWR5KTt2YXIgaj1mYWxzZTt0cnl7aj1FLmZyYW1lRWxlbWVudD09bnVsbH1jYXRjaChz
KXt9dC5kb2N1bWVudEVsZW1lbnQuZG9TY3JvbGwmJmomJmEoKX19fSxpc0Z1bmN0aW9uOmZ1bmN0
aW9uKGope3JldHVybiBiLnR5cGUoaik9PT0iZnVuY3Rpb24ifSxpc0FycmF5OkFycmF5LmlzQXJy
YXl8fGZ1bmN0aW9uKGope3JldHVybiBiLnR5cGUoaik9PT0iYXJyYXkifSxpc1dpbmRvdzpmdW5j
dGlvbihqKXtyZXR1cm4gaiYmdHlwZW9mIGo9PT0ib2JqZWN0IiYmInNldEludGVydmFsImluIGp9
LGlzTmFOOmZ1bmN0aW9uKGope3JldHVybiBqPT1udWxsfHwhci50ZXN0KGopfHxpc05hTihqKX0s
dHlwZTpmdW5jdGlvbihqKXtyZXR1cm4gaj09bnVsbD9TdHJpbmcoaik6Ult5LmNhbGwoaildfHwi
b2JqZWN0In0saXNQbGFpbk9iamVjdDpmdW5jdGlvbihqKXtpZighanx8Yi50eXBlKGopIT09Im9i
amVjdCJ8fGoubm9kZVR5cGV8fGIuaXNXaW5kb3coaikpcmV0dXJuIGZhbHNlO2lmKGouY29uc3Ry
dWN0b3ImJgohRi5jYWxsKGosImNvbnN0cnVjdG9yIikmJiFGLmNhbGwoai5jb25zdHJ1Y3Rvci5w
cm90b3R5cGUsImlzUHJvdG90eXBlT2YiKSlyZXR1cm4gZmFsc2U7Zm9yKHZhciBzIGluIGopO3Jl
dHVybiBzPT09Qnx8Ri5jYWxsKGoscyl9LGlzRW1wdHlPYmplY3Q6ZnVuY3Rpb24oail7Zm9yKHZh
ciBzIGluIGopcmV0dXJuIGZhbHNlO3JldHVybiB0cnVlfSxlcnJvcjpmdW5jdGlvbihqKXt0aHJv
dyBqO30scGFyc2VKU09OOmZ1bmN0aW9uKGope2lmKHR5cGVvZiBqIT09InN0cmluZyJ8fCFqKXJl
dHVybiBudWxsO2o9Yi50cmltKGopO2lmKEMudGVzdChqLnJlcGxhY2UoSiwiQCIpLnJlcGxhY2Uo
dywiXSIpLnJlcGxhY2UoSSwiIikpKXJldHVybiBFLkpTT04mJkUuSlNPTi5wYXJzZT9FLkpTT04u
cGFyc2Uoaik6KG5ldyBGdW5jdGlvbigicmV0dXJuICIraikpKCk7ZWxzZSBiLmVycm9yKCJJbnZh
bGlkIEpTT046ICIrail9LG5vb3A6ZnVuY3Rpb24oKXt9LGdsb2JhbEV2YWw6ZnVuY3Rpb24oail7
aWYoaiYmCmwudGVzdChqKSl7dmFyIHM9dC5nZXRFbGVtZW50c0J5VGFnTmFtZSgiaGVhZCIpWzBd
fHx0LmRvY3VtZW50RWxlbWVudCx2PXQuY3JlYXRlRWxlbWVudCgic2NyaXB0Iik7di50eXBlPSJ0
ZXh0L2phdmFzY3JpcHQiO2lmKGIuc3VwcG9ydC5zY3JpcHRFdmFsKXYuYXBwZW5kQ2hpbGQodC5j
cmVhdGVUZXh0Tm9kZShqKSk7ZWxzZSB2LnRleHQ9ajtzLmluc2VydEJlZm9yZSh2LHMuZmlyc3RD
aGlsZCk7cy5yZW1vdmVDaGlsZCh2KX19LG5vZGVOYW1lOmZ1bmN0aW9uKGoscyl7cmV0dXJuIGou
bm9kZU5hbWUmJmoubm9kZU5hbWUudG9VcHBlckNhc2UoKT09PXMudG9VcHBlckNhc2UoKX0sZWFj
aDpmdW5jdGlvbihqLHMsdil7dmFyIHosSD0wLEc9ai5sZW5ndGgsSz1HPT09Qnx8Yi5pc0Z1bmN0
aW9uKGopO2lmKHYpaWYoSylmb3IoeiBpbiBqKXtpZihzLmFwcGx5KGpbel0sdik9PT1mYWxzZSli
cmVha31lbHNlIGZvcig7SDxHOyl7aWYocy5hcHBseShqW0grK10sdik9PT1mYWxzZSlicmVha31l
bHNlIGlmKEspZm9yKHogaW4gail7aWYocy5jYWxsKGpbel0sCnosalt6XSk9PT1mYWxzZSlicmVh
a31lbHNlIGZvcih2PWpbMF07SDxHJiZzLmNhbGwodixILHYpIT09ZmFsc2U7dj1qWysrSF0pO3Jl
dHVybiBqfSx0cmltOk8/ZnVuY3Rpb24oail7cmV0dXJuIGo9PW51bGw/IiI6Ty5jYWxsKGopfTpm
dW5jdGlvbihqKXtyZXR1cm4gaj09bnVsbD8iIjpqLnRvU3RyaW5nKCkucmVwbGFjZShrLCIiKS5y
ZXBsYWNlKG8sIiIpfSxtYWtlQXJyYXk6ZnVuY3Rpb24oaixzKXt2YXIgdj1zfHxbXTtpZihqIT1u
dWxsKXt2YXIgej1iLnR5cGUoaik7ai5sZW5ndGg9PW51bGx8fHo9PT0ic3RyaW5nInx8ej09PSJm
dW5jdGlvbiJ8fHo9PT0icmVnZXhwInx8Yi5pc1dpbmRvdyhqKT9NLmNhbGwodixqKTpiLm1lcmdl
KHYsail9cmV0dXJuIHZ9LGluQXJyYXk6ZnVuY3Rpb24oaixzKXtpZihzLmluZGV4T2YpcmV0dXJu
IHMuaW5kZXhPZihqKTtmb3IodmFyIHY9MCx6PXMubGVuZ3RoO3Y8ejt2KyspaWYoc1t2XT09PWop
cmV0dXJuIHY7cmV0dXJuLTF9LG1lcmdlOmZ1bmN0aW9uKGosCnMpe3ZhciB2PWoubGVuZ3RoLHo9
MDtpZih0eXBlb2Ygcy5sZW5ndGg9PT0ibnVtYmVyIilmb3IodmFyIEg9cy5sZW5ndGg7ejxIO3or
KylqW3YrK109c1t6XTtlbHNlIGZvcig7c1t6XSE9PUI7KWpbdisrXT1zW3orK107ai5sZW5ndGg9
djtyZXR1cm4gan0sZ3JlcDpmdW5jdGlvbihqLHMsdil7dmFyIHo9W10sSDt2PSEhdjtmb3IodmFy
IEc9MCxLPWoubGVuZ3RoO0c8SztHKyspe0g9ISFzKGpbR10sRyk7diE9PUgmJnoucHVzaChqW0dd
KX1yZXR1cm4gen0sbWFwOmZ1bmN0aW9uKGoscyx2KXtmb3IodmFyIHo9W10sSCxHPTAsSz1qLmxl
bmd0aDtHPEs7RysrKXtIPXMoaltHXSxHLHYpO2lmKEghPW51bGwpelt6Lmxlbmd0aF09SH1yZXR1
cm4gei5jb25jYXQuYXBwbHkoW10seil9LGd1aWQ6MSxwcm94eTpmdW5jdGlvbihqLHMsdil7aWYo
YXJndW1lbnRzLmxlbmd0aD09PTIpaWYodHlwZW9mIHM9PT0ic3RyaW5nIil7dj1qO2o9dltzXTtz
PUJ9ZWxzZSBpZihzJiYhYi5pc0Z1bmN0aW9uKHMpKXt2PQpzO3M9Qn1pZighcyYmailzPWZ1bmN0
aW9uKCl7cmV0dXJuIGouYXBwbHkodnx8dGhpcyxhcmd1bWVudHMpfTtpZihqKXMuZ3VpZD1qLmd1
aWQ9ai5ndWlkfHxzLmd1aWR8fGIuZ3VpZCsrO3JldHVybiBzfSxhY2Nlc3M6ZnVuY3Rpb24oaixz
LHYseixILEcpe3ZhciBLPWoubGVuZ3RoO2lmKHR5cGVvZiBzPT09Im9iamVjdCIpe2Zvcih2YXIg
USBpbiBzKWIuYWNjZXNzKGosUSxzW1FdLHosSCx2KTtyZXR1cm4gan1pZih2IT09Qil7ej0hRyYm
eiYmYi5pc0Z1bmN0aW9uKHYpO2ZvcihRPTA7UTxLO1ErKylIKGpbUV0scyx6P3YuY2FsbChqW1Fd
LFEsSChqW1FdLHMpKTp2LEcpO3JldHVybiBqfXJldHVybiBLP0goalswXSxzKTpCfSxub3c6ZnVu
Y3Rpb24oKXtyZXR1cm4obmV3IERhdGUpLmdldFRpbWUoKX0sdWFNYXRjaDpmdW5jdGlvbihqKXtq
PWoudG9Mb3dlckNhc2UoKTtqPUwuZXhlYyhqKXx8Zy5leGVjKGopfHxpLmV4ZWMoail8fGouaW5k
ZXhPZigiY29tcGF0aWJsZSIpPDAmJm4uZXhlYyhqKXx8CltdO3JldHVybnticm93c2VyOmpbMV18
fCIiLHZlcnNpb246alsyXXx8IjAifX0sYnJvd3Nlcjp7fX0pO2IuZWFjaCgiQm9vbGVhbiBOdW1i
ZXIgU3RyaW5nIEZ1bmN0aW9uIEFycmF5IERhdGUgUmVnRXhwIE9iamVjdCIuc3BsaXQoIiAiKSxm
dW5jdGlvbihqLHMpe1JbIltvYmplY3QgIitzKyJdIl09cy50b0xvd2VyQ2FzZSgpfSk7bT1iLnVh
TWF0Y2gobSk7aWYobS5icm93c2VyKXtiLmJyb3dzZXJbbS5icm93c2VyXT10cnVlO2IuYnJvd3Nl
ci52ZXJzaW9uPW0udmVyc2lvbn1pZihiLmJyb3dzZXIud2Via2l0KWIuYnJvd3Nlci5zYWZhcmk9
dHJ1ZTtpZihEKWIuaW5BcnJheT1mdW5jdGlvbihqLHMpe3JldHVybiBELmNhbGwocyxqKX07aWYo
IS9ccy8udGVzdCgiXHUwMGEwIikpe2s9L15bXHNceEEwXSsvO289L1tcc1x4QTBdKyQvfWY9Yih0
KTtpZih0LmFkZEV2ZW50TGlzdGVuZXIpdT1mdW5jdGlvbigpe3QucmVtb3ZlRXZlbnRMaXN0ZW5l
cigiRE9NQ29udGVudExvYWRlZCIsdSwKZmFsc2UpO2IucmVhZHkoKX07ZWxzZSBpZih0LmF0dGFj
aEV2ZW50KXU9ZnVuY3Rpb24oKXtpZih0LnJlYWR5U3RhdGU9PT0iY29tcGxldGUiKXt0LmRldGFj
aEV2ZW50KCJvbnJlYWR5c3RhdGVjaGFuZ2UiLHUpO2IucmVhZHkoKX19O3JldHVybiBFLmpRdWVy
eT1FLiQ9Yn0oKTsoZnVuY3Rpb24oKXtjLnN1cHBvcnQ9e307dmFyIGE9dC5kb2N1bWVudEVsZW1l
bnQsYj10LmNyZWF0ZUVsZW1lbnQoInNjcmlwdCIpLGQ9dC5jcmVhdGVFbGVtZW50KCJkaXYiKSxl
PSJzY3JpcHQiK2Mubm93KCk7ZC5zdHlsZS5kaXNwbGF5PSJub25lIjtkLmlubmVySFRNTD0iICAg
PGxpbmsvPjx0YWJsZT48L3RhYmxlPjxhIGhyZWY9Jy9hJyBzdHlsZT0nY29sb3I6cmVkO2Zsb2F0
OmxlZnQ7b3BhY2l0eTouNTU7Jz5hPC9hPjxpbnB1dCB0eXBlPSdjaGVja2JveCcvPiI7dmFyIGY9
ZC5nZXRFbGVtZW50c0J5VGFnTmFtZSgiKiIpLGg9ZC5nZXRFbGVtZW50c0J5VGFnTmFtZSgiYSIp
WzBdLGw9dC5jcmVhdGVFbGVtZW50KCJzZWxlY3QiKSwKaz1sLmFwcGVuZENoaWxkKHQuY3JlYXRl
RWxlbWVudCgib3B0aW9uIikpO2lmKCEoIWZ8fCFmLmxlbmd0aHx8IWgpKXtjLnN1cHBvcnQ9e2xl
YWRpbmdXaGl0ZXNwYWNlOmQuZmlyc3RDaGlsZC5ub2RlVHlwZT09PTMsdGJvZHk6IWQuZ2V0RWxl
bWVudHNCeVRhZ05hbWUoInRib2R5IikubGVuZ3RoLGh0bWxTZXJpYWxpemU6ISFkLmdldEVsZW1l
bnRzQnlUYWdOYW1lKCJsaW5rIikubGVuZ3RoLHN0eWxlOi9yZWQvLnRlc3QoaC5nZXRBdHRyaWJ1
dGUoInN0eWxlIikpLGhyZWZOb3JtYWxpemVkOmguZ2V0QXR0cmlidXRlKCJocmVmIik9PT0iL2Ei
LG9wYWNpdHk6L14wLjU1JC8udGVzdChoLnN0eWxlLm9wYWNpdHkpLGNzc0Zsb2F0OiEhaC5zdHls
ZS5jc3NGbG9hdCxjaGVja09uOmQuZ2V0RWxlbWVudHNCeVRhZ05hbWUoImlucHV0IilbMF0udmFs
dWU9PT0ib24iLG9wdFNlbGVjdGVkOmsuc2VsZWN0ZWQsZGVsZXRlRXhwYW5kbzp0cnVlLG9wdERp
c2FibGVkOmZhbHNlLGNoZWNrQ2xvbmU6ZmFsc2UsCnNjcmlwdEV2YWw6ZmFsc2Usbm9DbG9uZUV2
ZW50OnRydWUsYm94TW9kZWw6bnVsbCxpbmxpbmVCbG9ja05lZWRzTGF5b3V0OmZhbHNlLHNocmlu
a1dyYXBCbG9ja3M6ZmFsc2UscmVsaWFibGVIaWRkZW5PZmZzZXRzOnRydWV9O2wuZGlzYWJsZWQ9
dHJ1ZTtjLnN1cHBvcnQub3B0RGlzYWJsZWQ9IWsuZGlzYWJsZWQ7Yi50eXBlPSJ0ZXh0L2phdmFz
Y3JpcHQiO3RyeXtiLmFwcGVuZENoaWxkKHQuY3JlYXRlVGV4dE5vZGUoIndpbmRvdy4iK2UrIj0x
OyIpKX1jYXRjaChvKXt9YS5pbnNlcnRCZWZvcmUoYixhLmZpcnN0Q2hpbGQpO2lmKEVbZV0pe2Mu
c3VwcG9ydC5zY3JpcHRFdmFsPXRydWU7ZGVsZXRlIEVbZV19dHJ5e2RlbGV0ZSBiLnRlc3R9Y2F0
Y2goeCl7Yy5zdXBwb3J0LmRlbGV0ZUV4cGFuZG89ZmFsc2V9YS5yZW1vdmVDaGlsZChiKTtpZihk
LmF0dGFjaEV2ZW50JiZkLmZpcmVFdmVudCl7ZC5hdHRhY2hFdmVudCgib25jbGljayIsZnVuY3Rp
b24gcigpe2Muc3VwcG9ydC5ub0Nsb25lRXZlbnQ9CmZhbHNlO2QuZGV0YWNoRXZlbnQoIm9uY2xp
Y2siLHIpfSk7ZC5jbG9uZU5vZGUodHJ1ZSkuZmlyZUV2ZW50KCJvbmNsaWNrIil9ZD10LmNyZWF0
ZUVsZW1lbnQoImRpdiIpO2QuaW5uZXJIVE1MPSI8aW5wdXQgdHlwZT0ncmFkaW8nIG5hbWU9J3Jh
ZGlvdGVzdCcgY2hlY2tlZD0nY2hlY2tlZCcvPiI7YT10LmNyZWF0ZURvY3VtZW50RnJhZ21lbnQo
KTthLmFwcGVuZENoaWxkKGQuZmlyc3RDaGlsZCk7Yy5zdXBwb3J0LmNoZWNrQ2xvbmU9YS5jbG9u
ZU5vZGUodHJ1ZSkuY2xvbmVOb2RlKHRydWUpLmxhc3RDaGlsZC5jaGVja2VkO2MoZnVuY3Rpb24o
KXt2YXIgcj10LmNyZWF0ZUVsZW1lbnQoImRpdiIpO3Iuc3R5bGUud2lkdGg9ci5zdHlsZS5wYWRk
aW5nTGVmdD0iMXB4Ijt0LmJvZHkuYXBwZW5kQ2hpbGQocik7Yy5ib3hNb2RlbD1jLnN1cHBvcnQu
Ym94TW9kZWw9ci5vZmZzZXRXaWR0aD09PTI7aWYoInpvb20iaW4gci5zdHlsZSl7ci5zdHlsZS5k
aXNwbGF5PSJpbmxpbmUiO3Iuc3R5bGUuem9vbT0KMTtjLnN1cHBvcnQuaW5saW5lQmxvY2tOZWVk
c0xheW91dD1yLm9mZnNldFdpZHRoPT09MjtyLnN0eWxlLmRpc3BsYXk9IiI7ci5pbm5lckhUTUw9
IjxkaXYgc3R5bGU9J3dpZHRoOjRweDsnPjwvZGl2PiI7Yy5zdXBwb3J0LnNocmlua1dyYXBCbG9j
a3M9ci5vZmZzZXRXaWR0aCE9PTJ9ci5pbm5lckhUTUw9Ijx0YWJsZT48dHI+PHRkIHN0eWxlPSdw
YWRkaW5nOjA7ZGlzcGxheTpub25lJz48L3RkPjx0ZD50PC90ZD48L3RyPjwvdGFibGU+Ijt2YXIg
QT1yLmdldEVsZW1lbnRzQnlUYWdOYW1lKCJ0ZCIpO2Muc3VwcG9ydC5yZWxpYWJsZUhpZGRlbk9m
ZnNldHM9QVswXS5vZmZzZXRIZWlnaHQ9PT0wO0FbMF0uc3R5bGUuZGlzcGxheT0iIjtBWzFdLnN0
eWxlLmRpc3BsYXk9Im5vbmUiO2Muc3VwcG9ydC5yZWxpYWJsZUhpZGRlbk9mZnNldHM9Yy5zdXBw
b3J0LnJlbGlhYmxlSGlkZGVuT2Zmc2V0cyYmQVswXS5vZmZzZXRIZWlnaHQ9PT0wO3IuaW5uZXJI
VE1MPSIiO3QuYm9keS5yZW1vdmVDaGlsZChyKS5zdHlsZS5kaXNwbGF5PQoibm9uZSJ9KTthPWZ1
bmN0aW9uKHIpe3ZhciBBPXQuY3JlYXRlRWxlbWVudCgiZGl2Iik7cj0ib24iK3I7dmFyIEM9ciBp
biBBO2lmKCFDKXtBLnNldEF0dHJpYnV0ZShyLCJyZXR1cm47Iik7Qz10eXBlb2YgQVtyXT09PSJm
dW5jdGlvbiJ9cmV0dXJuIEN9O2Muc3VwcG9ydC5zdWJtaXRCdWJibGVzPWEoInN1Ym1pdCIpO2Mu
c3VwcG9ydC5jaGFuZ2VCdWJibGVzPWEoImNoYW5nZSIpO2E9Yj1kPWY9aD1udWxsfX0pKCk7dmFy
IHJhPXt9LEphPS9eKD86XHsuKlx9fFxbLipcXSkkLztjLmV4dGVuZCh7Y2FjaGU6e30sdXVpZDow
LGV4cGFuZG86ImpRdWVyeSIrYy5ub3coKSxub0RhdGE6e2VtYmVkOnRydWUsb2JqZWN0OiJjbHNp
ZDpEMjdDREI2RS1BRTZELTExY2YtOTZCOC00NDQ1NTM1NDAwMDAiLGFwcGxldDp0cnVlfSxkYXRh
OmZ1bmN0aW9uKGEsYixkKXtpZihjLmFjY2VwdERhdGEoYSkpe2E9YT09RT9yYTphO3ZhciBlPWEu
bm9kZVR5cGUsZj1lP2FbYy5leHBhbmRvXTpudWxsLGg9CmMuY2FjaGU7aWYoIShlJiYhZiYmdHlw
ZW9mIGI9PT0ic3RyaW5nIiYmZD09PUIpKXtpZihlKWZ8fChhW2MuZXhwYW5kb109Zj0rK2MudXVp
ZCk7ZWxzZSBoPWE7aWYodHlwZW9mIGI9PT0ib2JqZWN0IilpZihlKWhbZl09Yy5leHRlbmQoaFtm
XSxiKTtlbHNlIGMuZXh0ZW5kKGgsYik7ZWxzZSBpZihlJiYhaFtmXSloW2ZdPXt9O2E9ZT9oW2Zd
Omg7aWYoZCE9PUIpYVtiXT1kO3JldHVybiB0eXBlb2YgYj09PSJzdHJpbmciP2FbYl06YX19fSxy
ZW1vdmVEYXRhOmZ1bmN0aW9uKGEsYil7aWYoYy5hY2NlcHREYXRhKGEpKXthPWE9PUU/cmE6YTt2
YXIgZD1hLm5vZGVUeXBlLGU9ZD9hW2MuZXhwYW5kb106YSxmPWMuY2FjaGUsaD1kP2ZbZV06ZTtp
ZihiKXtpZihoKXtkZWxldGUgaFtiXTtkJiZjLmlzRW1wdHlPYmplY3QoaCkmJmMucmVtb3ZlRGF0
YShhKX19ZWxzZSBpZihkJiZjLnN1cHBvcnQuZGVsZXRlRXhwYW5kbylkZWxldGUgYVtjLmV4cGFu
ZG9dO2Vsc2UgaWYoYS5yZW1vdmVBdHRyaWJ1dGUpYS5yZW1vdmVBdHRyaWJ1dGUoYy5leHBhbmRv
KTsKZWxzZSBpZihkKWRlbGV0ZSBmW2VdO2Vsc2UgZm9yKHZhciBsIGluIGEpZGVsZXRlIGFbbF19
fSxhY2NlcHREYXRhOmZ1bmN0aW9uKGEpe2lmKGEubm9kZU5hbWUpe3ZhciBiPWMubm9EYXRhW2Eu
bm9kZU5hbWUudG9Mb3dlckNhc2UoKV07aWYoYilyZXR1cm4hKGI9PT10cnVlfHxhLmdldEF0dHJp
YnV0ZSgiY2xhc3NpZCIpIT09Yil9cmV0dXJuIHRydWV9fSk7Yy5mbi5leHRlbmQoe2RhdGE6ZnVu
Y3Rpb24oYSxiKXt2YXIgZD1udWxsO2lmKHR5cGVvZiBhPT09InVuZGVmaW5lZCIpe2lmKHRoaXMu
bGVuZ3RoKXt2YXIgZT10aGlzWzBdLmF0dHJpYnV0ZXMsZjtkPWMuZGF0YSh0aGlzWzBdKTtmb3Io
dmFyIGg9MCxsPWUubGVuZ3RoO2g8bDtoKyspe2Y9ZVtoXS5uYW1lO2lmKGYuaW5kZXhPZigiZGF0
YS0iKT09PTApe2Y9Zi5zdWJzdHIoNSk7a2EodGhpc1swXSxmLGRbZl0pfX19cmV0dXJuIGR9ZWxz
ZSBpZih0eXBlb2YgYT09PSJvYmplY3QiKXJldHVybiB0aGlzLmVhY2goZnVuY3Rpb24oKXtjLmRh
dGEodGhpcywKYSl9KTt2YXIgaz1hLnNwbGl0KCIuIik7a1sxXT1rWzFdPyIuIitrWzFdOiIiO2lm
KGI9PT1CKXtkPXRoaXMudHJpZ2dlckhhbmRsZXIoImdldERhdGEiK2tbMV0rIiEiLFtrWzBdXSk7
aWYoZD09PUImJnRoaXMubGVuZ3RoKXtkPWMuZGF0YSh0aGlzWzBdLGEpO2Q9a2EodGhpc1swXSxh
LGQpfXJldHVybiBkPT09QiYma1sxXT90aGlzLmRhdGEoa1swXSk6ZH1lbHNlIHJldHVybiB0aGlz
LmVhY2goZnVuY3Rpb24oKXt2YXIgbz1jKHRoaXMpLHg9W2tbMF0sYl07by50cmlnZ2VySGFuZGxl
cigic2V0RGF0YSIra1sxXSsiISIseCk7Yy5kYXRhKHRoaXMsYSxiKTtvLnRyaWdnZXJIYW5kbGVy
KCJjaGFuZ2VEYXRhIitrWzFdKyIhIix4KX0pfSxyZW1vdmVEYXRhOmZ1bmN0aW9uKGEpe3JldHVy
biB0aGlzLmVhY2goZnVuY3Rpb24oKXtjLnJlbW92ZURhdGEodGhpcyxhKX0pfX0pO2MuZXh0ZW5k
KHtxdWV1ZTpmdW5jdGlvbihhLGIsZCl7aWYoYSl7Yj0oYnx8ImZ4IikrInF1ZXVlIjt2YXIgZT0K
Yy5kYXRhKGEsYik7aWYoIWQpcmV0dXJuIGV8fFtdO2lmKCFlfHxjLmlzQXJyYXkoZCkpZT1jLmRh
dGEoYSxiLGMubWFrZUFycmF5KGQpKTtlbHNlIGUucHVzaChkKTtyZXR1cm4gZX19LGRlcXVldWU6
ZnVuY3Rpb24oYSxiKXtiPWJ8fCJmeCI7dmFyIGQ9Yy5xdWV1ZShhLGIpLGU9ZC5zaGlmdCgpO2lm
KGU9PT0iaW5wcm9ncmVzcyIpZT1kLnNoaWZ0KCk7aWYoZSl7Yj09PSJmeCImJmQudW5zaGlmdCgi
aW5wcm9ncmVzcyIpO2UuY2FsbChhLGZ1bmN0aW9uKCl7Yy5kZXF1ZXVlKGEsYil9KX19fSk7Yy5m
bi5leHRlbmQoe3F1ZXVlOmZ1bmN0aW9uKGEsYil7aWYodHlwZW9mIGEhPT0ic3RyaW5nIil7Yj1h
O2E9ImZ4In1pZihiPT09QilyZXR1cm4gYy5xdWV1ZSh0aGlzWzBdLGEpO3JldHVybiB0aGlzLmVh
Y2goZnVuY3Rpb24oKXt2YXIgZD1jLnF1ZXVlKHRoaXMsYSxiKTthPT09ImZ4IiYmZFswXSE9PSJp
bnByb2dyZXNzIiYmYy5kZXF1ZXVlKHRoaXMsYSl9KX0sZGVxdWV1ZTpmdW5jdGlvbihhKXtyZXR1
cm4gdGhpcy5lYWNoKGZ1bmN0aW9uKCl7Yy5kZXF1ZXVlKHRoaXMsCmEpfSl9LGRlbGF5OmZ1bmN0
aW9uKGEsYil7YT1jLmZ4P2MuZnguc3BlZWRzW2FdfHxhOmE7Yj1ifHwiZngiO3JldHVybiB0aGlz
LnF1ZXVlKGIsZnVuY3Rpb24oKXt2YXIgZD10aGlzO3NldFRpbWVvdXQoZnVuY3Rpb24oKXtjLmRl
cXVldWUoZCxiKX0sYSl9KX0sY2xlYXJRdWV1ZTpmdW5jdGlvbihhKXtyZXR1cm4gdGhpcy5xdWV1
ZShhfHwiZngiLFtdKX19KTt2YXIgc2E9L1tcblx0XS9nLGhhPS9ccysvLFNhPS9cci9nLFRhPS9e
KD86aHJlZnxzcmN8c3R5bGUpJC8sVWE9L14oPzpidXR0b258aW5wdXQpJC9pLFZhPS9eKD86YnV0
dG9ufGlucHV0fG9iamVjdHxzZWxlY3R8dGV4dGFyZWEpJC9pLFdhPS9eYSg/OnJlYSk/JC9pLHRh
PS9eKD86cmFkaW98Y2hlY2tib3gpJC9pO2MucHJvcHM9eyJmb3IiOiJodG1sRm9yIiwiY2xhc3Mi
OiJjbGFzc05hbWUiLHJlYWRvbmx5OiJyZWFkT25seSIsbWF4bGVuZ3RoOiJtYXhMZW5ndGgiLGNl
bGxzcGFjaW5nOiJjZWxsU3BhY2luZyIscm93c3Bhbjoicm93U3BhbiIsCmNvbHNwYW46ImNvbFNw
YW4iLHRhYmluZGV4OiJ0YWJJbmRleCIsdXNlbWFwOiJ1c2VNYXAiLGZyYW1lYm9yZGVyOiJmcmFt
ZUJvcmRlciJ9O2MuZm4uZXh0ZW5kKHthdHRyOmZ1bmN0aW9uKGEsYil7cmV0dXJuIGMuYWNjZXNz
KHRoaXMsYSxiLHRydWUsYy5hdHRyKX0scmVtb3ZlQXR0cjpmdW5jdGlvbihhKXtyZXR1cm4gdGhp
cy5lYWNoKGZ1bmN0aW9uKCl7Yy5hdHRyKHRoaXMsYSwiIik7dGhpcy5ub2RlVHlwZT09PTEmJnRo
aXMucmVtb3ZlQXR0cmlidXRlKGEpfSl9LGFkZENsYXNzOmZ1bmN0aW9uKGEpe2lmKGMuaXNGdW5j
dGlvbihhKSlyZXR1cm4gdGhpcy5lYWNoKGZ1bmN0aW9uKHgpe3ZhciByPWModGhpcyk7ci5hZGRD
bGFzcyhhLmNhbGwodGhpcyx4LHIuYXR0cigiY2xhc3MiKSkpfSk7aWYoYSYmdHlwZW9mIGE9PT0i
c3RyaW5nIilmb3IodmFyIGI9KGF8fCIiKS5zcGxpdChoYSksZD0wLGU9dGhpcy5sZW5ndGg7ZDxl
O2QrKyl7dmFyIGY9dGhpc1tkXTtpZihmLm5vZGVUeXBlPT09CjEpaWYoZi5jbGFzc05hbWUpe2Zv
cih2YXIgaD0iICIrZi5jbGFzc05hbWUrIiAiLGw9Zi5jbGFzc05hbWUsaz0wLG89Yi5sZW5ndGg7
azxvO2srKylpZihoLmluZGV4T2YoIiAiK2Jba10rIiAiKTwwKWwrPSIgIitiW2tdO2YuY2xhc3NO
YW1lPWMudHJpbShsKX1lbHNlIGYuY2xhc3NOYW1lPWF9cmV0dXJuIHRoaXN9LHJlbW92ZUNsYXNz
OmZ1bmN0aW9uKGEpe2lmKGMuaXNGdW5jdGlvbihhKSlyZXR1cm4gdGhpcy5lYWNoKGZ1bmN0aW9u
KG8pe3ZhciB4PWModGhpcyk7eC5yZW1vdmVDbGFzcyhhLmNhbGwodGhpcyxvLHguYXR0cigiY2xh
c3MiKSkpfSk7aWYoYSYmdHlwZW9mIGE9PT0ic3RyaW5nInx8YT09PUIpZm9yKHZhciBiPShhfHwi
Iikuc3BsaXQoaGEpLGQ9MCxlPXRoaXMubGVuZ3RoO2Q8ZTtkKyspe3ZhciBmPXRoaXNbZF07aWYo
Zi5ub2RlVHlwZT09PTEmJmYuY2xhc3NOYW1lKWlmKGEpe2Zvcih2YXIgaD0oIiAiK2YuY2xhc3NO
YW1lKyIgIikucmVwbGFjZShzYSwiICIpLApsPTAsaz1iLmxlbmd0aDtsPGs7bCsrKWg9aC5yZXBs
YWNlKCIgIitiW2xdKyIgIiwiICIpO2YuY2xhc3NOYW1lPWMudHJpbShoKX1lbHNlIGYuY2xhc3NO
YW1lPSIifXJldHVybiB0aGlzfSx0b2dnbGVDbGFzczpmdW5jdGlvbihhLGIpe3ZhciBkPXR5cGVv
ZiBhLGU9dHlwZW9mIGI9PT0iYm9vbGVhbiI7aWYoYy5pc0Z1bmN0aW9uKGEpKXJldHVybiB0aGlz
LmVhY2goZnVuY3Rpb24oZil7dmFyIGg9Yyh0aGlzKTtoLnRvZ2dsZUNsYXNzKGEuY2FsbCh0aGlz
LGYsaC5hdHRyKCJjbGFzcyIpLGIpLGIpfSk7cmV0dXJuIHRoaXMuZWFjaChmdW5jdGlvbigpe2lm
KGQ9PT0ic3RyaW5nIilmb3IodmFyIGYsaD0wLGw9Yyh0aGlzKSxrPWIsbz1hLnNwbGl0KGhhKTtm
PW9baCsrXTspe2s9ZT9rOiFsLmhhc0NsYXNzKGYpO2xbaz8iYWRkQ2xhc3MiOiJyZW1vdmVDbGFz
cyJdKGYpfWVsc2UgaWYoZD09PSJ1bmRlZmluZWQifHxkPT09ImJvb2xlYW4iKXt0aGlzLmNsYXNz
TmFtZSYmYy5kYXRhKHRoaXMsCiJfX2NsYXNzTmFtZV9fIix0aGlzLmNsYXNzTmFtZSk7dGhpcy5j
bGFzc05hbWU9dGhpcy5jbGFzc05hbWV8fGE9PT1mYWxzZT8iIjpjLmRhdGEodGhpcywiX19jbGFz
c05hbWVfXyIpfHwiIn19KX0saGFzQ2xhc3M6ZnVuY3Rpb24oYSl7YT0iICIrYSsiICI7Zm9yKHZh
ciBiPTAsZD10aGlzLmxlbmd0aDtiPGQ7YisrKWlmKCgiICIrdGhpc1tiXS5jbGFzc05hbWUrIiAi
KS5yZXBsYWNlKHNhLCIgIikuaW5kZXhPZihhKT4tMSlyZXR1cm4gdHJ1ZTtyZXR1cm4gZmFsc2V9
LHZhbDpmdW5jdGlvbihhKXtpZighYXJndW1lbnRzLmxlbmd0aCl7dmFyIGI9dGhpc1swXTtpZihi
KXtpZihjLm5vZGVOYW1lKGIsIm9wdGlvbiIpKXt2YXIgZD1iLmF0dHJpYnV0ZXMudmFsdWU7cmV0
dXJuIWR8fGQuc3BlY2lmaWVkP2IudmFsdWU6Yi50ZXh0fWlmKGMubm9kZU5hbWUoYiwic2VsZWN0
Iikpe3ZhciBlPWIuc2VsZWN0ZWRJbmRleDtkPVtdO3ZhciBmPWIub3B0aW9ucztiPWIudHlwZT09
PSJzZWxlY3Qtb25lIjsKaWYoZTwwKXJldHVybiBudWxsO3ZhciBoPWI/ZTowO2ZvcihlPWI/ZSsx
OmYubGVuZ3RoO2g8ZTtoKyspe3ZhciBsPWZbaF07aWYobC5zZWxlY3RlZCYmKGMuc3VwcG9ydC5v
cHREaXNhYmxlZD8hbC5kaXNhYmxlZDpsLmdldEF0dHJpYnV0ZSgiZGlzYWJsZWQiKT09PW51bGwp
JiYoIWwucGFyZW50Tm9kZS5kaXNhYmxlZHx8IWMubm9kZU5hbWUobC5wYXJlbnROb2RlLCJvcHRn
cm91cCIpKSl7YT1jKGwpLnZhbCgpO2lmKGIpcmV0dXJuIGE7ZC5wdXNoKGEpfX1yZXR1cm4gZH1p
Zih0YS50ZXN0KGIudHlwZSkmJiFjLnN1cHBvcnQuY2hlY2tPbilyZXR1cm4gYi5nZXRBdHRyaWJ1
dGUoInZhbHVlIik9PT1udWxsPyJvbiI6Yi52YWx1ZTtyZXR1cm4oYi52YWx1ZXx8IiIpLnJlcGxh
Y2UoU2EsIiIpfXJldHVybiBCfXZhciBrPWMuaXNGdW5jdGlvbihhKTtyZXR1cm4gdGhpcy5lYWNo
KGZ1bmN0aW9uKG8pe3ZhciB4PWModGhpcykscj1hO2lmKHRoaXMubm9kZVR5cGU9PT0xKXtpZihr
KXI9CmEuY2FsbCh0aGlzLG8seC52YWwoKSk7aWYocj09bnVsbClyPSIiO2Vsc2UgaWYodHlwZW9m
IHI9PT0ibnVtYmVyIilyKz0iIjtlbHNlIGlmKGMuaXNBcnJheShyKSlyPWMubWFwKHIsZnVuY3Rp
b24oQyl7cmV0dXJuIEM9PW51bGw/IiI6QysiIn0pO2lmKGMuaXNBcnJheShyKSYmdGEudGVzdCh0
aGlzLnR5cGUpKXRoaXMuY2hlY2tlZD1jLmluQXJyYXkoeC52YWwoKSxyKT49MDtlbHNlIGlmKGMu
bm9kZU5hbWUodGhpcywic2VsZWN0Iikpe3ZhciBBPWMubWFrZUFycmF5KHIpO2MoIm9wdGlvbiIs
dGhpcykuZWFjaChmdW5jdGlvbigpe3RoaXMuc2VsZWN0ZWQ9Yy5pbkFycmF5KGModGhpcykudmFs
KCksQSk+PTB9KTtpZighQS5sZW5ndGgpdGhpcy5zZWxlY3RlZEluZGV4PS0xfWVsc2UgdGhpcy52
YWx1ZT1yfX0pfX0pO2MuZXh0ZW5kKHthdHRyRm46e3ZhbDp0cnVlLGNzczp0cnVlLGh0bWw6dHJ1
ZSx0ZXh0OnRydWUsZGF0YTp0cnVlLHdpZHRoOnRydWUsaGVpZ2h0OnRydWUsb2Zmc2V0OnRydWV9
LAphdHRyOmZ1bmN0aW9uKGEsYixkLGUpe2lmKCFhfHxhLm5vZGVUeXBlPT09M3x8YS5ub2RlVHlw
ZT09PTgpcmV0dXJuIEI7aWYoZSYmYiBpbiBjLmF0dHJGbilyZXR1cm4gYyhhKVtiXShkKTtlPWEu
bm9kZVR5cGUhPT0xfHwhYy5pc1hNTERvYyhhKTt2YXIgZj1kIT09QjtiPWUmJmMucHJvcHNbYl18
fGI7dmFyIGg9VGEudGVzdChiKTtpZigoYiBpbiBhfHxhW2JdIT09QikmJmUmJiFoKXtpZihmKXti
PT09InR5cGUiJiZVYS50ZXN0KGEubm9kZU5hbWUpJiZhLnBhcmVudE5vZGUmJmMuZXJyb3IoInR5
cGUgcHJvcGVydHkgY2FuJ3QgYmUgY2hhbmdlZCIpO2lmKGQ9PT1udWxsKWEubm9kZVR5cGU9PT0x
JiZhLnJlbW92ZUF0dHJpYnV0ZShiKTtlbHNlIGFbYl09ZH1pZihjLm5vZGVOYW1lKGEsImZvcm0i
KSYmYS5nZXRBdHRyaWJ1dGVOb2RlKGIpKXJldHVybiBhLmdldEF0dHJpYnV0ZU5vZGUoYikubm9k
ZVZhbHVlO2lmKGI9PT0idGFiSW5kZXgiKXJldHVybihiPWEuZ2V0QXR0cmlidXRlTm9kZSgidGFi
SW5kZXgiKSkmJgpiLnNwZWNpZmllZD9iLnZhbHVlOlZhLnRlc3QoYS5ub2RlTmFtZSl8fFdhLnRl
c3QoYS5ub2RlTmFtZSkmJmEuaHJlZj8wOkI7cmV0dXJuIGFbYl19aWYoIWMuc3VwcG9ydC5zdHls
ZSYmZSYmYj09PSJzdHlsZSIpe2lmKGYpYS5zdHlsZS5jc3NUZXh0PSIiK2Q7cmV0dXJuIGEuc3R5
bGUuY3NzVGV4dH1mJiZhLnNldEF0dHJpYnV0ZShiLCIiK2QpO2lmKCFhLmF0dHJpYnV0ZXNbYl0m
JmEuaGFzQXR0cmlidXRlJiYhYS5oYXNBdHRyaWJ1dGUoYikpcmV0dXJuIEI7YT0hYy5zdXBwb3J0
LmhyZWZOb3JtYWxpemVkJiZlJiZoP2EuZ2V0QXR0cmlidXRlKGIsMik6YS5nZXRBdHRyaWJ1dGUo
Yik7cmV0dXJuIGE9PT1udWxsP0I6YX19KTt2YXIgWD0vXC4oLiopJC8saWE9L14oPzp0ZXh0YXJl
YXxpbnB1dHxzZWxlY3QpJC9pLExhPS9cLi9nLE1hPS8gL2csWGE9L1teXHdccy58YF0vZyxZYT1m
dW5jdGlvbihhKXtyZXR1cm4gYS5yZXBsYWNlKFhhLCJcXCQmIil9LHVhPXtmb2N1c2luOjAsZm9j
dXNvdXQ6MH07CmMuZXZlbnQ9e2FkZDpmdW5jdGlvbihhLGIsZCxlKXtpZighKGEubm9kZVR5cGU9
PT0zfHxhLm5vZGVUeXBlPT09OCkpe2lmKGMuaXNXaW5kb3coYSkmJmEhPT1FJiYhYS5mcmFtZUVs
ZW1lbnQpYT1FO2lmKGQ9PT1mYWxzZSlkPVU7ZWxzZSBpZighZClyZXR1cm47dmFyIGYsaDtpZihk
LmhhbmRsZXIpe2Y9ZDtkPWYuaGFuZGxlcn1pZighZC5ndWlkKWQuZ3VpZD1jLmd1aWQrKztpZiho
PWMuZGF0YShhKSl7dmFyIGw9YS5ub2RlVHlwZT8iZXZlbnRzIjoiX19ldmVudHNfXyIsaz1oW2xd
LG89aC5oYW5kbGU7aWYodHlwZW9mIGs9PT0iZnVuY3Rpb24iKXtvPWsuaGFuZGxlO2s9ay5ldmVu
dHN9ZWxzZSBpZighayl7YS5ub2RlVHlwZXx8KGhbbF09aD1mdW5jdGlvbigpe30pO2guZXZlbnRz
PWs9e319aWYoIW8paC5oYW5kbGU9bz1mdW5jdGlvbigpe3JldHVybiB0eXBlb2YgYyE9PSJ1bmRl
ZmluZWQiJiYhYy5ldmVudC50cmlnZ2VyZWQ/Yy5ldmVudC5oYW5kbGUuYXBwbHkoby5lbGVtLAph
cmd1bWVudHMpOkJ9O28uZWxlbT1hO2I9Yi5zcGxpdCgiICIpO2Zvcih2YXIgeD0wLHI7bD1iW3gr
K107KXtoPWY/Yy5leHRlbmQoe30sZik6e2hhbmRsZXI6ZCxkYXRhOmV9O2lmKGwuaW5kZXhPZigi
LiIpPi0xKXtyPWwuc3BsaXQoIi4iKTtsPXIuc2hpZnQoKTtoLm5hbWVzcGFjZT1yLnNsaWNlKDAp
LnNvcnQoKS5qb2luKCIuIil9ZWxzZXtyPVtdO2gubmFtZXNwYWNlPSIifWgudHlwZT1sO2lmKCFo
Lmd1aWQpaC5ndWlkPWQuZ3VpZDt2YXIgQT1rW2xdLEM9Yy5ldmVudC5zcGVjaWFsW2xdfHx7fTtp
ZighQSl7QT1rW2xdPVtdO2lmKCFDLnNldHVwfHxDLnNldHVwLmNhbGwoYSxlLHIsbyk9PT1mYWxz
ZSlpZihhLmFkZEV2ZW50TGlzdGVuZXIpYS5hZGRFdmVudExpc3RlbmVyKGwsbyxmYWxzZSk7ZWxz
ZSBhLmF0dGFjaEV2ZW50JiZhLmF0dGFjaEV2ZW50KCJvbiIrbCxvKX1pZihDLmFkZCl7Qy5hZGQu
Y2FsbChhLGgpO2lmKCFoLmhhbmRsZXIuZ3VpZCloLmhhbmRsZXIuZ3VpZD0KZC5ndWlkfUEucHVz
aChoKTtjLmV2ZW50Lmdsb2JhbFtsXT10cnVlfWE9bnVsbH19fSxnbG9iYWw6e30scmVtb3ZlOmZ1
bmN0aW9uKGEsYixkLGUpe2lmKCEoYS5ub2RlVHlwZT09PTN8fGEubm9kZVR5cGU9PT04KSl7aWYo
ZD09PWZhbHNlKWQ9VTt2YXIgZixoLGw9MCxrLG8seCxyLEEsQyxKPWEubm9kZVR5cGU/ImV2ZW50
cyI6Il9fZXZlbnRzX18iLHc9Yy5kYXRhKGEpLEk9dyYmd1tKXTtpZih3JiZJKXtpZih0eXBlb2Yg
ST09PSJmdW5jdGlvbiIpe3c9STtJPUkuZXZlbnRzfWlmKGImJmIudHlwZSl7ZD1iLmhhbmRsZXI7
Yj1iLnR5cGV9aWYoIWJ8fHR5cGVvZiBiPT09InN0cmluZyImJmIuY2hhckF0KDApPT09Ii4iKXti
PWJ8fCIiO2ZvcihmIGluIEkpYy5ldmVudC5yZW1vdmUoYSxmK2IpfWVsc2V7Zm9yKGI9Yi5zcGxp
dCgiICIpO2Y9YltsKytdOyl7cj1mO2s9Zi5pbmRleE9mKCIuIik8MDtvPVtdO2lmKCFrKXtvPWYu
c3BsaXQoIi4iKTtmPW8uc2hpZnQoKTt4PVJlZ0V4cCgiKF58XFwuKSIrCmMubWFwKG8uc2xpY2Uo
MCkuc29ydCgpLFlhKS5qb2luKCJcXC4oPzouKlxcLik/IikrIihcXC58JCkiKX1pZihBPUlbZl0p
aWYoZCl7cj1jLmV2ZW50LnNwZWNpYWxbZl18fHt9O2ZvcihoPWV8fDA7aDxBLmxlbmd0aDtoKysp
e0M9QVtoXTtpZihkLmd1aWQ9PT1DLmd1aWQpe2lmKGt8fHgudGVzdChDLm5hbWVzcGFjZSkpe2U9
PW51bGwmJkEuc3BsaWNlKGgtLSwxKTtyLnJlbW92ZSYmci5yZW1vdmUuY2FsbChhLEMpfWlmKGUh
PW51bGwpYnJlYWt9fWlmKEEubGVuZ3RoPT09MHx8ZSE9bnVsbCYmQS5sZW5ndGg9PT0xKXtpZigh
ci50ZWFyZG93bnx8ci50ZWFyZG93bi5jYWxsKGEsbyk9PT1mYWxzZSljLnJlbW92ZUV2ZW50KGEs
Zix3LmhhbmRsZSk7ZGVsZXRlIElbZl19fWVsc2UgZm9yKGg9MDtoPEEubGVuZ3RoO2grKyl7Qz1B
W2hdO2lmKGt8fHgudGVzdChDLm5hbWVzcGFjZSkpe2MuZXZlbnQucmVtb3ZlKGEscixDLmhhbmRs
ZXIsaCk7QS5zcGxpY2UoaC0tLDEpfX19aWYoYy5pc0VtcHR5T2JqZWN0KEkpKXtpZihiPQp3Lmhh
bmRsZSliLmVsZW09bnVsbDtkZWxldGUgdy5ldmVudHM7ZGVsZXRlIHcuaGFuZGxlO2lmKHR5cGVv
ZiB3PT09ImZ1bmN0aW9uIiljLnJlbW92ZURhdGEoYSxKKTtlbHNlIGMuaXNFbXB0eU9iamVjdCh3
KSYmYy5yZW1vdmVEYXRhKGEpfX19fX0sdHJpZ2dlcjpmdW5jdGlvbihhLGIsZCxlKXt2YXIgZj1h
LnR5cGV8fGE7aWYoIWUpe2E9dHlwZW9mIGE9PT0ib2JqZWN0Ij9hW2MuZXhwYW5kb10/YTpjLmV4
dGVuZChjLkV2ZW50KGYpLGEpOmMuRXZlbnQoZik7aWYoZi5pbmRleE9mKCIhIik+PTApe2EudHlw
ZT1mPWYuc2xpY2UoMCwtMSk7YS5leGNsdXNpdmU9dHJ1ZX1pZighZCl7YS5zdG9wUHJvcGFnYXRp
b24oKTtjLmV2ZW50Lmdsb2JhbFtmXSYmYy5lYWNoKGMuY2FjaGUsZnVuY3Rpb24oKXt0aGlzLmV2
ZW50cyYmdGhpcy5ldmVudHNbZl0mJmMuZXZlbnQudHJpZ2dlcihhLGIsdGhpcy5oYW5kbGUuZWxl
bSl9KX1pZighZHx8ZC5ub2RlVHlwZT09PTN8fGQubm9kZVR5cGU9PT0KOClyZXR1cm4gQjthLnJl
c3VsdD1CO2EudGFyZ2V0PWQ7Yj1jLm1ha2VBcnJheShiKTtiLnVuc2hpZnQoYSl9YS5jdXJyZW50
VGFyZ2V0PWQ7KGU9ZC5ub2RlVHlwZT9jLmRhdGEoZCwiaGFuZGxlIik6KGMuZGF0YShkLCJfX2V2
ZW50c19fIil8fHt9KS5oYW5kbGUpJiZlLmFwcGx5KGQsYik7ZT1kLnBhcmVudE5vZGV8fGQub3du
ZXJEb2N1bWVudDt0cnl7aWYoIShkJiZkLm5vZGVOYW1lJiZjLm5vRGF0YVtkLm5vZGVOYW1lLnRv
TG93ZXJDYXNlKCldKSlpZihkWyJvbiIrZl0mJmRbIm9uIitmXS5hcHBseShkLGIpPT09ZmFsc2Up
e2EucmVzdWx0PWZhbHNlO2EucHJldmVudERlZmF1bHQoKX19Y2F0Y2goaCl7fWlmKCFhLmlzUHJv
cGFnYXRpb25TdG9wcGVkKCkmJmUpYy5ldmVudC50cmlnZ2VyKGEsYixlLHRydWUpO2Vsc2UgaWYo
IWEuaXNEZWZhdWx0UHJldmVudGVkKCkpe3ZhciBsO2U9YS50YXJnZXQ7dmFyIGs9Zi5yZXBsYWNl
KFgsIiIpLG89Yy5ub2RlTmFtZShlLCJhIikmJms9PT0KImNsaWNrIix4PWMuZXZlbnQuc3BlY2lh
bFtrXXx8e307aWYoKCF4Ll9kZWZhdWx0fHx4Ll9kZWZhdWx0LmNhbGwoZCxhKT09PWZhbHNlKSYm
IW8mJiEoZSYmZS5ub2RlTmFtZSYmYy5ub0RhdGFbZS5ub2RlTmFtZS50b0xvd2VyQ2FzZSgpXSkp
e3RyeXtpZihlW2tdKXtpZihsPWVbIm9uIitrXSllWyJvbiIra109bnVsbDtjLmV2ZW50LnRyaWdn
ZXJlZD10cnVlO2Vba10oKX19Y2F0Y2gocil7fWlmKGwpZVsib24iK2tdPWw7Yy5ldmVudC50cmln
Z2VyZWQ9ZmFsc2V9fX0saGFuZGxlOmZ1bmN0aW9uKGEpe3ZhciBiLGQsZSxmO2Q9W107dmFyIGg9
Yy5tYWtlQXJyYXkoYXJndW1lbnRzKTthPWhbMF09Yy5ldmVudC5maXgoYXx8RS5ldmVudCk7YS5j
dXJyZW50VGFyZ2V0PXRoaXM7Yj1hLnR5cGUuaW5kZXhPZigiLiIpPDAmJiFhLmV4Y2x1c2l2ZTtp
ZighYil7ZT1hLnR5cGUuc3BsaXQoIi4iKTthLnR5cGU9ZS5zaGlmdCgpO2Q9ZS5zbGljZSgwKS5z
b3J0KCk7ZT1SZWdFeHAoIihefFxcLikiKwpkLmpvaW4oIlxcLig/Oi4qXFwuKT8iKSsiKFxcLnwk
KSIpfWEubmFtZXNwYWNlPWEubmFtZXNwYWNlfHxkLmpvaW4oIi4iKTtmPWMuZGF0YSh0aGlzLHRo
aXMubm9kZVR5cGU/ImV2ZW50cyI6Il9fZXZlbnRzX18iKTtpZih0eXBlb2YgZj09PSJmdW5jdGlv
biIpZj1mLmV2ZW50cztkPShmfHx7fSlbYS50eXBlXTtpZihmJiZkKXtkPWQuc2xpY2UoMCk7Zj0w
O2Zvcih2YXIgbD1kLmxlbmd0aDtmPGw7ZisrKXt2YXIgaz1kW2ZdO2lmKGJ8fGUudGVzdChrLm5h
bWVzcGFjZSkpe2EuaGFuZGxlcj1rLmhhbmRsZXI7YS5kYXRhPWsuZGF0YTthLmhhbmRsZU9iaj1r
O2s9ay5oYW5kbGVyLmFwcGx5KHRoaXMsaCk7aWYoayE9PUIpe2EucmVzdWx0PWs7aWYoaz09PWZh
bHNlKXthLnByZXZlbnREZWZhdWx0KCk7YS5zdG9wUHJvcGFnYXRpb24oKX19aWYoYS5pc0ltbWVk
aWF0ZVByb3BhZ2F0aW9uU3RvcHBlZCgpKWJyZWFrfX19cmV0dXJuIGEucmVzdWx0fSxwcm9wczoi
YWx0S2V5IGF0dHJDaGFuZ2UgYXR0ck5hbWUgYnViYmxlcyBidXR0b24gY2FuY2VsYWJsZSBjaGFy
Q29kZSBjbGllbnRYIGNsaWVudFkgY3RybEtleSBjdXJyZW50VGFyZ2V0IGRhdGEgZGV0YWlsIGV2
ZW50UGhhc2UgZnJvbUVsZW1lbnQgaGFuZGxlciBrZXlDb2RlIGxheWVyWCBsYXllclkgbWV0YUtl
eSBuZXdWYWx1ZSBvZmZzZXRYIG9mZnNldFkgcGFnZVggcGFnZVkgcHJldlZhbHVlIHJlbGF0ZWRO
b2RlIHJlbGF0ZWRUYXJnZXQgc2NyZWVuWCBzY3JlZW5ZIHNoaWZ0S2V5IHNyY0VsZW1lbnQgdGFy
Z2V0IHRvRWxlbWVudCB2aWV3IHdoZWVsRGVsdGEgd2hpY2giLnNwbGl0KCIgIiksCmZpeDpmdW5j
dGlvbihhKXtpZihhW2MuZXhwYW5kb10pcmV0dXJuIGE7dmFyIGI9YTthPWMuRXZlbnQoYik7Zm9y
KHZhciBkPXRoaXMucHJvcHMubGVuZ3RoLGU7ZDspe2U9dGhpcy5wcm9wc1stLWRdO2FbZV09Yltl
XX1pZighYS50YXJnZXQpYS50YXJnZXQ9YS5zcmNFbGVtZW50fHx0O2lmKGEudGFyZ2V0Lm5vZGVU
eXBlPT09MylhLnRhcmdldD1hLnRhcmdldC5wYXJlbnROb2RlO2lmKCFhLnJlbGF0ZWRUYXJnZXQm
JmEuZnJvbUVsZW1lbnQpYS5yZWxhdGVkVGFyZ2V0PWEuZnJvbUVsZW1lbnQ9PT1hLnRhcmdldD9h
LnRvRWxlbWVudDphLmZyb21FbGVtZW50O2lmKGEucGFnZVg9PW51bGwmJmEuY2xpZW50WCE9bnVs
bCl7Yj10LmRvY3VtZW50RWxlbWVudDtkPXQuYm9keTthLnBhZ2VYPWEuY2xpZW50WCsoYiYmYi5z
Y3JvbGxMZWZ0fHxkJiZkLnNjcm9sbExlZnR8fDApLShiJiZiLmNsaWVudExlZnR8fGQmJmQuY2xp
ZW50TGVmdHx8MCk7YS5wYWdlWT1hLmNsaWVudFkrKGImJmIuc2Nyb2xsVG9wfHwKZCYmZC5zY3Jv
bGxUb3B8fDApLShiJiZiLmNsaWVudFRvcHx8ZCYmZC5jbGllbnRUb3B8fDApfWlmKGEud2hpY2g9
PW51bGwmJihhLmNoYXJDb2RlIT1udWxsfHxhLmtleUNvZGUhPW51bGwpKWEud2hpY2g9YS5jaGFy
Q29kZSE9bnVsbD9hLmNoYXJDb2RlOmEua2V5Q29kZTtpZighYS5tZXRhS2V5JiZhLmN0cmxLZXkp
YS5tZXRhS2V5PWEuY3RybEtleTtpZighYS53aGljaCYmYS5idXR0b24hPT1CKWEud2hpY2g9YS5i
dXR0b24mMT8xOmEuYnV0dG9uJjI/MzphLmJ1dHRvbiY0PzI6MDtyZXR1cm4gYX0sZ3VpZDoxRTgs
cHJveHk6Yy5wcm94eSxzcGVjaWFsOntyZWFkeTp7c2V0dXA6Yy5iaW5kUmVhZHksdGVhcmRvd246
Yy5ub29wfSxsaXZlOnthZGQ6ZnVuY3Rpb24oYSl7Yy5ldmVudC5hZGQodGhpcyxZKGEub3JpZ1R5
cGUsYS5zZWxlY3RvciksYy5leHRlbmQoe30sYSx7aGFuZGxlcjpLYSxndWlkOmEuaGFuZGxlci5n
dWlkfSkpfSxyZW1vdmU6ZnVuY3Rpb24oYSl7Yy5ldmVudC5yZW1vdmUodGhpcywKWShhLm9yaWdU
eXBlLGEuc2VsZWN0b3IpLGEpfX0sYmVmb3JldW5sb2FkOntzZXR1cDpmdW5jdGlvbihhLGIsZCl7
aWYoYy5pc1dpbmRvdyh0aGlzKSl0aGlzLm9uYmVmb3JldW5sb2FkPWR9LHRlYXJkb3duOmZ1bmN0
aW9uKGEsYil7aWYodGhpcy5vbmJlZm9yZXVubG9hZD09PWIpdGhpcy5vbmJlZm9yZXVubG9hZD1u
dWxsfX19fTtjLnJlbW92ZUV2ZW50PXQucmVtb3ZlRXZlbnRMaXN0ZW5lcj9mdW5jdGlvbihhLGIs
ZCl7YS5yZW1vdmVFdmVudExpc3RlbmVyJiZhLnJlbW92ZUV2ZW50TGlzdGVuZXIoYixkLGZhbHNl
KX06ZnVuY3Rpb24oYSxiLGQpe2EuZGV0YWNoRXZlbnQmJmEuZGV0YWNoRXZlbnQoIm9uIitiLGQp
fTtjLkV2ZW50PWZ1bmN0aW9uKGEpe2lmKCF0aGlzLnByZXZlbnREZWZhdWx0KXJldHVybiBuZXcg
Yy5FdmVudChhKTtpZihhJiZhLnR5cGUpe3RoaXMub3JpZ2luYWxFdmVudD1hO3RoaXMudHlwZT1h
LnR5cGV9ZWxzZSB0aGlzLnR5cGU9YTt0aGlzLnRpbWVTdGFtcD0KYy5ub3coKTt0aGlzW2MuZXhw
YW5kb109dHJ1ZX07Yy5FdmVudC5wcm90b3R5cGU9e3ByZXZlbnREZWZhdWx0OmZ1bmN0aW9uKCl7
dGhpcy5pc0RlZmF1bHRQcmV2ZW50ZWQ9Y2E7dmFyIGE9dGhpcy5vcmlnaW5hbEV2ZW50O2lmKGEp
aWYoYS5wcmV2ZW50RGVmYXVsdClhLnByZXZlbnREZWZhdWx0KCk7ZWxzZSBhLnJldHVyblZhbHVl
PWZhbHNlfSxzdG9wUHJvcGFnYXRpb246ZnVuY3Rpb24oKXt0aGlzLmlzUHJvcGFnYXRpb25TdG9w
cGVkPWNhO3ZhciBhPXRoaXMub3JpZ2luYWxFdmVudDtpZihhKXthLnN0b3BQcm9wYWdhdGlvbiYm
YS5zdG9wUHJvcGFnYXRpb24oKTthLmNhbmNlbEJ1YmJsZT10cnVlfX0sc3RvcEltbWVkaWF0ZVBy
b3BhZ2F0aW9uOmZ1bmN0aW9uKCl7dGhpcy5pc0ltbWVkaWF0ZVByb3BhZ2F0aW9uU3RvcHBlZD1j
YTt0aGlzLnN0b3BQcm9wYWdhdGlvbigpfSxpc0RlZmF1bHRQcmV2ZW50ZWQ6VSxpc1Byb3BhZ2F0
aW9uU3RvcHBlZDpVLGlzSW1tZWRpYXRlUHJvcGFnYXRpb25TdG9wcGVkOlV9Owp2YXIgdmE9ZnVu
Y3Rpb24oYSl7dmFyIGI9YS5yZWxhdGVkVGFyZ2V0O3RyeXtmb3IoO2ImJmIhPT10aGlzOyliPWIu
cGFyZW50Tm9kZTtpZihiIT09dGhpcyl7YS50eXBlPWEuZGF0YTtjLmV2ZW50LmhhbmRsZS5hcHBs
eSh0aGlzLGFyZ3VtZW50cyl9fWNhdGNoKGQpe319LHdhPWZ1bmN0aW9uKGEpe2EudHlwZT1hLmRh
dGE7Yy5ldmVudC5oYW5kbGUuYXBwbHkodGhpcyxhcmd1bWVudHMpfTtjLmVhY2goe21vdXNlZW50
ZXI6Im1vdXNlb3ZlciIsbW91c2VsZWF2ZToibW91c2VvdXQifSxmdW5jdGlvbihhLGIpe2MuZXZl
bnQuc3BlY2lhbFthXT17c2V0dXA6ZnVuY3Rpb24oZCl7Yy5ldmVudC5hZGQodGhpcyxiLGQmJmQu
c2VsZWN0b3I/d2E6dmEsYSl9LHRlYXJkb3duOmZ1bmN0aW9uKGQpe2MuZXZlbnQucmVtb3ZlKHRo
aXMsYixkJiZkLnNlbGVjdG9yP3dhOnZhKX19fSk7aWYoIWMuc3VwcG9ydC5zdWJtaXRCdWJibGVz
KWMuZXZlbnQuc3BlY2lhbC5zdWJtaXQ9e3NldHVwOmZ1bmN0aW9uKCl7aWYodGhpcy5ub2RlTmFt
ZS50b0xvd2VyQ2FzZSgpIT09CiJmb3JtIil7Yy5ldmVudC5hZGQodGhpcywiY2xpY2suc3BlY2lh
bFN1Ym1pdCIsZnVuY3Rpb24oYSl7dmFyIGI9YS50YXJnZXQsZD1iLnR5cGU7aWYoKGQ9PT0ic3Vi
bWl0Inx8ZD09PSJpbWFnZSIpJiZjKGIpLmNsb3Nlc3QoImZvcm0iKS5sZW5ndGgpe2EubGl2ZUZp
cmVkPUI7cmV0dXJuIGxhKCJzdWJtaXQiLHRoaXMsYXJndW1lbnRzKX19KTtjLmV2ZW50LmFkZCh0
aGlzLCJrZXlwcmVzcy5zcGVjaWFsU3VibWl0IixmdW5jdGlvbihhKXt2YXIgYj1hLnRhcmdldCxk
PWIudHlwZTtpZigoZD09PSJ0ZXh0Inx8ZD09PSJwYXNzd29yZCIpJiZjKGIpLmNsb3Nlc3QoImZv
cm0iKS5sZW5ndGgmJmEua2V5Q29kZT09PTEzKXthLmxpdmVGaXJlZD1CO3JldHVybiBsYSgic3Vi
bWl0Iix0aGlzLGFyZ3VtZW50cyl9fSl9ZWxzZSByZXR1cm4gZmFsc2V9LHRlYXJkb3duOmZ1bmN0
aW9uKCl7Yy5ldmVudC5yZW1vdmUodGhpcywiLnNwZWNpYWxTdWJtaXQiKX19O2lmKCFjLnN1cHBv
cnQuY2hhbmdlQnViYmxlcyl7dmFyIFYsCnhhPWZ1bmN0aW9uKGEpe3ZhciBiPWEudHlwZSxkPWEu
dmFsdWU7aWYoYj09PSJyYWRpbyJ8fGI9PT0iY2hlY2tib3giKWQ9YS5jaGVja2VkO2Vsc2UgaWYo
Yj09PSJzZWxlY3QtbXVsdGlwbGUiKWQ9YS5zZWxlY3RlZEluZGV4Pi0xP2MubWFwKGEub3B0aW9u
cyxmdW5jdGlvbihlKXtyZXR1cm4gZS5zZWxlY3RlZH0pLmpvaW4oIi0iKToiIjtlbHNlIGlmKGEu
bm9kZU5hbWUudG9Mb3dlckNhc2UoKT09PSJzZWxlY3QiKWQ9YS5zZWxlY3RlZEluZGV4O3JldHVy
biBkfSxaPWZ1bmN0aW9uKGEsYil7dmFyIGQ9YS50YXJnZXQsZSxmO2lmKCEoIWlhLnRlc3QoZC5u
b2RlTmFtZSl8fGQucmVhZE9ubHkpKXtlPWMuZGF0YShkLCJfY2hhbmdlX2RhdGEiKTtmPXhhKGQp
O2lmKGEudHlwZSE9PSJmb2N1c291dCJ8fGQudHlwZSE9PSJyYWRpbyIpYy5kYXRhKGQsIl9jaGFu
Z2VfZGF0YSIsZik7aWYoIShlPT09Qnx8Zj09PWUpKWlmKGUhPW51bGx8fGYpe2EudHlwZT0iY2hh
bmdlIjthLmxpdmVGaXJlZD0KQjtyZXR1cm4gYy5ldmVudC50cmlnZ2VyKGEsYixkKX19fTtjLmV2
ZW50LnNwZWNpYWwuY2hhbmdlPXtmaWx0ZXJzOntmb2N1c291dDpaLGJlZm9yZWRlYWN0aXZhdGU6
WixjbGljazpmdW5jdGlvbihhKXt2YXIgYj1hLnRhcmdldCxkPWIudHlwZTtpZihkPT09InJhZGlv
Inx8ZD09PSJjaGVja2JveCJ8fGIubm9kZU5hbWUudG9Mb3dlckNhc2UoKT09PSJzZWxlY3QiKXJl
dHVybiBaLmNhbGwodGhpcyxhKX0sa2V5ZG93bjpmdW5jdGlvbihhKXt2YXIgYj1hLnRhcmdldCxk
PWIudHlwZTtpZihhLmtleUNvZGU9PT0xMyYmYi5ub2RlTmFtZS50b0xvd2VyQ2FzZSgpIT09InRl
eHRhcmVhInx8YS5rZXlDb2RlPT09MzImJihkPT09ImNoZWNrYm94Inx8ZD09PSJyYWRpbyIpfHxk
PT09InNlbGVjdC1tdWx0aXBsZSIpcmV0dXJuIFouY2FsbCh0aGlzLGEpfSxiZWZvcmVhY3RpdmF0
ZTpmdW5jdGlvbihhKXthPWEudGFyZ2V0O2MuZGF0YShhLCJfY2hhbmdlX2RhdGEiLHhhKGEpKX19
LHNldHVwOmZ1bmN0aW9uKCl7aWYodGhpcy50eXBlPT09CiJmaWxlIilyZXR1cm4gZmFsc2U7Zm9y
KHZhciBhIGluIFYpYy5ldmVudC5hZGQodGhpcyxhKyIuc3BlY2lhbENoYW5nZSIsVlthXSk7cmV0
dXJuIGlhLnRlc3QodGhpcy5ub2RlTmFtZSl9LHRlYXJkb3duOmZ1bmN0aW9uKCl7Yy5ldmVudC5y
ZW1vdmUodGhpcywiLnNwZWNpYWxDaGFuZ2UiKTtyZXR1cm4gaWEudGVzdCh0aGlzLm5vZGVOYW1l
KX19O1Y9Yy5ldmVudC5zcGVjaWFsLmNoYW5nZS5maWx0ZXJzO1YuZm9jdXM9Vi5iZWZvcmVhY3Rp
dmF0ZX10LmFkZEV2ZW50TGlzdGVuZXImJmMuZWFjaCh7Zm9jdXM6ImZvY3VzaW4iLGJsdXI6ImZv
Y3Vzb3V0In0sZnVuY3Rpb24oYSxiKXtmdW5jdGlvbiBkKGUpe2U9Yy5ldmVudC5maXgoZSk7ZS50
eXBlPWI7cmV0dXJuIGMuZXZlbnQudHJpZ2dlcihlLG51bGwsZS50YXJnZXQpfWMuZXZlbnQuc3Bl
Y2lhbFtiXT17c2V0dXA6ZnVuY3Rpb24oKXt1YVtiXSsrPT09MCYmdC5hZGRFdmVudExpc3RlbmVy
KGEsZCx0cnVlKX0sdGVhcmRvd246ZnVuY3Rpb24oKXstLXVhW2JdPT09CjAmJnQucmVtb3ZlRXZl
bnRMaXN0ZW5lcihhLGQsdHJ1ZSl9fX0pO2MuZWFjaChbImJpbmQiLCJvbmUiXSxmdW5jdGlvbihh
LGIpe2MuZm5bYl09ZnVuY3Rpb24oZCxlLGYpe2lmKHR5cGVvZiBkPT09Im9iamVjdCIpe2Zvcih2
YXIgaCBpbiBkKXRoaXNbYl0oaCxlLGRbaF0sZik7cmV0dXJuIHRoaXN9aWYoYy5pc0Z1bmN0aW9u
KGUpfHxlPT09ZmFsc2Upe2Y9ZTtlPUJ9dmFyIGw9Yj09PSJvbmUiP2MucHJveHkoZixmdW5jdGlv
bihvKXtjKHRoaXMpLnVuYmluZChvLGwpO3JldHVybiBmLmFwcGx5KHRoaXMsYXJndW1lbnRzKX0p
OmY7aWYoZD09PSJ1bmxvYWQiJiZiIT09Im9uZSIpdGhpcy5vbmUoZCxlLGYpO2Vsc2V7aD0wO2Zv
cih2YXIgaz10aGlzLmxlbmd0aDtoPGs7aCsrKWMuZXZlbnQuYWRkKHRoaXNbaF0sZCxsLGUpfXJl
dHVybiB0aGlzfX0pO2MuZm4uZXh0ZW5kKHt1bmJpbmQ6ZnVuY3Rpb24oYSxiKXtpZih0eXBlb2Yg
YT09PSJvYmplY3QiJiYhYS5wcmV2ZW50RGVmYXVsdClmb3IodmFyIGQgaW4gYSl0aGlzLnVuYmlu
ZChkLAphW2RdKTtlbHNle2Q9MDtmb3IodmFyIGU9dGhpcy5sZW5ndGg7ZDxlO2QrKyljLmV2ZW50
LnJlbW92ZSh0aGlzW2RdLGEsYil9cmV0dXJuIHRoaXN9LGRlbGVnYXRlOmZ1bmN0aW9uKGEsYixk
LGUpe3JldHVybiB0aGlzLmxpdmUoYixkLGUsYSl9LHVuZGVsZWdhdGU6ZnVuY3Rpb24oYSxiLGQp
e3JldHVybiBhcmd1bWVudHMubGVuZ3RoPT09MD90aGlzLnVuYmluZCgibGl2ZSIpOnRoaXMuZGll
KGIsbnVsbCxkLGEpfSx0cmlnZ2VyOmZ1bmN0aW9uKGEsYil7cmV0dXJuIHRoaXMuZWFjaChmdW5j
dGlvbigpe2MuZXZlbnQudHJpZ2dlcihhLGIsdGhpcyl9KX0sdHJpZ2dlckhhbmRsZXI6ZnVuY3Rp
b24oYSxiKXtpZih0aGlzWzBdKXt2YXIgZD1jLkV2ZW50KGEpO2QucHJldmVudERlZmF1bHQoKTtk
LnN0b3BQcm9wYWdhdGlvbigpO2MuZXZlbnQudHJpZ2dlcihkLGIsdGhpc1swXSk7cmV0dXJuIGQu
cmVzdWx0fX0sdG9nZ2xlOmZ1bmN0aW9uKGEpe2Zvcih2YXIgYj1hcmd1bWVudHMsZD0KMTtkPGIu
bGVuZ3RoOyljLnByb3h5KGEsYltkKytdKTtyZXR1cm4gdGhpcy5jbGljayhjLnByb3h5KGEsZnVu
Y3Rpb24oZSl7dmFyIGY9KGMuZGF0YSh0aGlzLCJsYXN0VG9nZ2xlIithLmd1aWQpfHwwKSVkO2Mu
ZGF0YSh0aGlzLCJsYXN0VG9nZ2xlIithLmd1aWQsZisxKTtlLnByZXZlbnREZWZhdWx0KCk7cmV0
dXJuIGJbZl0uYXBwbHkodGhpcyxhcmd1bWVudHMpfHxmYWxzZX0pKX0saG92ZXI6ZnVuY3Rpb24o
YSxiKXtyZXR1cm4gdGhpcy5tb3VzZWVudGVyKGEpLm1vdXNlbGVhdmUoYnx8YSl9fSk7dmFyIHlh
PXtmb2N1czoiZm9jdXNpbiIsYmx1cjoiZm9jdXNvdXQiLG1vdXNlZW50ZXI6Im1vdXNlb3ZlciIs
bW91c2VsZWF2ZToibW91c2VvdXQifTtjLmVhY2goWyJsaXZlIiwiZGllIl0sZnVuY3Rpb24oYSxi
KXtjLmZuW2JdPWZ1bmN0aW9uKGQsZSxmLGgpe3ZhciBsLGs9MCxvLHgscj1ofHx0aGlzLnNlbGVj
dG9yO2g9aD90aGlzOmModGhpcy5jb250ZXh0KTtpZih0eXBlb2YgZD09PQoib2JqZWN0IiYmIWQu
cHJldmVudERlZmF1bHQpe2ZvcihsIGluIGQpaFtiXShsLGUsZFtsXSxyKTtyZXR1cm4gdGhpc31p
ZihjLmlzRnVuY3Rpb24oZSkpe2Y9ZTtlPUJ9Zm9yKGQ9KGR8fCIiKS5zcGxpdCgiICIpOyhsPWRb
aysrXSkhPW51bGw7KXtvPVguZXhlYyhsKTt4PSIiO2lmKG8pe3g9b1swXTtsPWwucmVwbGFjZShY
LCIiKX1pZihsPT09ImhvdmVyIilkLnB1c2goIm1vdXNlZW50ZXIiK3gsIm1vdXNlbGVhdmUiK3gp
O2Vsc2V7bz1sO2lmKGw9PT0iZm9jdXMifHxsPT09ImJsdXIiKXtkLnB1c2goeWFbbF0reCk7bCs9
eH1lbHNlIGw9KHlhW2xdfHxsKSt4O2lmKGI9PT0ibGl2ZSIpe3g9MDtmb3IodmFyIEE9aC5sZW5n
dGg7eDxBO3grKyljLmV2ZW50LmFkZChoW3hdLCJsaXZlLiIrWShsLHIpLHtkYXRhOmUsc2VsZWN0
b3I6cixoYW5kbGVyOmYsb3JpZ1R5cGU6bCxvcmlnSGFuZGxlcjpmLHByZVR5cGU6b30pfWVsc2Ug
aC51bmJpbmQoImxpdmUuIitZKGwsciksZil9fXJldHVybiB0aGlzfX0pOwpjLmVhY2goImJsdXIg
Zm9jdXMgZm9jdXNpbiBmb2N1c291dCBsb2FkIHJlc2l6ZSBzY3JvbGwgdW5sb2FkIGNsaWNrIGRi
bGNsaWNrIG1vdXNlZG93biBtb3VzZXVwIG1vdXNlbW92ZSBtb3VzZW92ZXIgbW91c2VvdXQgbW91
c2VlbnRlciBtb3VzZWxlYXZlIGNoYW5nZSBzZWxlY3Qgc3VibWl0IGtleWRvd24ga2V5cHJlc3Mg
a2V5dXAgZXJyb3IiLnNwbGl0KCIgIiksZnVuY3Rpb24oYSxiKXtjLmZuW2JdPWZ1bmN0aW9uKGQs
ZSl7aWYoZT09bnVsbCl7ZT1kO2Q9bnVsbH1yZXR1cm4gYXJndW1lbnRzLmxlbmd0aD4wP3RoaXMu
YmluZChiLGQsZSk6dGhpcy50cmlnZ2VyKGIpfTtpZihjLmF0dHJGbiljLmF0dHJGbltiXT10cnVl
fSk7RS5hdHRhY2hFdmVudCYmIUUuYWRkRXZlbnRMaXN0ZW5lciYmYyhFKS5iaW5kKCJ1bmxvYWQi
LGZ1bmN0aW9uKCl7Zm9yKHZhciBhIGluIGMuY2FjaGUpaWYoYy5jYWNoZVthXS5oYW5kbGUpdHJ5
e2MuZXZlbnQucmVtb3ZlKGMuY2FjaGVbYV0uaGFuZGxlLmVsZW0pfWNhdGNoKGIpe319KTsKKGZ1
bmN0aW9uKCl7ZnVuY3Rpb24gYShnLGksbixtLHAscSl7cD0wO2Zvcih2YXIgdT1tLmxlbmd0aDtw
PHU7cCsrKXt2YXIgeT1tW3BdO2lmKHkpe3ZhciBGPWZhbHNlO2Zvcih5PXlbZ107eTspe2lmKHku
c2l6Y2FjaGU9PT1uKXtGPW1beS5zaXpzZXRdO2JyZWFrfWlmKHkubm9kZVR5cGU9PT0xJiYhcSl7
eS5zaXpjYWNoZT1uO3kuc2l6c2V0PXB9aWYoeS5ub2RlTmFtZS50b0xvd2VyQ2FzZSgpPT09aSl7
Rj15O2JyZWFrfXk9eVtnXX1tW3BdPUZ9fX1mdW5jdGlvbiBiKGcsaSxuLG0scCxxKXtwPTA7Zm9y
KHZhciB1PW0ubGVuZ3RoO3A8dTtwKyspe3ZhciB5PW1bcF07aWYoeSl7dmFyIEY9ZmFsc2U7Zm9y
KHk9eVtnXTt5Oyl7aWYoeS5zaXpjYWNoZT09PW4pe0Y9bVt5LnNpenNldF07YnJlYWt9aWYoeS5u
b2RlVHlwZT09PTEpe2lmKCFxKXt5LnNpemNhY2hlPW47eS5zaXpzZXQ9cH1pZih0eXBlb2YgaSE9
PSJzdHJpbmciKXtpZih5PT09aSl7Rj10cnVlO2JyZWFrfX1lbHNlIGlmKGsuZmlsdGVyKGksClt5
XSkubGVuZ3RoPjApe0Y9eTticmVha319eT15W2ddfW1bcF09Rn19fXZhciBkPS8oKD86XCgoPzpc
KFteKCldK1wpfFteKCldKykrXCl8XFsoPzpcW1teXFtcXV0qXF18WyciXVteJyJdKlsnIl18W15c
W1xdJyJdKykrXF18XFwufFteID4rfiwoXFtcXF0rKSt8Wz4rfl0pKFxzKixccyopPygoPzoufFxy
fFxuKSopL2csZT0wLGY9T2JqZWN0LnByb3RvdHlwZS50b1N0cmluZyxoPWZhbHNlLGw9dHJ1ZTtb
MCwwXS5zb3J0KGZ1bmN0aW9uKCl7bD1mYWxzZTtyZXR1cm4gMH0pO3ZhciBrPWZ1bmN0aW9uKGcs
aSxuLG0pe249bnx8W107dmFyIHA9aT1pfHx0O2lmKGkubm9kZVR5cGUhPT0xJiZpLm5vZGVUeXBl
IT09OSlyZXR1cm5bXTtpZighZ3x8dHlwZW9mIGchPT0ic3RyaW5nIilyZXR1cm4gbjt2YXIgcSx1
LHksRixNLE49dHJ1ZSxPPWsuaXNYTUwoaSksRD1bXSxSPWc7ZG97ZC5leGVjKCIiKTtpZihxPWQu
ZXhlYyhSKSl7Uj1xWzNdO0QucHVzaChxWzFdKTtpZihxWzJdKXtGPXFbM107CmJyZWFrfX19d2hp
bGUocSk7aWYoRC5sZW5ndGg+MSYmeC5leGVjKGcpKWlmKEQubGVuZ3RoPT09MiYmby5yZWxhdGl2
ZVtEWzBdXSl1PUwoRFswXStEWzFdLGkpO2Vsc2UgZm9yKHU9by5yZWxhdGl2ZVtEWzBdXT9baV06
ayhELnNoaWZ0KCksaSk7RC5sZW5ndGg7KXtnPUQuc2hpZnQoKTtpZihvLnJlbGF0aXZlW2ddKWcr
PUQuc2hpZnQoKTt1PUwoZyx1KX1lbHNle2lmKCFtJiZELmxlbmd0aD4xJiZpLm5vZGVUeXBlPT09
OSYmIU8mJm8ubWF0Y2guSUQudGVzdChEWzBdKSYmIW8ubWF0Y2guSUQudGVzdChEW0QubGVuZ3Ro
LTFdKSl7cT1rLmZpbmQoRC5zaGlmdCgpLGksTyk7aT1xLmV4cHI/ay5maWx0ZXIocS5leHByLHEu
c2V0KVswXTpxLnNldFswXX1pZihpKXtxPW0/e2V4cHI6RC5wb3AoKSxzZXQ6QyhtKX06ay5maW5k
KEQucG9wKCksRC5sZW5ndGg9PT0xJiYoRFswXT09PSJ+Inx8RFswXT09PSIrIikmJmkucGFyZW50
Tm9kZT9pLnBhcmVudE5vZGU6aSxPKTt1PXEuZXhwcj9rLmZpbHRlcihxLmV4cHIsCnEuc2V0KTpx
LnNldDtpZihELmxlbmd0aD4wKXk9Qyh1KTtlbHNlIE49ZmFsc2U7Zm9yKDtELmxlbmd0aDspe3E9
TT1ELnBvcCgpO2lmKG8ucmVsYXRpdmVbTV0pcT1ELnBvcCgpO2Vsc2UgTT0iIjtpZihxPT1udWxs
KXE9aTtvLnJlbGF0aXZlW01dKHkscSxPKX19ZWxzZSB5PVtdfXl8fCh5PXUpO3l8fGsuZXJyb3Io
TXx8Zyk7aWYoZi5jYWxsKHkpPT09IltvYmplY3QgQXJyYXldIilpZihOKWlmKGkmJmkubm9kZVR5
cGU9PT0xKWZvcihnPTA7eVtnXSE9bnVsbDtnKyspe2lmKHlbZ10mJih5W2ddPT09dHJ1ZXx8eVtn
XS5ub2RlVHlwZT09PTEmJmsuY29udGFpbnMoaSx5W2ddKSkpbi5wdXNoKHVbZ10pfWVsc2UgZm9y
KGc9MDt5W2ddIT1udWxsO2crKyl5W2ddJiZ5W2ddLm5vZGVUeXBlPT09MSYmbi5wdXNoKHVbZ10p
O2Vsc2Ugbi5wdXNoLmFwcGx5KG4seSk7ZWxzZSBDKHksbik7aWYoRil7ayhGLHAsbixtKTtrLnVu
aXF1ZVNvcnQobil9cmV0dXJuIG59O2sudW5pcXVlU29ydD1mdW5jdGlvbihnKXtpZih3KXtoPQps
O2cuc29ydCh3KTtpZihoKWZvcih2YXIgaT0xO2k8Zy5sZW5ndGg7aSsrKWdbaV09PT1nW2ktMV0m
Jmcuc3BsaWNlKGktLSwxKX1yZXR1cm4gZ307ay5tYXRjaGVzPWZ1bmN0aW9uKGcsaSl7cmV0dXJu
IGsoZyxudWxsLG51bGwsaSl9O2subWF0Y2hlc1NlbGVjdG9yPWZ1bmN0aW9uKGcsaSl7cmV0dXJu
IGsoaSxudWxsLG51bGwsW2ddKS5sZW5ndGg+MH07ay5maW5kPWZ1bmN0aW9uKGcsaSxuKXt2YXIg
bTtpZighZylyZXR1cm5bXTtmb3IodmFyIHA9MCxxPW8ub3JkZXIubGVuZ3RoO3A8cTtwKyspe3Zh
ciB1LHk9by5vcmRlcltwXTtpZih1PW8ubGVmdE1hdGNoW3ldLmV4ZWMoZykpe3ZhciBGPXVbMV07
dS5zcGxpY2UoMSwxKTtpZihGLnN1YnN0cihGLmxlbmd0aC0xKSE9PSJcXCIpe3VbMV09KHVbMV18
fCIiKS5yZXBsYWNlKC9cXC9nLCIiKTttPW8uZmluZFt5XSh1LGksbik7aWYobSE9bnVsbCl7Zz1n
LnJlcGxhY2Uoby5tYXRjaFt5XSwiIik7YnJlYWt9fX19bXx8KG09aS5nZXRFbGVtZW50c0J5VGFn
TmFtZSgiKiIpKTsKcmV0dXJue3NldDptLGV4cHI6Z319O2suZmlsdGVyPWZ1bmN0aW9uKGcsaSxu
LG0pe2Zvcih2YXIgcCxxLHU9Zyx5PVtdLEY9aSxNPWkmJmlbMF0mJmsuaXNYTUwoaVswXSk7ZyYm
aS5sZW5ndGg7KXtmb3IodmFyIE4gaW4gby5maWx0ZXIpaWYoKHA9by5sZWZ0TWF0Y2hbTl0uZXhl
YyhnKSkhPW51bGwmJnBbMl0pe3ZhciBPLEQsUj1vLmZpbHRlcltOXTtEPXBbMV07cT1mYWxzZTtw
LnNwbGljZSgxLDEpO2lmKEQuc3Vic3RyKEQubGVuZ3RoLTEpIT09IlxcIil7aWYoRj09PXkpeT1b
XTtpZihvLnByZUZpbHRlcltOXSlpZihwPW8ucHJlRmlsdGVyW05dKHAsRixuLHksbSxNKSl7aWYo
cD09PXRydWUpY29udGludWV9ZWxzZSBxPU89dHJ1ZTtpZihwKWZvcih2YXIgaj0wOyhEPUZbal0p
IT1udWxsO2orKylpZihEKXtPPVIoRCxwLGosRik7dmFyIHM9bV4hIU87aWYobiYmTyE9bnVsbClp
ZihzKXE9dHJ1ZTtlbHNlIEZbal09ZmFsc2U7ZWxzZSBpZihzKXt5LnB1c2goRCk7cT10cnVlfX1p
ZihPIT09CkIpe258fChGPXkpO2c9Zy5yZXBsYWNlKG8ubWF0Y2hbTl0sIiIpO2lmKCFxKXJldHVy
bltdO2JyZWFrfX19aWYoZz09PXUpaWYocT09bnVsbClrLmVycm9yKGcpO2Vsc2UgYnJlYWs7dT1n
fXJldHVybiBGfTtrLmVycm9yPWZ1bmN0aW9uKGcpe3Rocm93IlN5bnRheCBlcnJvciwgdW5yZWNv
Z25pemVkIGV4cHJlc3Npb246ICIrZzt9O3ZhciBvPWsuc2VsZWN0b3JzPXtvcmRlcjpbIklEIiwi
TkFNRSIsIlRBRyJdLG1hdGNoOntJRDovIygoPzpbXHdcdTAwYzAtXHVGRkZGXC1dfFxcLikrKS8s
Q0xBU1M6L1wuKCg/Oltcd1x1MDBjMC1cdUZGRkZcLV18XFwuKSspLyxOQU1FOi9cW25hbWU9Wyci
XSooKD86W1x3XHUwMGMwLVx1RkZGRlwtXXxcXC4pKylbJyJdKlxdLyxBVFRSOi9cW1xzKigoPzpb
XHdcdTAwYzAtXHVGRkZGXC1dfFxcLikrKVxzKig/OihcUz89KVxzKihbJyJdKikoLio/KVwzfClc
cypcXS8sVEFHOi9eKCg/Oltcd1x1MDBjMC1cdUZGRkZcKlwtXXxcXC4pKykvLENISUxEOi86KG9u
bHl8bnRofGxhc3R8Zmlyc3QpLWNoaWxkKD86XCgoZXZlbnxvZGR8W1xkbitcLV0qKVwpKT8vLApQ
T1M6LzoobnRofGVxfGd0fGx0fGZpcnN0fGxhc3R8ZXZlbnxvZGQpKD86XCgoXGQqKVwpKT8oPz1b
XlwtXXwkKS8sUFNFVURPOi86KCg/Oltcd1x1MDBjMC1cdUZGRkZcLV18XFwuKSspKD86XCgoWyci
XT8pKCg/OlwoW15cKV0rXCl8W15cKFwpXSopKylcMlwpKT8vfSxsZWZ0TWF0Y2g6e30sYXR0ck1h
cDp7ImNsYXNzIjoiY2xhc3NOYW1lIiwiZm9yIjoiaHRtbEZvciJ9LGF0dHJIYW5kbGU6e2hyZWY6
ZnVuY3Rpb24oZyl7cmV0dXJuIGcuZ2V0QXR0cmlidXRlKCJocmVmIil9fSxyZWxhdGl2ZTp7Iisi
OmZ1bmN0aW9uKGcsaSl7dmFyIG49dHlwZW9mIGk9PT0ic3RyaW5nIixtPW4mJiEvXFcvLnRlc3Qo
aSk7bj1uJiYhbTtpZihtKWk9aS50b0xvd2VyQ2FzZSgpO209MDtmb3IodmFyIHA9Zy5sZW5ndGgs
cTttPHA7bSsrKWlmKHE9Z1ttXSl7Zm9yKDsocT1xLnByZXZpb3VzU2libGluZykmJnEubm9kZVR5
cGUhPT0xOyk7Z1ttXT1ufHxxJiZxLm5vZGVOYW1lLnRvTG93ZXJDYXNlKCk9PT0KaT9xfHxmYWxz
ZTpxPT09aX1uJiZrLmZpbHRlcihpLGcsdHJ1ZSl9LCI+IjpmdW5jdGlvbihnLGkpe3ZhciBuLG09
dHlwZW9mIGk9PT0ic3RyaW5nIixwPTAscT1nLmxlbmd0aDtpZihtJiYhL1xXLy50ZXN0KGkpKWZv
cihpPWkudG9Mb3dlckNhc2UoKTtwPHE7cCsrKXtpZihuPWdbcF0pe249bi5wYXJlbnROb2RlO2db
cF09bi5ub2RlTmFtZS50b0xvd2VyQ2FzZSgpPT09aT9uOmZhbHNlfX1lbHNle2Zvcig7cDxxO3Ar
KylpZihuPWdbcF0pZ1twXT1tP24ucGFyZW50Tm9kZTpuLnBhcmVudE5vZGU9PT1pO20mJmsuZmls
dGVyKGksZyx0cnVlKX19LCIiOmZ1bmN0aW9uKGcsaSxuKXt2YXIgbSxwPWUrKyxxPWI7aWYodHlw
ZW9mIGk9PT0ic3RyaW5nIiYmIS9cVy8udGVzdChpKSl7bT1pPWkudG9Mb3dlckNhc2UoKTtxPWF9
cSgicGFyZW50Tm9kZSIsaSxwLGcsbSxuKX0sIn4iOmZ1bmN0aW9uKGcsaSxuKXt2YXIgbSxwPWUr
KyxxPWI7aWYodHlwZW9mIGk9PT0ic3RyaW5nIiYmIS9cVy8udGVzdChpKSl7bT0KaT1pLnRvTG93
ZXJDYXNlKCk7cT1hfXEoInByZXZpb3VzU2libGluZyIsaSxwLGcsbSxuKX19LGZpbmQ6e0lEOmZ1
bmN0aW9uKGcsaSxuKXtpZih0eXBlb2YgaS5nZXRFbGVtZW50QnlJZCE9PSJ1bmRlZmluZWQiJiYh
bilyZXR1cm4oZz1pLmdldEVsZW1lbnRCeUlkKGdbMV0pKSYmZy5wYXJlbnROb2RlP1tnXTpbXX0s
TkFNRTpmdW5jdGlvbihnLGkpe2lmKHR5cGVvZiBpLmdldEVsZW1lbnRzQnlOYW1lIT09InVuZGVm
aW5lZCIpe2Zvcih2YXIgbj1bXSxtPWkuZ2V0RWxlbWVudHNCeU5hbWUoZ1sxXSkscD0wLHE9bS5s
ZW5ndGg7cDxxO3ArKyltW3BdLmdldEF0dHJpYnV0ZSgibmFtZSIpPT09Z1sxXSYmbi5wdXNoKG1b
cF0pO3JldHVybiBuLmxlbmd0aD09PTA/bnVsbDpufX0sVEFHOmZ1bmN0aW9uKGcsaSl7cmV0dXJu
IGkuZ2V0RWxlbWVudHNCeVRhZ05hbWUoZ1sxXSl9fSxwcmVGaWx0ZXI6e0NMQVNTOmZ1bmN0aW9u
KGcsaSxuLG0scCxxKXtnPSIgIitnWzFdLnJlcGxhY2UoL1xcL2csCiIiKSsiICI7aWYocSlyZXR1
cm4gZztxPTA7Zm9yKHZhciB1Oyh1PWlbcV0pIT1udWxsO3ErKylpZih1KWlmKHBeKHUuY2xhc3NO
YW1lJiYoIiAiK3UuY2xhc3NOYW1lKyIgIikucmVwbGFjZSgvW1x0XG5dL2csIiAiKS5pbmRleE9m
KGcpPj0wKSlufHxtLnB1c2godSk7ZWxzZSBpZihuKWlbcV09ZmFsc2U7cmV0dXJuIGZhbHNlfSxJ
RDpmdW5jdGlvbihnKXtyZXR1cm4gZ1sxXS5yZXBsYWNlKC9cXC9nLCIiKX0sVEFHOmZ1bmN0aW9u
KGcpe3JldHVybiBnWzFdLnRvTG93ZXJDYXNlKCl9LENISUxEOmZ1bmN0aW9uKGcpe2lmKGdbMV09
PT0ibnRoIil7dmFyIGk9LygtPykoXGQqKW4oKD86XCt8LSk/XGQqKS8uZXhlYyhnWzJdPT09ImV2
ZW4iJiYiMm4ifHxnWzJdPT09Im9kZCImJiIybisxInx8IS9cRC8udGVzdChnWzJdKSYmIjBuKyIr
Z1syXXx8Z1syXSk7Z1syXT1pWzFdKyhpWzJdfHwxKS0wO2dbM109aVszXS0wfWdbMF09ZSsrO3Jl
dHVybiBnfSxBVFRSOmZ1bmN0aW9uKGcsaSxuLAptLHAscSl7aT1nWzFdLnJlcGxhY2UoL1xcL2cs
IiIpO2lmKCFxJiZvLmF0dHJNYXBbaV0pZ1sxXT1vLmF0dHJNYXBbaV07aWYoZ1syXT09PSJ+PSIp
Z1s0XT0iICIrZ1s0XSsiICI7cmV0dXJuIGd9LFBTRVVETzpmdW5jdGlvbihnLGksbixtLHApe2lm
KGdbMV09PT0ibm90IilpZigoZC5leGVjKGdbM10pfHwiIikubGVuZ3RoPjF8fC9eXHcvLnRlc3Qo
Z1szXSkpZ1szXT1rKGdbM10sbnVsbCxudWxsLGkpO2Vsc2V7Zz1rLmZpbHRlcihnWzNdLGksbix0
cnVlXnApO258fG0ucHVzaC5hcHBseShtLGcpO3JldHVybiBmYWxzZX1lbHNlIGlmKG8ubWF0Y2gu
UE9TLnRlc3QoZ1swXSl8fG8ubWF0Y2guQ0hJTEQudGVzdChnWzBdKSlyZXR1cm4gdHJ1ZTtyZXR1
cm4gZ30sUE9TOmZ1bmN0aW9uKGcpe2cudW5zaGlmdCh0cnVlKTtyZXR1cm4gZ319LGZpbHRlcnM6
e2VuYWJsZWQ6ZnVuY3Rpb24oZyl7cmV0dXJuIGcuZGlzYWJsZWQ9PT1mYWxzZSYmZy50eXBlIT09
ImhpZGRlbiJ9LGRpc2FibGVkOmZ1bmN0aW9uKGcpe3JldHVybiBnLmRpc2FibGVkPT09CnRydWV9
LGNoZWNrZWQ6ZnVuY3Rpb24oZyl7cmV0dXJuIGcuY2hlY2tlZD09PXRydWV9LHNlbGVjdGVkOmZ1
bmN0aW9uKGcpe3JldHVybiBnLnNlbGVjdGVkPT09dHJ1ZX0scGFyZW50OmZ1bmN0aW9uKGcpe3Jl
dHVybiEhZy5maXJzdENoaWxkfSxlbXB0eTpmdW5jdGlvbihnKXtyZXR1cm4hZy5maXJzdENoaWxk
fSxoYXM6ZnVuY3Rpb24oZyxpLG4pe3JldHVybiEhayhuWzNdLGcpLmxlbmd0aH0saGVhZGVyOmZ1
bmN0aW9uKGcpe3JldHVybi9oXGQvaS50ZXN0KGcubm9kZU5hbWUpfSx0ZXh0OmZ1bmN0aW9uKGcp
e3JldHVybiJ0ZXh0Ij09PWcudHlwZX0scmFkaW86ZnVuY3Rpb24oZyl7cmV0dXJuInJhZGlvIj09
PWcudHlwZX0sY2hlY2tib3g6ZnVuY3Rpb24oZyl7cmV0dXJuImNoZWNrYm94Ij09PWcudHlwZX0s
ZmlsZTpmdW5jdGlvbihnKXtyZXR1cm4iZmlsZSI9PT1nLnR5cGV9LHBhc3N3b3JkOmZ1bmN0aW9u
KGcpe3JldHVybiJwYXNzd29yZCI9PT1nLnR5cGV9LHN1Ym1pdDpmdW5jdGlvbihnKXtyZXR1cm4i
c3VibWl0Ij09PQpnLnR5cGV9LGltYWdlOmZ1bmN0aW9uKGcpe3JldHVybiJpbWFnZSI9PT1nLnR5
cGV9LHJlc2V0OmZ1bmN0aW9uKGcpe3JldHVybiJyZXNldCI9PT1nLnR5cGV9LGJ1dHRvbjpmdW5j
dGlvbihnKXtyZXR1cm4iYnV0dG9uIj09PWcudHlwZXx8Zy5ub2RlTmFtZS50b0xvd2VyQ2FzZSgp
PT09ImJ1dHRvbiJ9LGlucHV0OmZ1bmN0aW9uKGcpe3JldHVybi9pbnB1dHxzZWxlY3R8dGV4dGFy
ZWF8YnV0dG9uL2kudGVzdChnLm5vZGVOYW1lKX19LHNldEZpbHRlcnM6e2ZpcnN0OmZ1bmN0aW9u
KGcsaSl7cmV0dXJuIGk9PT0wfSxsYXN0OmZ1bmN0aW9uKGcsaSxuLG0pe3JldHVybiBpPT09bS5s
ZW5ndGgtMX0sZXZlbjpmdW5jdGlvbihnLGkpe3JldHVybiBpJTI9PT0wfSxvZGQ6ZnVuY3Rpb24o
ZyxpKXtyZXR1cm4gaSUyPT09MX0sbHQ6ZnVuY3Rpb24oZyxpLG4pe3JldHVybiBpPG5bM10tMH0s
Z3Q6ZnVuY3Rpb24oZyxpLG4pe3JldHVybiBpPm5bM10tMH0sbnRoOmZ1bmN0aW9uKGcsaSxuKXty
ZXR1cm4gblszXS0KMD09PWl9LGVxOmZ1bmN0aW9uKGcsaSxuKXtyZXR1cm4gblszXS0wPT09aX19
LGZpbHRlcjp7UFNFVURPOmZ1bmN0aW9uKGcsaSxuLG0pe3ZhciBwPWlbMV0scT1vLmZpbHRlcnNb
cF07aWYocSlyZXR1cm4gcShnLG4saSxtKTtlbHNlIGlmKHA9PT0iY29udGFpbnMiKXJldHVybihn
LnRleHRDb250ZW50fHxnLmlubmVyVGV4dHx8ay5nZXRUZXh0KFtnXSl8fCIiKS5pbmRleE9mKGlb
M10pPj0wO2Vsc2UgaWYocD09PSJub3QiKXtpPWlbM107bj0wO2ZvcihtPWkubGVuZ3RoO248bTtu
KyspaWYoaVtuXT09PWcpcmV0dXJuIGZhbHNlO3JldHVybiB0cnVlfWVsc2Ugay5lcnJvcigiU3lu
dGF4IGVycm9yLCB1bnJlY29nbml6ZWQgZXhwcmVzc2lvbjogIitwKX0sQ0hJTEQ6ZnVuY3Rpb24o
ZyxpKXt2YXIgbj1pWzFdLG09Zztzd2l0Y2gobil7Y2FzZSAib25seSI6Y2FzZSAiZmlyc3QiOmZv
cig7bT1tLnByZXZpb3VzU2libGluZzspaWYobS5ub2RlVHlwZT09PTEpcmV0dXJuIGZhbHNlO2lm
KG49PT0KImZpcnN0IilyZXR1cm4gdHJ1ZTttPWc7Y2FzZSAibGFzdCI6Zm9yKDttPW0ubmV4dFNp
Ymxpbmc7KWlmKG0ubm9kZVR5cGU9PT0xKXJldHVybiBmYWxzZTtyZXR1cm4gdHJ1ZTtjYXNlICJu
dGgiOm49aVsyXTt2YXIgcD1pWzNdO2lmKG49PT0xJiZwPT09MClyZXR1cm4gdHJ1ZTt2YXIgcT1p
WzBdLHU9Zy5wYXJlbnROb2RlO2lmKHUmJih1LnNpemNhY2hlIT09cXx8IWcubm9kZUluZGV4KSl7
dmFyIHk9MDtmb3IobT11LmZpcnN0Q2hpbGQ7bTttPW0ubmV4dFNpYmxpbmcpaWYobS5ub2RlVHlw
ZT09PTEpbS5ub2RlSW5kZXg9Kyt5O3Uuc2l6Y2FjaGU9cX1tPWcubm9kZUluZGV4LXA7cmV0dXJu
IG49PT0wP209PT0wOm0lbj09PTAmJm0vbj49MH19LElEOmZ1bmN0aW9uKGcsaSl7cmV0dXJuIGcu
bm9kZVR5cGU9PT0xJiZnLmdldEF0dHJpYnV0ZSgiaWQiKT09PWl9LFRBRzpmdW5jdGlvbihnLGkp
e3JldHVybiBpPT09IioiJiZnLm5vZGVUeXBlPT09MXx8Zy5ub2RlTmFtZS50b0xvd2VyQ2FzZSgp
PT09Cml9LENMQVNTOmZ1bmN0aW9uKGcsaSl7cmV0dXJuKCIgIisoZy5jbGFzc05hbWV8fGcuZ2V0
QXR0cmlidXRlKCJjbGFzcyIpKSsiICIpLmluZGV4T2YoaSk+LTF9LEFUVFI6ZnVuY3Rpb24oZyxp
KXt2YXIgbj1pWzFdO249by5hdHRySGFuZGxlW25dP28uYXR0ckhhbmRsZVtuXShnKTpnW25dIT1u
dWxsP2dbbl06Zy5nZXRBdHRyaWJ1dGUobik7dmFyIG09bisiIixwPWlbMl0scT1pWzRdO3JldHVy
biBuPT1udWxsP3A9PT0iIT0iOnA9PT0iPSI/bT09PXE6cD09PSIqPSI/bS5pbmRleE9mKHEpPj0w
OnA9PT0ifj0iPygiICIrbSsiICIpLmluZGV4T2YocSk+PTA6IXE/bSYmbiE9PWZhbHNlOnA9PT0i
IT0iP20hPT1xOnA9PT0iXj0iP20uaW5kZXhPZihxKT09PTA6cD09PSIkPSI/bS5zdWJzdHIobS5s
ZW5ndGgtcS5sZW5ndGgpPT09cTpwPT09Inw9Ij9tPT09cXx8bS5zdWJzdHIoMCxxLmxlbmd0aCsx
KT09PXErIi0iOmZhbHNlfSxQT1M6ZnVuY3Rpb24oZyxpLG4sbSl7dmFyIHA9by5zZXRGaWx0ZXJz
W2lbMl1dOwppZihwKXJldHVybiBwKGcsbixpLG0pfX19LHg9by5tYXRjaC5QT1Mscj1mdW5jdGlv
bihnLGkpe3JldHVybiJcXCIrKGktMCsxKX0sQTtmb3IoQSBpbiBvLm1hdGNoKXtvLm1hdGNoW0Fd
PVJlZ0V4cChvLm1hdGNoW0FdLnNvdXJjZSsvKD8hW15cW10qXF0pKD8hW15cKF0qXCkpLy5zb3Vy
Y2UpO28ubGVmdE1hdGNoW0FdPVJlZ0V4cCgvKF4oPzoufFxyfFxuKSo/KS8uc291cmNlK28ubWF0
Y2hbQV0uc291cmNlLnJlcGxhY2UoL1xcKFxkKykvZyxyKSl9dmFyIEM9ZnVuY3Rpb24oZyxpKXtn
PUFycmF5LnByb3RvdHlwZS5zbGljZS5jYWxsKGcsMCk7aWYoaSl7aS5wdXNoLmFwcGx5KGksZyk7
cmV0dXJuIGl9cmV0dXJuIGd9O3RyeXtBcnJheS5wcm90b3R5cGUuc2xpY2UuY2FsbCh0LmRvY3Vt
ZW50RWxlbWVudC5jaGlsZE5vZGVzLDApfWNhdGNoKEope0M9ZnVuY3Rpb24oZyxpKXt2YXIgbj0w
LG09aXx8W107aWYoZi5jYWxsKGcpPT09IltvYmplY3QgQXJyYXldIilBcnJheS5wcm90b3R5cGUu
cHVzaC5hcHBseShtLApnKTtlbHNlIGlmKHR5cGVvZiBnLmxlbmd0aD09PSJudW1iZXIiKWZvcih2
YXIgcD1nLmxlbmd0aDtuPHA7bisrKW0ucHVzaChnW25dKTtlbHNlIGZvcig7Z1tuXTtuKyspbS5w
dXNoKGdbbl0pO3JldHVybiBtfX12YXIgdyxJO2lmKHQuZG9jdW1lbnRFbGVtZW50LmNvbXBhcmVE
b2N1bWVudFBvc2l0aW9uKXc9ZnVuY3Rpb24oZyxpKXtpZihnPT09aSl7aD10cnVlO3JldHVybiAw
fWlmKCFnLmNvbXBhcmVEb2N1bWVudFBvc2l0aW9ufHwhaS5jb21wYXJlRG9jdW1lbnRQb3NpdGlv
bilyZXR1cm4gZy5jb21wYXJlRG9jdW1lbnRQb3NpdGlvbj8tMToxO3JldHVybiBnLmNvbXBhcmVE
b2N1bWVudFBvc2l0aW9uKGkpJjQ/LTE6MX07ZWxzZXt3PWZ1bmN0aW9uKGcsaSl7dmFyIG4sbSxw
PVtdLHE9W107bj1nLnBhcmVudE5vZGU7bT1pLnBhcmVudE5vZGU7dmFyIHU9bjtpZihnPT09aSl7
aD10cnVlO3JldHVybiAwfWVsc2UgaWYobj09PW0pcmV0dXJuIEkoZyxpKTtlbHNlIGlmKG4pe2lm
KCFtKXJldHVybiAxfWVsc2UgcmV0dXJuLTE7CmZvcig7dTspe3AudW5zaGlmdCh1KTt1PXUucGFy
ZW50Tm9kZX1mb3IodT1tO3U7KXtxLnVuc2hpZnQodSk7dT11LnBhcmVudE5vZGV9bj1wLmxlbmd0
aDttPXEubGVuZ3RoO2Zvcih1PTA7dTxuJiZ1PG07dSsrKWlmKHBbdV0hPT1xW3VdKXJldHVybiBJ
KHBbdV0scVt1XSk7cmV0dXJuIHU9PT1uP0koZyxxW3VdLC0xKTpJKHBbdV0saSwxKX07ST1mdW5j
dGlvbihnLGksbil7aWYoZz09PWkpcmV0dXJuIG47Zm9yKGc9Zy5uZXh0U2libGluZztnOyl7aWYo
Zz09PWkpcmV0dXJuLTE7Zz1nLm5leHRTaWJsaW5nfXJldHVybiAxfX1rLmdldFRleHQ9ZnVuY3Rp
b24oZyl7Zm9yKHZhciBpPSIiLG4sbT0wO2dbbV07bSsrKXtuPWdbbV07aWYobi5ub2RlVHlwZT09
PTN8fG4ubm9kZVR5cGU9PT00KWkrPW4ubm9kZVZhbHVlO2Vsc2UgaWYobi5ub2RlVHlwZSE9PTgp
aSs9ay5nZXRUZXh0KG4uY2hpbGROb2Rlcyl9cmV0dXJuIGl9OyhmdW5jdGlvbigpe3ZhciBnPXQu
Y3JlYXRlRWxlbWVudCgiZGl2IiksCmk9InNjcmlwdCIrKG5ldyBEYXRlKS5nZXRUaW1lKCksbj10
LmRvY3VtZW50RWxlbWVudDtnLmlubmVySFRNTD0iPGEgbmFtZT0nIitpKyInLz4iO24uaW5zZXJ0
QmVmb3JlKGcsbi5maXJzdENoaWxkKTtpZih0LmdldEVsZW1lbnRCeUlkKGkpKXtvLmZpbmQuSUQ9
ZnVuY3Rpb24obSxwLHEpe2lmKHR5cGVvZiBwLmdldEVsZW1lbnRCeUlkIT09InVuZGVmaW5lZCIm
JiFxKXJldHVybihwPXAuZ2V0RWxlbWVudEJ5SWQobVsxXSkpP3AuaWQ9PT1tWzFdfHx0eXBlb2Yg
cC5nZXRBdHRyaWJ1dGVOb2RlIT09InVuZGVmaW5lZCImJnAuZ2V0QXR0cmlidXRlTm9kZSgiaWQi
KS5ub2RlVmFsdWU9PT1tWzFdP1twXTpCOltdfTtvLmZpbHRlci5JRD1mdW5jdGlvbihtLHApe3Zh
ciBxPXR5cGVvZiBtLmdldEF0dHJpYnV0ZU5vZGUhPT0idW5kZWZpbmVkIiYmbS5nZXRBdHRyaWJ1
dGVOb2RlKCJpZCIpO3JldHVybiBtLm5vZGVUeXBlPT09MSYmcSYmcS5ub2RlVmFsdWU9PT1wfX1u
LnJlbW92ZUNoaWxkKGcpOwpuPWc9bnVsbH0pKCk7KGZ1bmN0aW9uKCl7dmFyIGc9dC5jcmVhdGVF
bGVtZW50KCJkaXYiKTtnLmFwcGVuZENoaWxkKHQuY3JlYXRlQ29tbWVudCgiIikpO2lmKGcuZ2V0
RWxlbWVudHNCeVRhZ05hbWUoIioiKS5sZW5ndGg+MClvLmZpbmQuVEFHPWZ1bmN0aW9uKGksbil7
dmFyIG09bi5nZXRFbGVtZW50c0J5VGFnTmFtZShpWzFdKTtpZihpWzFdPT09IioiKXtmb3IodmFy
IHA9W10scT0wO21bcV07cSsrKW1bcV0ubm9kZVR5cGU9PT0xJiZwLnB1c2gobVtxXSk7bT1wfXJl
dHVybiBtfTtnLmlubmVySFRNTD0iPGEgaHJlZj0nIyc+PC9hPiI7aWYoZy5maXJzdENoaWxkJiZ0
eXBlb2YgZy5maXJzdENoaWxkLmdldEF0dHJpYnV0ZSE9PSJ1bmRlZmluZWQiJiZnLmZpcnN0Q2hp
bGQuZ2V0QXR0cmlidXRlKCJocmVmIikhPT0iIyIpby5hdHRySGFuZGxlLmhyZWY9ZnVuY3Rpb24o
aSl7cmV0dXJuIGkuZ2V0QXR0cmlidXRlKCJocmVmIiwyKX07Zz1udWxsfSkoKTt0LnF1ZXJ5U2Vs
ZWN0b3JBbGwmJgpmdW5jdGlvbigpe3ZhciBnPWssaT10LmNyZWF0ZUVsZW1lbnQoImRpdiIpO2ku
aW5uZXJIVE1MPSI8cCBjbGFzcz0nVEVTVCc+PC9wPiI7aWYoIShpLnF1ZXJ5U2VsZWN0b3JBbGwm
JmkucXVlcnlTZWxlY3RvckFsbCgiLlRFU1QiKS5sZW5ndGg9PT0wKSl7az1mdW5jdGlvbihtLHAs
cSx1KXtwPXB8fHQ7bT1tLnJlcGxhY2UoL1w9XHMqKFteJyJcXV0qKVxzKlxdL2csIj0nJDEnXSIp
O2lmKCF1JiYhay5pc1hNTChwKSlpZihwLm5vZGVUeXBlPT09OSl0cnl7cmV0dXJuIEMocC5xdWVy
eVNlbGVjdG9yQWxsKG0pLHEpfWNhdGNoKHkpe31lbHNlIGlmKHAubm9kZVR5cGU9PT0xJiZwLm5v
ZGVOYW1lLnRvTG93ZXJDYXNlKCkhPT0ib2JqZWN0Iil7dmFyIEY9cC5nZXRBdHRyaWJ1dGUoImlk
IiksTT1GfHwiX19zaXp6bGVfXyI7Rnx8cC5zZXRBdHRyaWJ1dGUoImlkIixNKTt0cnl7cmV0dXJu
IEMocC5xdWVyeVNlbGVjdG9yQWxsKCIjIitNKyIgIittKSxxKX1jYXRjaChOKXt9ZmluYWxseXtG
fHwKcC5yZW1vdmVBdHRyaWJ1dGUoImlkIil9fXJldHVybiBnKG0scCxxLHUpfTtmb3IodmFyIG4g
aW4gZylrW25dPWdbbl07aT1udWxsfX0oKTsoZnVuY3Rpb24oKXt2YXIgZz10LmRvY3VtZW50RWxl
bWVudCxpPWcubWF0Y2hlc1NlbGVjdG9yfHxnLm1vek1hdGNoZXNTZWxlY3Rvcnx8Zy53ZWJraXRN
YXRjaGVzU2VsZWN0b3J8fGcubXNNYXRjaGVzU2VsZWN0b3Isbj1mYWxzZTt0cnl7aS5jYWxsKHQu
ZG9jdW1lbnRFbGVtZW50LCJbdGVzdCE9JyddOnNpenpsZSIpfWNhdGNoKG0pe249dHJ1ZX1pZihp
KWsubWF0Y2hlc1NlbGVjdG9yPWZ1bmN0aW9uKHAscSl7cT1xLnJlcGxhY2UoL1w9XHMqKFteJyJc
XV0qKVxzKlxdL2csIj0nJDEnXSIpO2lmKCFrLmlzWE1MKHApKXRyeXtpZihufHwhby5tYXRjaC5Q
U0VVRE8udGVzdChxKSYmIS8hPS8udGVzdChxKSlyZXR1cm4gaS5jYWxsKHAscSl9Y2F0Y2godSl7
fXJldHVybiBrKHEsbnVsbCxudWxsLFtwXSkubGVuZ3RoPjB9fSkoKTsoZnVuY3Rpb24oKXt2YXIg
Zz0KdC5jcmVhdGVFbGVtZW50KCJkaXYiKTtnLmlubmVySFRNTD0iPGRpdiBjbGFzcz0ndGVzdCBl
Jz48L2Rpdj48ZGl2IGNsYXNzPSd0ZXN0Jz48L2Rpdj4iO2lmKCEoIWcuZ2V0RWxlbWVudHNCeUNs
YXNzTmFtZXx8Zy5nZXRFbGVtZW50c0J5Q2xhc3NOYW1lKCJlIikubGVuZ3RoPT09MCkpe2cubGFz
dENoaWxkLmNsYXNzTmFtZT0iZSI7aWYoZy5nZXRFbGVtZW50c0J5Q2xhc3NOYW1lKCJlIikubGVu
Z3RoIT09MSl7by5vcmRlci5zcGxpY2UoMSwwLCJDTEFTUyIpO28uZmluZC5DTEFTUz1mdW5jdGlv
bihpLG4sbSl7aWYodHlwZW9mIG4uZ2V0RWxlbWVudHNCeUNsYXNzTmFtZSE9PSJ1bmRlZmluZWQi
JiYhbSlyZXR1cm4gbi5nZXRFbGVtZW50c0J5Q2xhc3NOYW1lKGlbMV0pfTtnPW51bGx9fX0pKCk7
ay5jb250YWlucz10LmRvY3VtZW50RWxlbWVudC5jb250YWlucz9mdW5jdGlvbihnLGkpe3JldHVy
biBnIT09aSYmKGcuY29udGFpbnM/Zy5jb250YWlucyhpKTp0cnVlKX06dC5kb2N1bWVudEVsZW1l
bnQuY29tcGFyZURvY3VtZW50UG9zaXRpb24/CmZ1bmN0aW9uKGcsaSl7cmV0dXJuISEoZy5jb21w
YXJlRG9jdW1lbnRQb3NpdGlvbihpKSYxNil9OmZ1bmN0aW9uKCl7cmV0dXJuIGZhbHNlfTtrLmlz
WE1MPWZ1bmN0aW9uKGcpe3JldHVybihnPShnP2cub3duZXJEb2N1bWVudHx8ZzowKS5kb2N1bWVu
dEVsZW1lbnQpP2cubm9kZU5hbWUhPT0iSFRNTCI6ZmFsc2V9O3ZhciBMPWZ1bmN0aW9uKGcsaSl7
Zm9yKHZhciBuLG09W10scD0iIixxPWkubm9kZVR5cGU/W2ldOmk7bj1vLm1hdGNoLlBTRVVETy5l
eGVjKGcpOyl7cCs9blswXTtnPWcucmVwbGFjZShvLm1hdGNoLlBTRVVETywiIil9Zz1vLnJlbGF0
aXZlW2ddP2crIioiOmc7bj0wO2Zvcih2YXIgdT1xLmxlbmd0aDtuPHU7bisrKWsoZyxxW25dLG0p
O3JldHVybiBrLmZpbHRlcihwLG0pfTtjLmZpbmQ9aztjLmV4cHI9ay5zZWxlY3RvcnM7Yy5leHBy
WyI6Il09Yy5leHByLmZpbHRlcnM7Yy51bmlxdWU9ay51bmlxdWVTb3J0O2MudGV4dD1rLmdldFRl
eHQ7Yy5pc1hNTERvYz1rLmlzWE1MOwpjLmNvbnRhaW5zPWsuY29udGFpbnN9KSgpO3ZhciBaYT0v
VW50aWwkLywkYT0vXig/OnBhcmVudHN8cHJldlVudGlsfHByZXZBbGwpLyxhYj0vLC8sTmE9L14u
W146I1xbXC4sXSokLyxiYj1BcnJheS5wcm90b3R5cGUuc2xpY2UsY2I9Yy5leHByLm1hdGNoLlBP
UztjLmZuLmV4dGVuZCh7ZmluZDpmdW5jdGlvbihhKXtmb3IodmFyIGI9dGhpcy5wdXNoU3RhY2so
IiIsImZpbmQiLGEpLGQ9MCxlPTAsZj10aGlzLmxlbmd0aDtlPGY7ZSsrKXtkPWIubGVuZ3RoO2Mu
ZmluZChhLHRoaXNbZV0sYik7aWYoZT4wKWZvcih2YXIgaD1kO2g8Yi5sZW5ndGg7aCsrKWZvcih2
YXIgbD0wO2w8ZDtsKyspaWYoYltsXT09PWJbaF0pe2Iuc3BsaWNlKGgtLSwxKTticmVha319cmV0
dXJuIGJ9LGhhczpmdW5jdGlvbihhKXt2YXIgYj1jKGEpO3JldHVybiB0aGlzLmZpbHRlcihmdW5j
dGlvbigpe2Zvcih2YXIgZD0wLGU9Yi5sZW5ndGg7ZDxlO2QrKylpZihjLmNvbnRhaW5zKHRoaXMs
YltkXSkpcmV0dXJuIHRydWV9KX0sCm5vdDpmdW5jdGlvbihhKXtyZXR1cm4gdGhpcy5wdXNoU3Rh
Y2sobWEodGhpcyxhLGZhbHNlKSwibm90IixhKX0sZmlsdGVyOmZ1bmN0aW9uKGEpe3JldHVybiB0
aGlzLnB1c2hTdGFjayhtYSh0aGlzLGEsdHJ1ZSksImZpbHRlciIsYSl9LGlzOmZ1bmN0aW9uKGEp
e3JldHVybiEhYSYmYy5maWx0ZXIoYSx0aGlzKS5sZW5ndGg+MH0sY2xvc2VzdDpmdW5jdGlvbihh
LGIpe3ZhciBkPVtdLGUsZixoPXRoaXNbMF07aWYoYy5pc0FycmF5KGEpKXt2YXIgbCxrPXt9LG89
MTtpZihoJiZhLmxlbmd0aCl7ZT0wO2ZvcihmPWEubGVuZ3RoO2U8ZjtlKyspe2w9YVtlXTtrW2xd
fHwoa1tsXT1jLmV4cHIubWF0Y2guUE9TLnRlc3QobCk/YyhsLGJ8fHRoaXMuY29udGV4dCk6bCl9
Zm9yKDtoJiZoLm93bmVyRG9jdW1lbnQmJmghPT1iOyl7Zm9yKGwgaW4gayl7ZT1rW2xdO2lmKGUu
anF1ZXJ5P2UuaW5kZXgoaCk+LTE6YyhoKS5pcyhlKSlkLnB1c2goe3NlbGVjdG9yOmwsZWxlbTpo
LGxldmVsOm99KX1oPQpoLnBhcmVudE5vZGU7bysrfX1yZXR1cm4gZH1sPWNiLnRlc3QoYSk/Yyhh
LGJ8fHRoaXMuY29udGV4dCk6bnVsbDtlPTA7Zm9yKGY9dGhpcy5sZW5ndGg7ZTxmO2UrKylmb3Io
aD10aGlzW2VdO2g7KWlmKGw/bC5pbmRleChoKT4tMTpjLmZpbmQubWF0Y2hlc1NlbGVjdG9yKGgs
YSkpe2QucHVzaChoKTticmVha31lbHNle2g9aC5wYXJlbnROb2RlO2lmKCFofHwhaC5vd25lckRv
Y3VtZW50fHxoPT09YilicmVha31kPWQubGVuZ3RoPjE/Yy51bmlxdWUoZCk6ZDtyZXR1cm4gdGhp
cy5wdXNoU3RhY2soZCwiY2xvc2VzdCIsYSl9LGluZGV4OmZ1bmN0aW9uKGEpe2lmKCFhfHx0eXBl
b2YgYT09PSJzdHJpbmciKXJldHVybiBjLmluQXJyYXkodGhpc1swXSxhP2MoYSk6dGhpcy5wYXJl
bnQoKS5jaGlsZHJlbigpKTtyZXR1cm4gYy5pbkFycmF5KGEuanF1ZXJ5P2FbMF06YSx0aGlzKX0s
YWRkOmZ1bmN0aW9uKGEsYil7dmFyIGQ9dHlwZW9mIGE9PT0ic3RyaW5nIj9jKGEsYnx8dGhpcy5j
b250ZXh0KToKYy5tYWtlQXJyYXkoYSksZT1jLm1lcmdlKHRoaXMuZ2V0KCksZCk7cmV0dXJuIHRo
aXMucHVzaFN0YWNrKCFkWzBdfHwhZFswXS5wYXJlbnROb2RlfHxkWzBdLnBhcmVudE5vZGUubm9k
ZVR5cGU9PT0xMXx8IWVbMF18fCFlWzBdLnBhcmVudE5vZGV8fGVbMF0ucGFyZW50Tm9kZS5ub2Rl
VHlwZT09PTExP2U6Yy51bmlxdWUoZSkpfSxhbmRTZWxmOmZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMu
YWRkKHRoaXMucHJldk9iamVjdCl9fSk7Yy5lYWNoKHtwYXJlbnQ6ZnVuY3Rpb24oYSl7cmV0dXJu
KGE9YS5wYXJlbnROb2RlKSYmYS5ub2RlVHlwZSE9PTExP2E6bnVsbH0scGFyZW50czpmdW5jdGlv
bihhKXtyZXR1cm4gYy5kaXIoYSwicGFyZW50Tm9kZSIpfSxwYXJlbnRzVW50aWw6ZnVuY3Rpb24o
YSxiLGQpe3JldHVybiBjLmRpcihhLCJwYXJlbnROb2RlIixkKX0sbmV4dDpmdW5jdGlvbihhKXty
ZXR1cm4gYy5udGgoYSwyLCJuZXh0U2libGluZyIpfSxwcmV2OmZ1bmN0aW9uKGEpe3JldHVybiBj
Lm50aChhLAoyLCJwcmV2aW91c1NpYmxpbmciKX0sbmV4dEFsbDpmdW5jdGlvbihhKXtyZXR1cm4g
Yy5kaXIoYSwibmV4dFNpYmxpbmciKX0scHJldkFsbDpmdW5jdGlvbihhKXtyZXR1cm4gYy5kaXIo
YSwicHJldmlvdXNTaWJsaW5nIil9LG5leHRVbnRpbDpmdW5jdGlvbihhLGIsZCl7cmV0dXJuIGMu
ZGlyKGEsIm5leHRTaWJsaW5nIixkKX0scHJldlVudGlsOmZ1bmN0aW9uKGEsYixkKXtyZXR1cm4g
Yy5kaXIoYSwicHJldmlvdXNTaWJsaW5nIixkKX0sc2libGluZ3M6ZnVuY3Rpb24oYSl7cmV0dXJu
IGMuc2libGluZyhhLnBhcmVudE5vZGUuZmlyc3RDaGlsZCxhKX0sY2hpbGRyZW46ZnVuY3Rpb24o
YSl7cmV0dXJuIGMuc2libGluZyhhLmZpcnN0Q2hpbGQpfSxjb250ZW50czpmdW5jdGlvbihhKXty
ZXR1cm4gYy5ub2RlTmFtZShhLCJpZnJhbWUiKT9hLmNvbnRlbnREb2N1bWVudHx8YS5jb250ZW50
V2luZG93LmRvY3VtZW50OmMubWFrZUFycmF5KGEuY2hpbGROb2Rlcyl9fSxmdW5jdGlvbihhLApi
KXtjLmZuW2FdPWZ1bmN0aW9uKGQsZSl7dmFyIGY9Yy5tYXAodGhpcyxiLGQpO1phLnRlc3QoYSl8
fChlPWQpO2lmKGUmJnR5cGVvZiBlPT09InN0cmluZyIpZj1jLmZpbHRlcihlLGYpO2Y9dGhpcy5s
ZW5ndGg+MT9jLnVuaXF1ZShmKTpmO2lmKCh0aGlzLmxlbmd0aD4xfHxhYi50ZXN0KGUpKSYmJGEu
dGVzdChhKSlmPWYucmV2ZXJzZSgpO3JldHVybiB0aGlzLnB1c2hTdGFjayhmLGEsYmIuY2FsbChh
cmd1bWVudHMpLmpvaW4oIiwiKSl9fSk7Yy5leHRlbmQoe2ZpbHRlcjpmdW5jdGlvbihhLGIsZCl7
aWYoZClhPSI6bm90KCIrYSsiKSI7cmV0dXJuIGIubGVuZ3RoPT09MT9jLmZpbmQubWF0Y2hlc1Nl
bGVjdG9yKGJbMF0sYSk/W2JbMF1dOltdOmMuZmluZC5tYXRjaGVzKGEsYil9LGRpcjpmdW5jdGlv
bihhLGIsZCl7dmFyIGU9W107Zm9yKGE9YVtiXTthJiZhLm5vZGVUeXBlIT09OSYmKGQ9PT1CfHxh
Lm5vZGVUeXBlIT09MXx8IWMoYSkuaXMoZCkpOyl7YS5ub2RlVHlwZT09PTEmJgplLnB1c2goYSk7
YT1hW2JdfXJldHVybiBlfSxudGg6ZnVuY3Rpb24oYSxiLGQpe2I9Ynx8MTtmb3IodmFyIGU9MDth
O2E9YVtkXSlpZihhLm5vZGVUeXBlPT09MSYmKytlPT09YilicmVhaztyZXR1cm4gYX0sc2libGlu
ZzpmdW5jdGlvbihhLGIpe2Zvcih2YXIgZD1bXTthO2E9YS5uZXh0U2libGluZylhLm5vZGVUeXBl
PT09MSYmYSE9PWImJmQucHVzaChhKTtyZXR1cm4gZH19KTt2YXIgemE9LyBqUXVlcnlcZCs9Iig/
OlxkK3xudWxsKSIvZywkPS9eXHMrLyxBYT0vPCg/IWFyZWF8YnJ8Y29sfGVtYmVkfGhyfGltZ3xp
bnB1dHxsaW5rfG1ldGF8cGFyYW0pKChbXHc6XSspW14+XSopXC8+L2lnLEJhPS88KFtcdzpdKykv
LGRiPS88dGJvZHkvaSxlYj0vPHwmIz9cdys7LyxDYT0vPCg/OnNjcmlwdHxvYmplY3R8ZW1iZWR8
b3B0aW9ufHN0eWxlKS9pLERhPS9jaGVja2VkXHMqKD86W149XXw9XHMqLmNoZWNrZWQuKS9pLGZi
PS9cPShbXj0iJz5cc10rXC8pPi9nLFA9e29wdGlvbjpbMSwKIjxzZWxlY3QgbXVsdGlwbGU9J211
bHRpcGxlJz4iLCI8L3NlbGVjdD4iXSxsZWdlbmQ6WzEsIjxmaWVsZHNldD4iLCI8L2ZpZWxkc2V0
PiJdLHRoZWFkOlsxLCI8dGFibGU+IiwiPC90YWJsZT4iXSx0cjpbMiwiPHRhYmxlPjx0Ym9keT4i
LCI8L3Rib2R5PjwvdGFibGU+Il0sdGQ6WzMsIjx0YWJsZT48dGJvZHk+PHRyPiIsIjwvdHI+PC90
Ym9keT48L3RhYmxlPiJdLGNvbDpbMiwiPHRhYmxlPjx0Ym9keT48L3Rib2R5Pjxjb2xncm91cD4i
LCI8L2NvbGdyb3VwPjwvdGFibGU+Il0sYXJlYTpbMSwiPG1hcD4iLCI8L21hcD4iXSxfZGVmYXVs
dDpbMCwiIiwiIl19O1Aub3B0Z3JvdXA9UC5vcHRpb247UC50Ym9keT1QLnRmb290PVAuY29sZ3Jv
dXA9UC5jYXB0aW9uPVAudGhlYWQ7UC50aD1QLnRkO2lmKCFjLnN1cHBvcnQuaHRtbFNlcmlhbGl6
ZSlQLl9kZWZhdWx0PVsxLCJkaXY8ZGl2PiIsIjwvZGl2PiJdO2MuZm4uZXh0ZW5kKHt0ZXh0OmZ1
bmN0aW9uKGEpe2lmKGMuaXNGdW5jdGlvbihhKSlyZXR1cm4gdGhpcy5lYWNoKGZ1bmN0aW9uKGIp
e3ZhciBkPQpjKHRoaXMpO2QudGV4dChhLmNhbGwodGhpcyxiLGQudGV4dCgpKSl9KTtpZih0eXBl
b2YgYSE9PSJvYmplY3QiJiZhIT09QilyZXR1cm4gdGhpcy5lbXB0eSgpLmFwcGVuZCgodGhpc1sw
XSYmdGhpc1swXS5vd25lckRvY3VtZW50fHx0KS5jcmVhdGVUZXh0Tm9kZShhKSk7cmV0dXJuIGMu
dGV4dCh0aGlzKX0sd3JhcEFsbDpmdW5jdGlvbihhKXtpZihjLmlzRnVuY3Rpb24oYSkpcmV0dXJu
IHRoaXMuZWFjaChmdW5jdGlvbihkKXtjKHRoaXMpLndyYXBBbGwoYS5jYWxsKHRoaXMsZCkpfSk7
aWYodGhpc1swXSl7dmFyIGI9YyhhLHRoaXNbMF0ub3duZXJEb2N1bWVudCkuZXEoMCkuY2xvbmUo
dHJ1ZSk7dGhpc1swXS5wYXJlbnROb2RlJiZiLmluc2VydEJlZm9yZSh0aGlzWzBdKTtiLm1hcChm
dW5jdGlvbigpe2Zvcih2YXIgZD10aGlzO2QuZmlyc3RDaGlsZCYmZC5maXJzdENoaWxkLm5vZGVU
eXBlPT09MTspZD1kLmZpcnN0Q2hpbGQ7cmV0dXJuIGR9KS5hcHBlbmQodGhpcyl9cmV0dXJuIHRo
aXN9LAp3cmFwSW5uZXI6ZnVuY3Rpb24oYSl7aWYoYy5pc0Z1bmN0aW9uKGEpKXJldHVybiB0aGlz
LmVhY2goZnVuY3Rpb24oYil7Yyh0aGlzKS53cmFwSW5uZXIoYS5jYWxsKHRoaXMsYikpfSk7cmV0
dXJuIHRoaXMuZWFjaChmdW5jdGlvbigpe3ZhciBiPWModGhpcyksZD1iLmNvbnRlbnRzKCk7ZC5s
ZW5ndGg/ZC53cmFwQWxsKGEpOmIuYXBwZW5kKGEpfSl9LHdyYXA6ZnVuY3Rpb24oYSl7cmV0dXJu
IHRoaXMuZWFjaChmdW5jdGlvbigpe2ModGhpcykud3JhcEFsbChhKX0pfSx1bndyYXA6ZnVuY3Rp
b24oKXtyZXR1cm4gdGhpcy5wYXJlbnQoKS5lYWNoKGZ1bmN0aW9uKCl7Yy5ub2RlTmFtZSh0aGlz
LCJib2R5Iil8fGModGhpcykucmVwbGFjZVdpdGgodGhpcy5jaGlsZE5vZGVzKX0pLmVuZCgpfSxh
cHBlbmQ6ZnVuY3Rpb24oKXtyZXR1cm4gdGhpcy5kb21NYW5pcChhcmd1bWVudHMsdHJ1ZSxmdW5j
dGlvbihhKXt0aGlzLm5vZGVUeXBlPT09MSYmdGhpcy5hcHBlbmRDaGlsZChhKX0pfSwKcHJlcGVu
ZDpmdW5jdGlvbigpe3JldHVybiB0aGlzLmRvbU1hbmlwKGFyZ3VtZW50cyx0cnVlLGZ1bmN0aW9u
KGEpe3RoaXMubm9kZVR5cGU9PT0xJiZ0aGlzLmluc2VydEJlZm9yZShhLHRoaXMuZmlyc3RDaGls
ZCl9KX0sYmVmb3JlOmZ1bmN0aW9uKCl7aWYodGhpc1swXSYmdGhpc1swXS5wYXJlbnROb2RlKXJl
dHVybiB0aGlzLmRvbU1hbmlwKGFyZ3VtZW50cyxmYWxzZSxmdW5jdGlvbihiKXt0aGlzLnBhcmVu
dE5vZGUuaW5zZXJ0QmVmb3JlKGIsdGhpcyl9KTtlbHNlIGlmKGFyZ3VtZW50cy5sZW5ndGgpe3Zh
ciBhPWMoYXJndW1lbnRzWzBdKTthLnB1c2guYXBwbHkoYSx0aGlzLnRvQXJyYXkoKSk7cmV0dXJu
IHRoaXMucHVzaFN0YWNrKGEsImJlZm9yZSIsYXJndW1lbnRzKX19LGFmdGVyOmZ1bmN0aW9uKCl7
aWYodGhpc1swXSYmdGhpc1swXS5wYXJlbnROb2RlKXJldHVybiB0aGlzLmRvbU1hbmlwKGFyZ3Vt
ZW50cyxmYWxzZSxmdW5jdGlvbihiKXt0aGlzLnBhcmVudE5vZGUuaW5zZXJ0QmVmb3JlKGIsCnRo
aXMubmV4dFNpYmxpbmcpfSk7ZWxzZSBpZihhcmd1bWVudHMubGVuZ3RoKXt2YXIgYT10aGlzLnB1
c2hTdGFjayh0aGlzLCJhZnRlciIsYXJndW1lbnRzKTthLnB1c2guYXBwbHkoYSxjKGFyZ3VtZW50
c1swXSkudG9BcnJheSgpKTtyZXR1cm4gYX19LHJlbW92ZTpmdW5jdGlvbihhLGIpe2Zvcih2YXIg
ZD0wLGU7KGU9dGhpc1tkXSkhPW51bGw7ZCsrKWlmKCFhfHxjLmZpbHRlcihhLFtlXSkubGVuZ3Ro
KXtpZighYiYmZS5ub2RlVHlwZT09PTEpe2MuY2xlYW5EYXRhKGUuZ2V0RWxlbWVudHNCeVRhZ05h
bWUoIioiKSk7Yy5jbGVhbkRhdGEoW2VdKX1lLnBhcmVudE5vZGUmJmUucGFyZW50Tm9kZS5yZW1v
dmVDaGlsZChlKX1yZXR1cm4gdGhpc30sZW1wdHk6ZnVuY3Rpb24oKXtmb3IodmFyIGE9MCxiOyhi
PXRoaXNbYV0pIT1udWxsO2ErKylmb3IoYi5ub2RlVHlwZT09PTEmJmMuY2xlYW5EYXRhKGIuZ2V0
RWxlbWVudHNCeVRhZ05hbWUoIioiKSk7Yi5maXJzdENoaWxkOyliLnJlbW92ZUNoaWxkKGIuZmly
c3RDaGlsZCk7CnJldHVybiB0aGlzfSxjbG9uZTpmdW5jdGlvbihhKXt2YXIgYj10aGlzLm1hcChm
dW5jdGlvbigpe2lmKCFjLnN1cHBvcnQubm9DbG9uZUV2ZW50JiYhYy5pc1hNTERvYyh0aGlzKSl7
dmFyIGQ9dGhpcy5vdXRlckhUTUwsZT10aGlzLm93bmVyRG9jdW1lbnQ7aWYoIWQpe2Q9ZS5jcmVh
dGVFbGVtZW50KCJkaXYiKTtkLmFwcGVuZENoaWxkKHRoaXMuY2xvbmVOb2RlKHRydWUpKTtkPWQu
aW5uZXJIVE1MfXJldHVybiBjLmNsZWFuKFtkLnJlcGxhY2UoemEsIiIpLnJlcGxhY2UoZmIsJz0i
JDEiPicpLnJlcGxhY2UoJCwiIildLGUpWzBdfWVsc2UgcmV0dXJuIHRoaXMuY2xvbmVOb2RlKHRy
dWUpfSk7aWYoYT09PXRydWUpe25hKHRoaXMsYik7bmEodGhpcy5maW5kKCIqIiksYi5maW5kKCIq
IikpfXJldHVybiBifSxodG1sOmZ1bmN0aW9uKGEpe2lmKGE9PT1CKXJldHVybiB0aGlzWzBdJiZ0
aGlzWzBdLm5vZGVUeXBlPT09MT90aGlzWzBdLmlubmVySFRNTC5yZXBsYWNlKHphLCIiKTpudWxs
OwplbHNlIGlmKHR5cGVvZiBhPT09InN0cmluZyImJiFDYS50ZXN0KGEpJiYoYy5zdXBwb3J0Lmxl
YWRpbmdXaGl0ZXNwYWNlfHwhJC50ZXN0KGEpKSYmIVBbKEJhLmV4ZWMoYSl8fFsiIiwiIl0pWzFd
LnRvTG93ZXJDYXNlKCldKXthPWEucmVwbGFjZShBYSwiPCQxPjwvJDI+Iik7dHJ5e2Zvcih2YXIg
Yj0wLGQ9dGhpcy5sZW5ndGg7YjxkO2IrKylpZih0aGlzW2JdLm5vZGVUeXBlPT09MSl7Yy5jbGVh
bkRhdGEodGhpc1tiXS5nZXRFbGVtZW50c0J5VGFnTmFtZSgiKiIpKTt0aGlzW2JdLmlubmVySFRN
TD1hfX1jYXRjaChlKXt0aGlzLmVtcHR5KCkuYXBwZW5kKGEpfX1lbHNlIGMuaXNGdW5jdGlvbihh
KT90aGlzLmVhY2goZnVuY3Rpb24oZil7dmFyIGg9Yyh0aGlzKTtoLmh0bWwoYS5jYWxsKHRoaXMs
ZixoLmh0bWwoKSkpfSk6dGhpcy5lbXB0eSgpLmFwcGVuZChhKTtyZXR1cm4gdGhpc30scmVwbGFj
ZVdpdGg6ZnVuY3Rpb24oYSl7aWYodGhpc1swXSYmdGhpc1swXS5wYXJlbnROb2RlKXtpZihjLmlz
RnVuY3Rpb24oYSkpcmV0dXJuIHRoaXMuZWFjaChmdW5jdGlvbihiKXt2YXIgZD0KYyh0aGlzKSxl
PWQuaHRtbCgpO2QucmVwbGFjZVdpdGgoYS5jYWxsKHRoaXMsYixlKSl9KTtpZih0eXBlb2YgYSE9
PSJzdHJpbmciKWE9YyhhKS5kZXRhY2goKTtyZXR1cm4gdGhpcy5lYWNoKGZ1bmN0aW9uKCl7dmFy
IGI9dGhpcy5uZXh0U2libGluZyxkPXRoaXMucGFyZW50Tm9kZTtjKHRoaXMpLnJlbW92ZSgpO2I/
YyhiKS5iZWZvcmUoYSk6YyhkKS5hcHBlbmQoYSl9KX1lbHNlIHJldHVybiB0aGlzLnB1c2hTdGFj
ayhjKGMuaXNGdW5jdGlvbihhKT9hKCk6YSksInJlcGxhY2VXaXRoIixhKX0sZGV0YWNoOmZ1bmN0
aW9uKGEpe3JldHVybiB0aGlzLnJlbW92ZShhLHRydWUpfSxkb21NYW5pcDpmdW5jdGlvbihhLGIs
ZCl7dmFyIGUsZixoLGw9YVswXSxrPVtdO2lmKCFjLnN1cHBvcnQuY2hlY2tDbG9uZSYmYXJndW1l
bnRzLmxlbmd0aD09PTMmJnR5cGVvZiBsPT09InN0cmluZyImJkRhLnRlc3QobCkpcmV0dXJuIHRo
aXMuZWFjaChmdW5jdGlvbigpe2ModGhpcykuZG9tTWFuaXAoYSwKYixkLHRydWUpfSk7aWYoYy5p
c0Z1bmN0aW9uKGwpKXJldHVybiB0aGlzLmVhY2goZnVuY3Rpb24oeCl7dmFyIHI9Yyh0aGlzKTth
WzBdPWwuY2FsbCh0aGlzLHgsYj9yLmh0bWwoKTpCKTtyLmRvbU1hbmlwKGEsYixkKX0pO2lmKHRo
aXNbMF0pe2U9bCYmbC5wYXJlbnROb2RlO2U9Yy5zdXBwb3J0LnBhcmVudE5vZGUmJmUmJmUubm9k
ZVR5cGU9PT0xMSYmZS5jaGlsZE5vZGVzLmxlbmd0aD09PXRoaXMubGVuZ3RoP3tmcmFnbWVudDpl
fTpjLmJ1aWxkRnJhZ21lbnQoYSx0aGlzLGspO2g9ZS5mcmFnbWVudDtpZihmPWguY2hpbGROb2Rl
cy5sZW5ndGg9PT0xP2g9aC5maXJzdENoaWxkOmguZmlyc3RDaGlsZCl7Yj1iJiZjLm5vZGVOYW1l
KGYsInRyIik7Zj0wO2Zvcih2YXIgbz10aGlzLmxlbmd0aDtmPG87ZisrKWQuY2FsbChiP2Mubm9k
ZU5hbWUodGhpc1tmXSwidGFibGUiKT90aGlzW2ZdLmdldEVsZW1lbnRzQnlUYWdOYW1lKCJ0Ym9k
eSIpWzBdfHx0aGlzW2ZdLmFwcGVuZENoaWxkKHRoaXNbZl0ub3duZXJEb2N1bWVudC5jcmVhdGVF
bGVtZW50KCJ0Ym9keSIpKToKdGhpc1tmXTp0aGlzW2ZdLGY+MHx8ZS5jYWNoZWFibGV8fHRoaXMu
bGVuZ3RoPjE/aC5jbG9uZU5vZGUodHJ1ZSk6aCl9ay5sZW5ndGgmJmMuZWFjaChrLE9hKX1yZXR1
cm4gdGhpc319KTtjLmJ1aWxkRnJhZ21lbnQ9ZnVuY3Rpb24oYSxiLGQpe3ZhciBlLGYsaDtiPWIm
JmJbMF0/YlswXS5vd25lckRvY3VtZW50fHxiWzBdOnQ7aWYoYS5sZW5ndGg9PT0xJiZ0eXBlb2Yg
YVswXT09PSJzdHJpbmciJiZhWzBdLmxlbmd0aDw1MTImJmI9PT10JiYhQ2EudGVzdChhWzBdKSYm
KGMuc3VwcG9ydC5jaGVja0Nsb25lfHwhRGEudGVzdChhWzBdKSkpe2Y9dHJ1ZTtpZihoPWMuZnJh
Z21lbnRzW2FbMF1dKWlmKGghPT0xKWU9aH1pZighZSl7ZT1iLmNyZWF0ZURvY3VtZW50RnJhZ21l
bnQoKTtjLmNsZWFuKGEsYixlLGQpfWlmKGYpYy5mcmFnbWVudHNbYVswXV09aD9lOjE7cmV0dXJu
e2ZyYWdtZW50OmUsY2FjaGVhYmxlOmZ9fTtjLmZyYWdtZW50cz17fTtjLmVhY2goe2FwcGVuZFRv
OiJhcHBlbmQiLApwcmVwZW5kVG86InByZXBlbmQiLGluc2VydEJlZm9yZToiYmVmb3JlIixpbnNl
cnRBZnRlcjoiYWZ0ZXIiLHJlcGxhY2VBbGw6InJlcGxhY2VXaXRoIn0sZnVuY3Rpb24oYSxiKXtj
LmZuW2FdPWZ1bmN0aW9uKGQpe3ZhciBlPVtdO2Q9YyhkKTt2YXIgZj10aGlzLmxlbmd0aD09PTEm
JnRoaXNbMF0ucGFyZW50Tm9kZTtpZihmJiZmLm5vZGVUeXBlPT09MTEmJmYuY2hpbGROb2Rlcy5s
ZW5ndGg9PT0xJiZkLmxlbmd0aD09PTEpe2RbYl0odGhpc1swXSk7cmV0dXJuIHRoaXN9ZWxzZXtm
PTA7Zm9yKHZhciBoPWQubGVuZ3RoO2Y8aDtmKyspe3ZhciBsPShmPjA/dGhpcy5jbG9uZSh0cnVl
KTp0aGlzKS5nZXQoKTtjKGRbZl0pW2JdKGwpO2U9ZS5jb25jYXQobCl9cmV0dXJuIHRoaXMucHVz
aFN0YWNrKGUsYSxkLnNlbGVjdG9yKX19fSk7Yy5leHRlbmQoe2NsZWFuOmZ1bmN0aW9uKGEsYixk
LGUpe2I9Ynx8dDtpZih0eXBlb2YgYi5jcmVhdGVFbGVtZW50PT09InVuZGVmaW5lZCIpYj1iLm93
bmVyRG9jdW1lbnR8fApiWzBdJiZiWzBdLm93bmVyRG9jdW1lbnR8fHQ7Zm9yKHZhciBmPVtdLGg9
MCxsOyhsPWFbaF0pIT1udWxsO2grKyl7aWYodHlwZW9mIGw9PT0ibnVtYmVyIilsKz0iIjtpZihs
KXtpZih0eXBlb2YgbD09PSJzdHJpbmciJiYhZWIudGVzdChsKSlsPWIuY3JlYXRlVGV4dE5vZGUo
bCk7ZWxzZSBpZih0eXBlb2YgbD09PSJzdHJpbmciKXtsPWwucmVwbGFjZShBYSwiPCQxPjwvJDI+
Iik7dmFyIGs9KEJhLmV4ZWMobCl8fFsiIiwiIl0pWzFdLnRvTG93ZXJDYXNlKCksbz1QW2tdfHxQ
Ll9kZWZhdWx0LHg9b1swXSxyPWIuY3JlYXRlRWxlbWVudCgiZGl2Iik7Zm9yKHIuaW5uZXJIVE1M
PW9bMV0rbCtvWzJdO3gtLTspcj1yLmxhc3RDaGlsZDtpZighYy5zdXBwb3J0LnRib2R5KXt4PWRi
LnRlc3QobCk7az1rPT09InRhYmxlIiYmIXg/ci5maXJzdENoaWxkJiZyLmZpcnN0Q2hpbGQuY2hp
bGROb2RlczpvWzFdPT09Ijx0YWJsZT4iJiYheD9yLmNoaWxkTm9kZXM6W107Zm9yKG89ay5sZW5n
dGgtCjE7bz49MDstLW8pYy5ub2RlTmFtZShrW29dLCJ0Ym9keSIpJiYha1tvXS5jaGlsZE5vZGVz
Lmxlbmd0aCYma1tvXS5wYXJlbnROb2RlLnJlbW92ZUNoaWxkKGtbb10pfSFjLnN1cHBvcnQubGVh
ZGluZ1doaXRlc3BhY2UmJiQudGVzdChsKSYmci5pbnNlcnRCZWZvcmUoYi5jcmVhdGVUZXh0Tm9k
ZSgkLmV4ZWMobClbMF0pLHIuZmlyc3RDaGlsZCk7bD1yLmNoaWxkTm9kZXN9aWYobC5ub2RlVHlw
ZSlmLnB1c2gobCk7ZWxzZSBmPWMubWVyZ2UoZixsKX19aWYoZClmb3IoaD0wO2ZbaF07aCsrKWlm
KGUmJmMubm9kZU5hbWUoZltoXSwic2NyaXB0IikmJighZltoXS50eXBlfHxmW2hdLnR5cGUudG9M
b3dlckNhc2UoKT09PSJ0ZXh0L2phdmFzY3JpcHQiKSllLnB1c2goZltoXS5wYXJlbnROb2RlP2Zb
aF0ucGFyZW50Tm9kZS5yZW1vdmVDaGlsZChmW2hdKTpmW2hdKTtlbHNle2ZbaF0ubm9kZVR5cGU9
PT0xJiZmLnNwbGljZS5hcHBseShmLFtoKzEsMF0uY29uY2F0KGMubWFrZUFycmF5KGZbaF0uZ2V0
RWxlbWVudHNCeVRhZ05hbWUoInNjcmlwdCIpKSkpOwpkLmFwcGVuZENoaWxkKGZbaF0pfXJldHVy
biBmfSxjbGVhbkRhdGE6ZnVuY3Rpb24oYSl7Zm9yKHZhciBiLGQsZT1jLmNhY2hlLGY9Yy5ldmVu
dC5zcGVjaWFsLGg9Yy5zdXBwb3J0LmRlbGV0ZUV4cGFuZG8sbD0wLGs7KGs9YVtsXSkhPW51bGw7
bCsrKWlmKCEoay5ub2RlTmFtZSYmYy5ub0RhdGFbay5ub2RlTmFtZS50b0xvd2VyQ2FzZSgpXSkp
aWYoZD1rW2MuZXhwYW5kb10pe2lmKChiPWVbZF0pJiZiLmV2ZW50cylmb3IodmFyIG8gaW4gYi5l
dmVudHMpZltvXT9jLmV2ZW50LnJlbW92ZShrLG8pOmMucmVtb3ZlRXZlbnQoayxvLGIuaGFuZGxl
KTtpZihoKWRlbGV0ZSBrW2MuZXhwYW5kb107ZWxzZSBrLnJlbW92ZUF0dHJpYnV0ZSYmay5yZW1v
dmVBdHRyaWJ1dGUoYy5leHBhbmRvKTtkZWxldGUgZVtkXX19fSk7dmFyIEVhPS9hbHBoYVwoW14p
XSpcKS9pLGdiPS9vcGFjaXR5PShbXildKikvLGhiPS8tKFthLXpdKS9pZyxpYj0vKFtBLVpdKS9n
LEZhPS9eLT9cZCsoPzpweCk/JC9pLApqYj0vXi0/XGQvLGtiPXtwb3NpdGlvbjoiYWJzb2x1dGUi
LHZpc2liaWxpdHk6ImhpZGRlbiIsZGlzcGxheToiYmxvY2sifSxQYT1bIkxlZnQiLCJSaWdodCJd
LFFhPVsiVG9wIiwiQm90dG9tIl0sVyxHYSxhYSxsYj1mdW5jdGlvbihhLGIpe3JldHVybiBiLnRv
VXBwZXJDYXNlKCl9O2MuZm4uY3NzPWZ1bmN0aW9uKGEsYil7aWYoYXJndW1lbnRzLmxlbmd0aD09
PTImJmI9PT1CKXJldHVybiB0aGlzO3JldHVybiBjLmFjY2Vzcyh0aGlzLGEsYix0cnVlLGZ1bmN0
aW9uKGQsZSxmKXtyZXR1cm4gZiE9PUI/Yy5zdHlsZShkLGUsZik6Yy5jc3MoZCxlKX0pfTtjLmV4
dGVuZCh7Y3NzSG9va3M6e29wYWNpdHk6e2dldDpmdW5jdGlvbihhLGIpe2lmKGIpe3ZhciBkPVco
YSwib3BhY2l0eSIsIm9wYWNpdHkiKTtyZXR1cm4gZD09PSIiPyIxIjpkfWVsc2UgcmV0dXJuIGEu
c3R5bGUub3BhY2l0eX19fSxjc3NOdW1iZXI6e3pJbmRleDp0cnVlLGZvbnRXZWlnaHQ6dHJ1ZSxv
cGFjaXR5OnRydWUsCnpvb206dHJ1ZSxsaW5lSGVpZ2h0OnRydWV9LGNzc1Byb3BzOnsiZmxvYXQi
OmMuc3VwcG9ydC5jc3NGbG9hdD8iY3NzRmxvYXQiOiJzdHlsZUZsb2F0In0sc3R5bGU6ZnVuY3Rp
b24oYSxiLGQsZSl7aWYoISghYXx8YS5ub2RlVHlwZT09PTN8fGEubm9kZVR5cGU9PT04fHwhYS5z
dHlsZSkpe3ZhciBmLGg9Yy5jYW1lbENhc2UoYiksbD1hLnN0eWxlLGs9Yy5jc3NIb29rc1toXTti
PWMuY3NzUHJvcHNbaF18fGg7aWYoZCE9PUIpe2lmKCEodHlwZW9mIGQ9PT0ibnVtYmVyIiYmaXNO
YU4oZCl8fGQ9PW51bGwpKXtpZih0eXBlb2YgZD09PSJudW1iZXIiJiYhYy5jc3NOdW1iZXJbaF0p
ZCs9InB4IjtpZigha3x8ISgic2V0ImluIGspfHwoZD1rLnNldChhLGQpKSE9PUIpdHJ5e2xbYl09
ZH1jYXRjaChvKXt9fX1lbHNle2lmKGsmJiJnZXQiaW4gayYmKGY9ay5nZXQoYSxmYWxzZSxlKSkh
PT1CKXJldHVybiBmO3JldHVybiBsW2JdfX19LGNzczpmdW5jdGlvbihhLGIsZCl7dmFyIGUsZj1j
LmNhbWVsQ2FzZShiKSwKaD1jLmNzc0hvb2tzW2ZdO2I9Yy5jc3NQcm9wc1tmXXx8ZjtpZihoJiYi
Z2V0ImluIGgmJihlPWguZ2V0KGEsdHJ1ZSxkKSkhPT1CKXJldHVybiBlO2Vsc2UgaWYoVylyZXR1
cm4gVyhhLGIsZil9LHN3YXA6ZnVuY3Rpb24oYSxiLGQpe3ZhciBlPXt9LGY7Zm9yKGYgaW4gYil7
ZVtmXT1hLnN0eWxlW2ZdO2Euc3R5bGVbZl09YltmXX1kLmNhbGwoYSk7Zm9yKGYgaW4gYilhLnN0
eWxlW2ZdPWVbZl19LGNhbWVsQ2FzZTpmdW5jdGlvbihhKXtyZXR1cm4gYS5yZXBsYWNlKGhiLGxi
KX19KTtjLmN1ckNTUz1jLmNzcztjLmVhY2goWyJoZWlnaHQiLCJ3aWR0aCJdLGZ1bmN0aW9uKGEs
Yil7Yy5jc3NIb29rc1tiXT17Z2V0OmZ1bmN0aW9uKGQsZSxmKXt2YXIgaDtpZihlKXtpZihkLm9m
ZnNldFdpZHRoIT09MCloPW9hKGQsYixmKTtlbHNlIGMuc3dhcChkLGtiLGZ1bmN0aW9uKCl7aD1v
YShkLGIsZil9KTtpZihoPD0wKXtoPVcoZCxiLGIpO2lmKGg9PT0iMHB4IiYmYWEpaD1hYShkLGIs
Yik7CmlmKGghPW51bGwpcmV0dXJuIGg9PT0iInx8aD09PSJhdXRvIj8iMHB4IjpofWlmKGg8MHx8
aD09bnVsbCl7aD1kLnN0eWxlW2JdO3JldHVybiBoPT09IiJ8fGg9PT0iYXV0byI/IjBweCI6aH1y
ZXR1cm4gdHlwZW9mIGg9PT0ic3RyaW5nIj9oOmgrInB4In19LHNldDpmdW5jdGlvbihkLGUpe2lm
KEZhLnRlc3QoZSkpe2U9cGFyc2VGbG9hdChlKTtpZihlPj0wKXJldHVybiBlKyJweCJ9ZWxzZSBy
ZXR1cm4gZX19fSk7aWYoIWMuc3VwcG9ydC5vcGFjaXR5KWMuY3NzSG9va3Mub3BhY2l0eT17Z2V0
OmZ1bmN0aW9uKGEsYil7cmV0dXJuIGdiLnRlc3QoKGImJmEuY3VycmVudFN0eWxlP2EuY3VycmVu
dFN0eWxlLmZpbHRlcjphLnN0eWxlLmZpbHRlcil8fCIiKT9wYXJzZUZsb2F0KFJlZ0V4cC4kMSkv
MTAwKyIiOmI/IjEiOiIifSxzZXQ6ZnVuY3Rpb24oYSxiKXt2YXIgZD1hLnN0eWxlO2Quem9vbT0x
O3ZhciBlPWMuaXNOYU4oYik/IiI6ImFscGhhKG9wYWNpdHk9IitiKjEwMCsiKSIsZj0KZC5maWx0
ZXJ8fCIiO2QuZmlsdGVyPUVhLnRlc3QoZik/Zi5yZXBsYWNlKEVhLGUpOmQuZmlsdGVyKyIgIitl
fX07aWYodC5kZWZhdWx0VmlldyYmdC5kZWZhdWx0Vmlldy5nZXRDb21wdXRlZFN0eWxlKUdhPWZ1
bmN0aW9uKGEsYixkKXt2YXIgZTtkPWQucmVwbGFjZShpYiwiLSQxIikudG9Mb3dlckNhc2UoKTtp
ZighKGI9YS5vd25lckRvY3VtZW50LmRlZmF1bHRWaWV3KSlyZXR1cm4gQjtpZihiPWIuZ2V0Q29t
cHV0ZWRTdHlsZShhLG51bGwpKXtlPWIuZ2V0UHJvcGVydHlWYWx1ZShkKTtpZihlPT09IiImJiFj
LmNvbnRhaW5zKGEub3duZXJEb2N1bWVudC5kb2N1bWVudEVsZW1lbnQsYSkpZT1jLnN0eWxlKGEs
ZCl9cmV0dXJuIGV9O2lmKHQuZG9jdW1lbnRFbGVtZW50LmN1cnJlbnRTdHlsZSlhYT1mdW5jdGlv
bihhLGIpe3ZhciBkLGUsZj1hLmN1cnJlbnRTdHlsZSYmYS5jdXJyZW50U3R5bGVbYl0saD1hLnN0
eWxlO2lmKCFGYS50ZXN0KGYpJiZqYi50ZXN0KGYpKXtkPWgubGVmdDsKZT1hLnJ1bnRpbWVTdHls
ZS5sZWZ0O2EucnVudGltZVN0eWxlLmxlZnQ9YS5jdXJyZW50U3R5bGUubGVmdDtoLmxlZnQ9Yj09
PSJmb250U2l6ZSI/IjFlbSI6Znx8MDtmPWgucGl4ZWxMZWZ0KyJweCI7aC5sZWZ0PWQ7YS5ydW50
aW1lU3R5bGUubGVmdD1lfXJldHVybiBmPT09IiI/ImF1dG8iOmZ9O1c9R2F8fGFhO2lmKGMuZXhw
ciYmYy5leHByLmZpbHRlcnMpe2MuZXhwci5maWx0ZXJzLmhpZGRlbj1mdW5jdGlvbihhKXt2YXIg
Yj1hLm9mZnNldEhlaWdodDtyZXR1cm4gYS5vZmZzZXRXaWR0aD09PTAmJmI9PT0wfHwhYy5zdXBw
b3J0LnJlbGlhYmxlSGlkZGVuT2Zmc2V0cyYmKGEuc3R5bGUuZGlzcGxheXx8Yy5jc3MoYSwiZGlz
cGxheSIpKT09PSJub25lIn07Yy5leHByLmZpbHRlcnMudmlzaWJsZT1mdW5jdGlvbihhKXtyZXR1
cm4hYy5leHByLmZpbHRlcnMuaGlkZGVuKGEpfX12YXIgbWI9Yy5ub3coKSxuYj0vPHNjcmlwdFxi
W148XSooPzooPyE8XC9zY3JpcHQ+KTxbXjxdKikqPFwvc2NyaXB0Pi9naSwKb2I9L14oPzpzZWxl
Y3R8dGV4dGFyZWEpL2kscGI9L14oPzpjb2xvcnxkYXRlfGRhdGV0aW1lfGVtYWlsfGhpZGRlbnxt
b250aHxudW1iZXJ8cGFzc3dvcmR8cmFuZ2V8c2VhcmNofHRlbHx0ZXh0fHRpbWV8dXJsfHdlZWsp
JC9pLHFiPS9eKD86R0VUfEhFQUQpJC8sUmE9L1xbXF0kLyxUPS9cPVw/KCZ8JCkvLGphPS9cPy8s
cmI9LyhbPyZdKV89W14mXSovLHNiPS9eKFx3KzopP1wvXC8oW15cLz8jXSspLyx0Yj0vJTIwL2cs
dWI9LyMuKiQvLEhhPWMuZm4ubG9hZDtjLmZuLmV4dGVuZCh7bG9hZDpmdW5jdGlvbihhLGIsZCl7
aWYodHlwZW9mIGEhPT0ic3RyaW5nIiYmSGEpcmV0dXJuIEhhLmFwcGx5KHRoaXMsYXJndW1lbnRz
KTtlbHNlIGlmKCF0aGlzLmxlbmd0aClyZXR1cm4gdGhpczt2YXIgZT1hLmluZGV4T2YoIiAiKTtp
ZihlPj0wKXt2YXIgZj1hLnNsaWNlKGUsYS5sZW5ndGgpO2E9YS5zbGljZSgwLGUpfWU9IkdFVCI7
aWYoYilpZihjLmlzRnVuY3Rpb24oYikpe2Q9YjtiPW51bGx9ZWxzZSBpZih0eXBlb2YgYj09PQoi
b2JqZWN0Iil7Yj1jLnBhcmFtKGIsYy5hamF4U2V0dGluZ3MudHJhZGl0aW9uYWwpO2U9IlBPU1Qi
fXZhciBoPXRoaXM7Yy5hamF4KHt1cmw6YSx0eXBlOmUsZGF0YVR5cGU6Imh0bWwiLGRhdGE6Yixj
b21wbGV0ZTpmdW5jdGlvbihsLGspe2lmKGs9PT0ic3VjY2VzcyJ8fGs9PT0ibm90bW9kaWZpZWQi
KWguaHRtbChmP2MoIjxkaXY+IikuYXBwZW5kKGwucmVzcG9uc2VUZXh0LnJlcGxhY2UobmIsIiIp
KS5maW5kKGYpOmwucmVzcG9uc2VUZXh0KTtkJiZoLmVhY2goZCxbbC5yZXNwb25zZVRleHQsayxs
XSl9fSk7cmV0dXJuIHRoaXN9LHNlcmlhbGl6ZTpmdW5jdGlvbigpe3JldHVybiBjLnBhcmFtKHRo
aXMuc2VyaWFsaXplQXJyYXkoKSl9LHNlcmlhbGl6ZUFycmF5OmZ1bmN0aW9uKCl7cmV0dXJuIHRo
aXMubWFwKGZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMuZWxlbWVudHM/Yy5tYWtlQXJyYXkodGhpcy5l
bGVtZW50cyk6dGhpc30pLmZpbHRlcihmdW5jdGlvbigpe3JldHVybiB0aGlzLm5hbWUmJgohdGhp
cy5kaXNhYmxlZCYmKHRoaXMuY2hlY2tlZHx8b2IudGVzdCh0aGlzLm5vZGVOYW1lKXx8cGIudGVz
dCh0aGlzLnR5cGUpKX0pLm1hcChmdW5jdGlvbihhLGIpe3ZhciBkPWModGhpcykudmFsKCk7cmV0
dXJuIGQ9PW51bGw/bnVsbDpjLmlzQXJyYXkoZCk/Yy5tYXAoZCxmdW5jdGlvbihlKXtyZXR1cm57
bmFtZTpiLm5hbWUsdmFsdWU6ZX19KTp7bmFtZTpiLm5hbWUsdmFsdWU6ZH19KS5nZXQoKX19KTtj
LmVhY2goImFqYXhTdGFydCBhamF4U3RvcCBhamF4Q29tcGxldGUgYWpheEVycm9yIGFqYXhTdWNj
ZXNzIGFqYXhTZW5kIi5zcGxpdCgiICIpLGZ1bmN0aW9uKGEsYil7Yy5mbltiXT1mdW5jdGlvbihk
KXtyZXR1cm4gdGhpcy5iaW5kKGIsZCl9fSk7Yy5leHRlbmQoe2dldDpmdW5jdGlvbihhLGIsZCxl
KXtpZihjLmlzRnVuY3Rpb24oYikpe2U9ZXx8ZDtkPWI7Yj1udWxsfXJldHVybiBjLmFqYXgoe3R5
cGU6IkdFVCIsdXJsOmEsZGF0YTpiLHN1Y2Nlc3M6ZCxkYXRhVHlwZTplfSl9LApnZXRTY3JpcHQ6
ZnVuY3Rpb24oYSxiKXtyZXR1cm4gYy5nZXQoYSxudWxsLGIsInNjcmlwdCIpfSxnZXRKU09OOmZ1
bmN0aW9uKGEsYixkKXtyZXR1cm4gYy5nZXQoYSxiLGQsImpzb24iKX0scG9zdDpmdW5jdGlvbihh
LGIsZCxlKXtpZihjLmlzRnVuY3Rpb24oYikpe2U9ZXx8ZDtkPWI7Yj17fX1yZXR1cm4gYy5hamF4
KHt0eXBlOiJQT1NUIix1cmw6YSxkYXRhOmIsc3VjY2VzczpkLGRhdGFUeXBlOmV9KX0sYWpheFNl
dHVwOmZ1bmN0aW9uKGEpe2MuZXh0ZW5kKGMuYWpheFNldHRpbmdzLGEpfSxhamF4U2V0dGluZ3M6
e3VybDpsb2NhdGlvbi5ocmVmLGdsb2JhbDp0cnVlLHR5cGU6IkdFVCIsY29udGVudFR5cGU6ImFw
cGxpY2F0aW9uL3gtd3d3LWZvcm0tdXJsZW5jb2RlZCIscHJvY2Vzc0RhdGE6dHJ1ZSxhc3luYzp0
cnVlLHhocjpmdW5jdGlvbigpe3JldHVybiBuZXcgRS5YTUxIdHRwUmVxdWVzdH0sYWNjZXB0czp7
eG1sOiJhcHBsaWNhdGlvbi94bWwsIHRleHQveG1sIixodG1sOiJ0ZXh0L2h0bWwiLApzY3JpcHQ6
InRleHQvamF2YXNjcmlwdCwgYXBwbGljYXRpb24vamF2YXNjcmlwdCIsanNvbjoiYXBwbGljYXRp
b24vanNvbiwgdGV4dC9qYXZhc2NyaXB0Iix0ZXh0OiJ0ZXh0L3BsYWluIixfZGVmYXVsdDoiKi8q
In19LGFqYXg6ZnVuY3Rpb24oYSl7dmFyIGI9Yy5leHRlbmQodHJ1ZSx7fSxjLmFqYXhTZXR0aW5n
cyxhKSxkLGUsZixoPWIudHlwZS50b1VwcGVyQ2FzZSgpLGw9cWIudGVzdChoKTtiLnVybD1iLnVy
bC5yZXBsYWNlKHViLCIiKTtiLmNvbnRleHQ9YSYmYS5jb250ZXh0IT1udWxsP2EuY29udGV4dDpi
O2lmKGIuZGF0YSYmYi5wcm9jZXNzRGF0YSYmdHlwZW9mIGIuZGF0YSE9PSJzdHJpbmciKWIuZGF0
YT1jLnBhcmFtKGIuZGF0YSxiLnRyYWRpdGlvbmFsKTtpZihiLmRhdGFUeXBlPT09Impzb25wIil7
aWYoaD09PSJHRVQiKVQudGVzdChiLnVybCl8fChiLnVybCs9KGphLnRlc3QoYi51cmwpPyImIjoi
PyIpKyhiLmpzb25wfHwiY2FsbGJhY2siKSsiPT8iKTtlbHNlIGlmKCFiLmRhdGF8fAohVC50ZXN0
KGIuZGF0YSkpYi5kYXRhPShiLmRhdGE/Yi5kYXRhKyImIjoiIikrKGIuanNvbnB8fCJjYWxsYmFj
ayIpKyI9PyI7Yi5kYXRhVHlwZT0ianNvbiJ9aWYoYi5kYXRhVHlwZT09PSJqc29uIiYmKGIuZGF0
YSYmVC50ZXN0KGIuZGF0YSl8fFQudGVzdChiLnVybCkpKXtkPWIuanNvbnBDYWxsYmFja3x8Impz
b25wIittYisrO2lmKGIuZGF0YSliLmRhdGE9KGIuZGF0YSsiIikucmVwbGFjZShULCI9IitkKyIk
MSIpO2IudXJsPWIudXJsLnJlcGxhY2UoVCwiPSIrZCsiJDEiKTtiLmRhdGFUeXBlPSJzY3JpcHQi
O3ZhciBrPUVbZF07RVtkXT1mdW5jdGlvbihtKXtpZihjLmlzRnVuY3Rpb24oaykpayhtKTtlbHNl
e0VbZF09Qjt0cnl7ZGVsZXRlIEVbZF19Y2F0Y2gocCl7fX1mPW07Yy5oYW5kbGVTdWNjZXNzKGIs
dyxlLGYpO2MuaGFuZGxlQ29tcGxldGUoYix3LGUsZik7ciYmci5yZW1vdmVDaGlsZChBKX19aWYo
Yi5kYXRhVHlwZT09PSJzY3JpcHQiJiZiLmNhY2hlPT09bnVsbCliLmNhY2hlPQpmYWxzZTtpZihi
LmNhY2hlPT09ZmFsc2UmJmwpe3ZhciBvPWMubm93KCkseD1iLnVybC5yZXBsYWNlKHJiLCIkMV89
IitvKTtiLnVybD14Kyh4PT09Yi51cmw/KGphLnRlc3QoYi51cmwpPyImIjoiPyIpKyJfPSIrbzoi
Iil9aWYoYi5kYXRhJiZsKWIudXJsKz0oamEudGVzdChiLnVybCk/IiYiOiI/IikrYi5kYXRhO2Iu
Z2xvYmFsJiZjLmFjdGl2ZSsrPT09MCYmYy5ldmVudC50cmlnZ2VyKCJhamF4U3RhcnQiKTtvPShv
PXNiLmV4ZWMoYi51cmwpKSYmKG9bMV0mJm9bMV0udG9Mb3dlckNhc2UoKSE9PWxvY2F0aW9uLnBy
b3RvY29sfHxvWzJdLnRvTG93ZXJDYXNlKCkhPT1sb2NhdGlvbi5ob3N0KTtpZihiLmRhdGFUeXBl
PT09InNjcmlwdCImJmg9PT0iR0VUIiYmbyl7dmFyIHI9dC5nZXRFbGVtZW50c0J5VGFnTmFtZSgi
aGVhZCIpWzBdfHx0LmRvY3VtZW50RWxlbWVudCxBPXQuY3JlYXRlRWxlbWVudCgic2NyaXB0Iik7
aWYoYi5zY3JpcHRDaGFyc2V0KUEuY2hhcnNldD1iLnNjcmlwdENoYXJzZXQ7CkEuc3JjPWIudXJs
O2lmKCFkKXt2YXIgQz1mYWxzZTtBLm9ubG9hZD1BLm9ucmVhZHlzdGF0ZWNoYW5nZT1mdW5jdGlv
bigpe2lmKCFDJiYoIXRoaXMucmVhZHlTdGF0ZXx8dGhpcy5yZWFkeVN0YXRlPT09ImxvYWRlZCJ8
fHRoaXMucmVhZHlTdGF0ZT09PSJjb21wbGV0ZSIpKXtDPXRydWU7Yy5oYW5kbGVTdWNjZXNzKGIs
dyxlLGYpO2MuaGFuZGxlQ29tcGxldGUoYix3LGUsZik7QS5vbmxvYWQ9QS5vbnJlYWR5c3RhdGVj
aGFuZ2U9bnVsbDtyJiZBLnBhcmVudE5vZGUmJnIucmVtb3ZlQ2hpbGQoQSl9fX1yLmluc2VydEJl
Zm9yZShBLHIuZmlyc3RDaGlsZCk7cmV0dXJuIEJ9dmFyIEo9ZmFsc2Usdz1iLnhocigpO2lmKHcp
e2IudXNlcm5hbWU/dy5vcGVuKGgsYi51cmwsYi5hc3luYyxiLnVzZXJuYW1lLGIucGFzc3dvcmQp
Oncub3BlbihoLGIudXJsLGIuYXN5bmMpO3RyeXtpZihiLmRhdGEhPW51bGwmJiFsfHxhJiZhLmNv
bnRlbnRUeXBlKXcuc2V0UmVxdWVzdEhlYWRlcigiQ29udGVudC1UeXBlIiwKYi5jb250ZW50VHlw
ZSk7aWYoYi5pZk1vZGlmaWVkKXtjLmxhc3RNb2RpZmllZFtiLnVybF0mJncuc2V0UmVxdWVzdEhl
YWRlcigiSWYtTW9kaWZpZWQtU2luY2UiLGMubGFzdE1vZGlmaWVkW2IudXJsXSk7Yy5ldGFnW2Iu
dXJsXSYmdy5zZXRSZXF1ZXN0SGVhZGVyKCJJZi1Ob25lLU1hdGNoIixjLmV0YWdbYi51cmxdKX1v
fHx3LnNldFJlcXVlc3RIZWFkZXIoIlgtUmVxdWVzdGVkLVdpdGgiLCJYTUxIdHRwUmVxdWVzdCIp
O3cuc2V0UmVxdWVzdEhlYWRlcigiQWNjZXB0IixiLmRhdGFUeXBlJiZiLmFjY2VwdHNbYi5kYXRh
VHlwZV0/Yi5hY2NlcHRzW2IuZGF0YVR5cGVdKyIsICovKjsgcT0wLjAxIjpiLmFjY2VwdHMuX2Rl
ZmF1bHQpfWNhdGNoKEkpe31pZihiLmJlZm9yZVNlbmQmJmIuYmVmb3JlU2VuZC5jYWxsKGIuY29u
dGV4dCx3LGIpPT09ZmFsc2Upe2IuZ2xvYmFsJiZjLmFjdGl2ZS0tPT09MSYmYy5ldmVudC50cmln
Z2VyKCJhamF4U3RvcCIpO3cuYWJvcnQoKTtyZXR1cm4gZmFsc2V9Yi5nbG9iYWwmJgpjLnRyaWdn
ZXJHbG9iYWwoYiwiYWpheFNlbmQiLFt3LGJdKTt2YXIgTD13Lm9ucmVhZHlzdGF0ZWNoYW5nZT1m
dW5jdGlvbihtKXtpZighd3x8dy5yZWFkeVN0YXRlPT09MHx8bT09PSJhYm9ydCIpe0p8fGMuaGFu
ZGxlQ29tcGxldGUoYix3LGUsZik7Sj10cnVlO2lmKHcpdy5vbnJlYWR5c3RhdGVjaGFuZ2U9Yy5u
b29wfWVsc2UgaWYoIUomJncmJih3LnJlYWR5U3RhdGU9PT00fHxtPT09InRpbWVvdXQiKSl7Sj10
cnVlO3cub25yZWFkeXN0YXRlY2hhbmdlPWMubm9vcDtlPW09PT0idGltZW91dCI/InRpbWVvdXQi
OiFjLmh0dHBTdWNjZXNzKHcpPyJlcnJvciI6Yi5pZk1vZGlmaWVkJiZjLmh0dHBOb3RNb2RpZmll
ZCh3LGIudXJsKT8ibm90bW9kaWZpZWQiOiJzdWNjZXNzIjt2YXIgcDtpZihlPT09InN1Y2Nlc3Mi
KXRyeXtmPWMuaHR0cERhdGEodyxiLmRhdGFUeXBlLGIpfWNhdGNoKHEpe2U9InBhcnNlcmVycm9y
IjtwPXF9aWYoZT09PSJzdWNjZXNzInx8ZT09PSJub3Rtb2RpZmllZCIpZHx8CmMuaGFuZGxlU3Vj
Y2VzcyhiLHcsZSxmKTtlbHNlIGMuaGFuZGxlRXJyb3IoYix3LGUscCk7ZHx8Yy5oYW5kbGVDb21w
bGV0ZShiLHcsZSxmKTttPT09InRpbWVvdXQiJiZ3LmFib3J0KCk7aWYoYi5hc3luYyl3PW51bGx9
fTt0cnl7dmFyIGc9dy5hYm9ydDt3LmFib3J0PWZ1bmN0aW9uKCl7dyYmRnVuY3Rpb24ucHJvdG90
eXBlLmNhbGwuY2FsbChnLHcpO0woImFib3J0Iil9fWNhdGNoKGkpe31iLmFzeW5jJiZiLnRpbWVv
dXQ+MCYmc2V0VGltZW91dChmdW5jdGlvbigpe3cmJiFKJiZMKCJ0aW1lb3V0Iil9LGIudGltZW91
dCk7dHJ5e3cuc2VuZChsfHxiLmRhdGE9PW51bGw/bnVsbDpiLmRhdGEpfWNhdGNoKG4pe2MuaGFu
ZGxlRXJyb3IoYix3LG51bGwsbik7Yy5oYW5kbGVDb21wbGV0ZShiLHcsZSxmKX1iLmFzeW5jfHxM
KCk7cmV0dXJuIHd9fSxwYXJhbTpmdW5jdGlvbihhLGIpe3ZhciBkPVtdLGU9ZnVuY3Rpb24oaCxs
KXtsPWMuaXNGdW5jdGlvbihsKT9sKCk6bDtkW2QubGVuZ3RoXT0KZW5jb2RlVVJJQ29tcG9uZW50
KGgpKyI9IitlbmNvZGVVUklDb21wb25lbnQobCl9O2lmKGI9PT1CKWI9Yy5hamF4U2V0dGluZ3Mu
dHJhZGl0aW9uYWw7aWYoYy5pc0FycmF5KGEpfHxhLmpxdWVyeSljLmVhY2goYSxmdW5jdGlvbigp
e2UodGhpcy5uYW1lLHRoaXMudmFsdWUpfSk7ZWxzZSBmb3IodmFyIGYgaW4gYSlkYShmLGFbZl0s
YixlKTtyZXR1cm4gZC5qb2luKCImIikucmVwbGFjZSh0YiwiKyIpfX0pO2MuZXh0ZW5kKHthY3Rp
dmU6MCxsYXN0TW9kaWZpZWQ6e30sZXRhZzp7fSxoYW5kbGVFcnJvcjpmdW5jdGlvbihhLGIsZCxl
KXthLmVycm9yJiZhLmVycm9yLmNhbGwoYS5jb250ZXh0LGIsZCxlKTthLmdsb2JhbCYmYy50cmln
Z2VyR2xvYmFsKGEsImFqYXhFcnJvciIsW2IsYSxlXSl9LGhhbmRsZVN1Y2Nlc3M6ZnVuY3Rpb24o
YSxiLGQsZSl7YS5zdWNjZXNzJiZhLnN1Y2Nlc3MuY2FsbChhLmNvbnRleHQsZSxkLGIpO2EuZ2xv
YmFsJiZjLnRyaWdnZXJHbG9iYWwoYSwiYWpheFN1Y2Nlc3MiLApbYixhXSl9LGhhbmRsZUNvbXBs
ZXRlOmZ1bmN0aW9uKGEsYixkKXthLmNvbXBsZXRlJiZhLmNvbXBsZXRlLmNhbGwoYS5jb250ZXh0
LGIsZCk7YS5nbG9iYWwmJmMudHJpZ2dlckdsb2JhbChhLCJhamF4Q29tcGxldGUiLFtiLGFdKTth
Lmdsb2JhbCYmYy5hY3RpdmUtLT09PTEmJmMuZXZlbnQudHJpZ2dlcigiYWpheFN0b3AiKX0sdHJp
Z2dlckdsb2JhbDpmdW5jdGlvbihhLGIsZCl7KGEuY29udGV4dCYmYS5jb250ZXh0LnVybD09bnVs
bD9jKGEuY29udGV4dCk6Yy5ldmVudCkudHJpZ2dlcihiLGQpfSxodHRwU3VjY2VzczpmdW5jdGlv
bihhKXt0cnl7cmV0dXJuIWEuc3RhdHVzJiZsb2NhdGlvbi5wcm90b2NvbD09PSJmaWxlOiJ8fGEu
c3RhdHVzPj0yMDAmJmEuc3RhdHVzPDMwMHx8YS5zdGF0dXM9PT0zMDR8fGEuc3RhdHVzPT09MTIy
M31jYXRjaChiKXt9cmV0dXJuIGZhbHNlfSxodHRwTm90TW9kaWZpZWQ6ZnVuY3Rpb24oYSxiKXt2
YXIgZD1hLmdldFJlc3BvbnNlSGVhZGVyKCJMYXN0LU1vZGlmaWVkIiksCmU9YS5nZXRSZXNwb25z
ZUhlYWRlcigiRXRhZyIpO2lmKGQpYy5sYXN0TW9kaWZpZWRbYl09ZDtpZihlKWMuZXRhZ1tiXT1l
O3JldHVybiBhLnN0YXR1cz09PTMwNH0saHR0cERhdGE6ZnVuY3Rpb24oYSxiLGQpe3ZhciBlPWEu
Z2V0UmVzcG9uc2VIZWFkZXIoImNvbnRlbnQtdHlwZSIpfHwiIixmPWI9PT0ieG1sInx8IWImJmUu
aW5kZXhPZigieG1sIik+PTA7YT1mP2EucmVzcG9uc2VYTUw6YS5yZXNwb25zZVRleHQ7ZiYmYS5k
b2N1bWVudEVsZW1lbnQubm9kZU5hbWU9PT0icGFyc2VyZXJyb3IiJiZjLmVycm9yKCJwYXJzZXJl
cnJvciIpO2lmKGQmJmQuZGF0YUZpbHRlcilhPWQuZGF0YUZpbHRlcihhLGIpO2lmKHR5cGVvZiBh
PT09InN0cmluZyIpaWYoYj09PSJqc29uInx8IWImJmUuaW5kZXhPZigianNvbiIpPj0wKWE9Yy5w
YXJzZUpTT04oYSk7ZWxzZSBpZihiPT09InNjcmlwdCJ8fCFiJiZlLmluZGV4T2YoImphdmFzY3Jp
cHQiKT49MCljLmdsb2JhbEV2YWwoYSk7cmV0dXJuIGF9fSk7CmlmKEUuQWN0aXZlWE9iamVjdClj
LmFqYXhTZXR0aW5ncy54aHI9ZnVuY3Rpb24oKXtpZihFLmxvY2F0aW9uLnByb3RvY29sIT09ImZp
bGU6Iil0cnl7cmV0dXJuIG5ldyBFLlhNTEh0dHBSZXF1ZXN0fWNhdGNoKGEpe310cnl7cmV0dXJu
IG5ldyBFLkFjdGl2ZVhPYmplY3QoIk1pY3Jvc29mdC5YTUxIVFRQIil9Y2F0Y2goYil7fX07Yy5z
dXBwb3J0LmFqYXg9ISFjLmFqYXhTZXR0aW5ncy54aHIoKTt2YXIgZWE9e30sdmI9L14oPzp0b2dn
bGV8c2hvd3xoaWRlKSQvLHdiPS9eKFsrXC1dPSk/KFtcZCsuXC1dKykoLiopJC8sYmEscGE9W1si
aGVpZ2h0IiwibWFyZ2luVG9wIiwibWFyZ2luQm90dG9tIiwicGFkZGluZ1RvcCIsInBhZGRpbmdC
b3R0b20iXSxbIndpZHRoIiwibWFyZ2luTGVmdCIsIm1hcmdpblJpZ2h0IiwicGFkZGluZ0xlZnQi
LCJwYWRkaW5nUmlnaHQiXSxbIm9wYWNpdHkiXV07Yy5mbi5leHRlbmQoe3Nob3c6ZnVuY3Rpb24o
YSxiLGQpe2lmKGF8fGE9PT0wKXJldHVybiB0aGlzLmFuaW1hdGUoUygic2hvdyIsCjMpLGEsYixk
KTtlbHNle2Q9MDtmb3IodmFyIGU9dGhpcy5sZW5ndGg7ZDxlO2QrKyl7YT10aGlzW2RdO2I9YS5z
dHlsZS5kaXNwbGF5O2lmKCFjLmRhdGEoYSwib2xkZGlzcGxheSIpJiZiPT09Im5vbmUiKWI9YS5z
dHlsZS5kaXNwbGF5PSIiO2I9PT0iIiYmYy5jc3MoYSwiZGlzcGxheSIpPT09Im5vbmUiJiZjLmRh
dGEoYSwib2xkZGlzcGxheSIscWEoYS5ub2RlTmFtZSkpfWZvcihkPTA7ZDxlO2QrKyl7YT10aGlz
W2RdO2I9YS5zdHlsZS5kaXNwbGF5O2lmKGI9PT0iInx8Yj09PSJub25lIilhLnN0eWxlLmRpc3Bs
YXk9Yy5kYXRhKGEsIm9sZGRpc3BsYXkiKXx8IiJ9cmV0dXJuIHRoaXN9fSxoaWRlOmZ1bmN0aW9u
KGEsYixkKXtpZihhfHxhPT09MClyZXR1cm4gdGhpcy5hbmltYXRlKFMoImhpZGUiLDMpLGEsYixk
KTtlbHNle2E9MDtmb3IoYj10aGlzLmxlbmd0aDthPGI7YSsrKXtkPWMuY3NzKHRoaXNbYV0sImRp
c3BsYXkiKTtkIT09Im5vbmUiJiZjLmRhdGEodGhpc1thXSwib2xkZGlzcGxheSIsCmQpfWZvcihh
PTA7YTxiO2ErKyl0aGlzW2FdLnN0eWxlLmRpc3BsYXk9Im5vbmUiO3JldHVybiB0aGlzfX0sX3Rv
Z2dsZTpjLmZuLnRvZ2dsZSx0b2dnbGU6ZnVuY3Rpb24oYSxiLGQpe3ZhciBlPXR5cGVvZiBhPT09
ImJvb2xlYW4iO2lmKGMuaXNGdW5jdGlvbihhKSYmYy5pc0Z1bmN0aW9uKGIpKXRoaXMuX3RvZ2ds
ZS5hcHBseSh0aGlzLGFyZ3VtZW50cyk7ZWxzZSBhPT1udWxsfHxlP3RoaXMuZWFjaChmdW5jdGlv
bigpe3ZhciBmPWU/YTpjKHRoaXMpLmlzKCI6aGlkZGVuIik7Yyh0aGlzKVtmPyJzaG93IjoiaGlk
ZSJdKCl9KTp0aGlzLmFuaW1hdGUoUygidG9nZ2xlIiwzKSxhLGIsZCk7cmV0dXJuIHRoaXN9LGZh
ZGVUbzpmdW5jdGlvbihhLGIsZCxlKXtyZXR1cm4gdGhpcy5maWx0ZXIoIjpoaWRkZW4iKS5jc3Mo
Im9wYWNpdHkiLDApLnNob3coKS5lbmQoKS5hbmltYXRlKHtvcGFjaXR5OmJ9LGEsZCxlKX0sYW5p
bWF0ZTpmdW5jdGlvbihhLGIsZCxlKXt2YXIgZj1jLnNwZWVkKGIsCmQsZSk7aWYoYy5pc0VtcHR5
T2JqZWN0KGEpKXJldHVybiB0aGlzLmVhY2goZi5jb21wbGV0ZSk7cmV0dXJuIHRoaXNbZi5xdWV1
ZT09PWZhbHNlPyJlYWNoIjoicXVldWUiXShmdW5jdGlvbigpe3ZhciBoPWMuZXh0ZW5kKHt9LGYp
LGwsaz10aGlzLm5vZGVUeXBlPT09MSxvPWsmJmModGhpcykuaXMoIjpoaWRkZW4iKSx4PXRoaXM7
Zm9yKGwgaW4gYSl7dmFyIHI9Yy5jYW1lbENhc2UobCk7aWYobCE9PXIpe2Fbcl09YVtsXTtkZWxl
dGUgYVtsXTtsPXJ9aWYoYVtsXT09PSJoaWRlIiYmb3x8YVtsXT09PSJzaG93IiYmIW8pcmV0dXJu
IGguY29tcGxldGUuY2FsbCh0aGlzKTtpZihrJiYobD09PSJoZWlnaHQifHxsPT09IndpZHRoIikp
e2gub3ZlcmZsb3c9W3RoaXMuc3R5bGUub3ZlcmZsb3csdGhpcy5zdHlsZS5vdmVyZmxvd1gsdGhp
cy5zdHlsZS5vdmVyZmxvd1ldO2lmKGMuY3NzKHRoaXMsImRpc3BsYXkiKT09PSJpbmxpbmUiJiZj
LmNzcyh0aGlzLCJmbG9hdCIpPT09Im5vbmUiKWlmKGMuc3VwcG9ydC5pbmxpbmVCbG9ja05lZWRz
TGF5b3V0KWlmKHFhKHRoaXMubm9kZU5hbWUpPT09CiJpbmxpbmUiKXRoaXMuc3R5bGUuZGlzcGxh
eT0iaW5saW5lLWJsb2NrIjtlbHNle3RoaXMuc3R5bGUuZGlzcGxheT0iaW5saW5lIjt0aGlzLnN0
eWxlLnpvb209MX1lbHNlIHRoaXMuc3R5bGUuZGlzcGxheT0iaW5saW5lLWJsb2NrIn1pZihjLmlz
QXJyYXkoYVtsXSkpeyhoLnNwZWNpYWxFYXNpbmc9aC5zcGVjaWFsRWFzaW5nfHx7fSlbbF09YVts
XVsxXTthW2xdPWFbbF1bMF19fWlmKGgub3ZlcmZsb3chPW51bGwpdGhpcy5zdHlsZS5vdmVyZmxv
dz0iaGlkZGVuIjtoLmN1ckFuaW09Yy5leHRlbmQoe30sYSk7Yy5lYWNoKGEsZnVuY3Rpb24oQSxD
KXt2YXIgSj1uZXcgYy5meCh4LGgsQSk7aWYodmIudGVzdChDKSlKW0M9PT0idG9nZ2xlIj9vPyJz
aG93IjoiaGlkZSI6Q10oYSk7ZWxzZXt2YXIgdz13Yi5leGVjKEMpLEk9Si5jdXIoKXx8MDtpZih3
KXt2YXIgTD1wYXJzZUZsb2F0KHdbMl0pLGc9d1szXXx8InB4IjtpZihnIT09InB4Iil7Yy5zdHls
ZSh4LEEsKEx8fDEpK2cpO0k9KEx8fAoxKS9KLmN1cigpKkk7Yy5zdHlsZSh4LEEsSStnKX1pZih3
WzFdKUw9KHdbMV09PT0iLT0iPy0xOjEpKkwrSTtKLmN1c3RvbShJLEwsZyl9ZWxzZSBKLmN1c3Rv
bShJLEMsIiIpfX0pO3JldHVybiB0cnVlfSl9LHN0b3A6ZnVuY3Rpb24oYSxiKXt2YXIgZD1jLnRp
bWVyczthJiZ0aGlzLnF1ZXVlKFtdKTt0aGlzLmVhY2goZnVuY3Rpb24oKXtmb3IodmFyIGU9ZC5s
ZW5ndGgtMTtlPj0wO2UtLSlpZihkW2VdLmVsZW09PT10aGlzKXtiJiZkW2VdKHRydWUpO2Quc3Bs
aWNlKGUsMSl9fSk7Ynx8dGhpcy5kZXF1ZXVlKCk7cmV0dXJuIHRoaXN9fSk7Yy5lYWNoKHtzbGlk
ZURvd246Uygic2hvdyIsMSksc2xpZGVVcDpTKCJoaWRlIiwxKSxzbGlkZVRvZ2dsZTpTKCJ0b2dn
bGUiLDEpLGZhZGVJbjp7b3BhY2l0eToic2hvdyJ9LGZhZGVPdXQ6e29wYWNpdHk6ImhpZGUifSxm
YWRlVG9nZ2xlOntvcGFjaXR5OiJ0b2dnbGUifX0sZnVuY3Rpb24oYSxiKXtjLmZuW2FdPWZ1bmN0
aW9uKGQsZSxmKXtyZXR1cm4gdGhpcy5hbmltYXRlKGIsCmQsZSxmKX19KTtjLmV4dGVuZCh7c3Bl
ZWQ6ZnVuY3Rpb24oYSxiLGQpe3ZhciBlPWEmJnR5cGVvZiBhPT09Im9iamVjdCI/Yy5leHRlbmQo
e30sYSk6e2NvbXBsZXRlOmR8fCFkJiZifHxjLmlzRnVuY3Rpb24oYSkmJmEsZHVyYXRpb246YSxl
YXNpbmc6ZCYmYnx8YiYmIWMuaXNGdW5jdGlvbihiKSYmYn07ZS5kdXJhdGlvbj1jLmZ4Lm9mZj8w
OnR5cGVvZiBlLmR1cmF0aW9uPT09Im51bWJlciI/ZS5kdXJhdGlvbjplLmR1cmF0aW9uIGluIGMu
Znguc3BlZWRzP2MuZnguc3BlZWRzW2UuZHVyYXRpb25dOmMuZnguc3BlZWRzLl9kZWZhdWx0O2Uu
b2xkPWUuY29tcGxldGU7ZS5jb21wbGV0ZT1mdW5jdGlvbigpe2UucXVldWUhPT1mYWxzZSYmYyh0
aGlzKS5kZXF1ZXVlKCk7Yy5pc0Z1bmN0aW9uKGUub2xkKSYmZS5vbGQuY2FsbCh0aGlzKX07cmV0
dXJuIGV9LGVhc2luZzp7bGluZWFyOmZ1bmN0aW9uKGEsYixkLGUpe3JldHVybiBkK2UqYX0sc3dp
bmc6ZnVuY3Rpb24oYSxiLGQsZSl7cmV0dXJuKC1NYXRoLmNvcyhhKgpNYXRoLlBJKS8yKzAuNSkq
ZStkfX0sdGltZXJzOltdLGZ4OmZ1bmN0aW9uKGEsYixkKXt0aGlzLm9wdGlvbnM9Yjt0aGlzLmVs
ZW09YTt0aGlzLnByb3A9ZDtpZighYi5vcmlnKWIub3JpZz17fX19KTtjLmZ4LnByb3RvdHlwZT17
dXBkYXRlOmZ1bmN0aW9uKCl7dGhpcy5vcHRpb25zLnN0ZXAmJnRoaXMub3B0aW9ucy5zdGVwLmNh
bGwodGhpcy5lbGVtLHRoaXMubm93LHRoaXMpOyhjLmZ4LnN0ZXBbdGhpcy5wcm9wXXx8Yy5meC5z
dGVwLl9kZWZhdWx0KSh0aGlzKX0sY3VyOmZ1bmN0aW9uKCl7aWYodGhpcy5lbGVtW3RoaXMucHJv
cF0hPW51bGwmJighdGhpcy5lbGVtLnN0eWxlfHx0aGlzLmVsZW0uc3R5bGVbdGhpcy5wcm9wXT09
bnVsbCkpcmV0dXJuIHRoaXMuZWxlbVt0aGlzLnByb3BdO3ZhciBhPXBhcnNlRmxvYXQoYy5jc3Mo
dGhpcy5lbGVtLHRoaXMucHJvcCkpO3JldHVybiBhJiZhPi0xRTQ/YTowfSxjdXN0b206ZnVuY3Rp
b24oYSxiLGQpe2Z1bmN0aW9uIGUobCl7cmV0dXJuIGYuc3RlcChsKX0KdmFyIGY9dGhpcyxoPWMu
Zng7dGhpcy5zdGFydFRpbWU9Yy5ub3coKTt0aGlzLnN0YXJ0PWE7dGhpcy5lbmQ9Yjt0aGlzLnVu
aXQ9ZHx8dGhpcy51bml0fHwicHgiO3RoaXMubm93PXRoaXMuc3RhcnQ7dGhpcy5wb3M9dGhpcy5z
dGF0ZT0wO2UuZWxlbT10aGlzLmVsZW07aWYoZSgpJiZjLnRpbWVycy5wdXNoKGUpJiYhYmEpYmE9
c2V0SW50ZXJ2YWwoaC50aWNrLGguaW50ZXJ2YWwpfSxzaG93OmZ1bmN0aW9uKCl7dGhpcy5vcHRp
b25zLm9yaWdbdGhpcy5wcm9wXT1jLnN0eWxlKHRoaXMuZWxlbSx0aGlzLnByb3ApO3RoaXMub3B0
aW9ucy5zaG93PXRydWU7dGhpcy5jdXN0b20odGhpcy5wcm9wPT09IndpZHRoInx8dGhpcy5wcm9w
PT09ImhlaWdodCI/MTowLHRoaXMuY3VyKCkpO2ModGhpcy5lbGVtKS5zaG93KCl9LGhpZGU6ZnVu
Y3Rpb24oKXt0aGlzLm9wdGlvbnMub3JpZ1t0aGlzLnByb3BdPWMuc3R5bGUodGhpcy5lbGVtLHRo
aXMucHJvcCk7dGhpcy5vcHRpb25zLmhpZGU9dHJ1ZTsKdGhpcy5jdXN0b20odGhpcy5jdXIoKSww
KX0sc3RlcDpmdW5jdGlvbihhKXt2YXIgYj1jLm5vdygpLGQ9dHJ1ZTtpZihhfHxiPj10aGlzLm9w
dGlvbnMuZHVyYXRpb24rdGhpcy5zdGFydFRpbWUpe3RoaXMubm93PXRoaXMuZW5kO3RoaXMucG9z
PXRoaXMuc3RhdGU9MTt0aGlzLnVwZGF0ZSgpO3RoaXMub3B0aW9ucy5jdXJBbmltW3RoaXMucHJv
cF09dHJ1ZTtmb3IodmFyIGUgaW4gdGhpcy5vcHRpb25zLmN1ckFuaW0paWYodGhpcy5vcHRpb25z
LmN1ckFuaW1bZV0hPT10cnVlKWQ9ZmFsc2U7aWYoZCl7aWYodGhpcy5vcHRpb25zLm92ZXJmbG93
IT1udWxsJiYhYy5zdXBwb3J0LnNocmlua1dyYXBCbG9ja3Mpe3ZhciBmPXRoaXMuZWxlbSxoPXRo
aXMub3B0aW9ucztjLmVhY2goWyIiLCJYIiwiWSJdLGZ1bmN0aW9uKGssbyl7Zi5zdHlsZVsib3Zl
cmZsb3ciK29dPWgub3ZlcmZsb3dba119KX10aGlzLm9wdGlvbnMuaGlkZSYmYyh0aGlzLmVsZW0p
LmhpZGUoKTtpZih0aGlzLm9wdGlvbnMuaGlkZXx8CnRoaXMub3B0aW9ucy5zaG93KWZvcih2YXIg
bCBpbiB0aGlzLm9wdGlvbnMuY3VyQW5pbSljLnN0eWxlKHRoaXMuZWxlbSxsLHRoaXMub3B0aW9u
cy5vcmlnW2xdKTt0aGlzLm9wdGlvbnMuY29tcGxldGUuY2FsbCh0aGlzLmVsZW0pfXJldHVybiBm
YWxzZX1lbHNle2E9Yi10aGlzLnN0YXJ0VGltZTt0aGlzLnN0YXRlPWEvdGhpcy5vcHRpb25zLmR1
cmF0aW9uO2I9dGhpcy5vcHRpb25zLmVhc2luZ3x8KGMuZWFzaW5nLnN3aW5nPyJzd2luZyI6Imxp
bmVhciIpO3RoaXMucG9zPWMuZWFzaW5nW3RoaXMub3B0aW9ucy5zcGVjaWFsRWFzaW5nJiZ0aGlz
Lm9wdGlvbnMuc3BlY2lhbEVhc2luZ1t0aGlzLnByb3BdfHxiXSh0aGlzLnN0YXRlLGEsMCwxLHRo
aXMub3B0aW9ucy5kdXJhdGlvbik7dGhpcy5ub3c9dGhpcy5zdGFydCsodGhpcy5lbmQtdGhpcy5z
dGFydCkqdGhpcy5wb3M7dGhpcy51cGRhdGUoKX1yZXR1cm4gdHJ1ZX19O2MuZXh0ZW5kKGMuZngs
e3RpY2s6ZnVuY3Rpb24oKXtmb3IodmFyIGE9CmMudGltZXJzLGI9MDtiPGEubGVuZ3RoO2IrKylh
W2JdKCl8fGEuc3BsaWNlKGItLSwxKTthLmxlbmd0aHx8Yy5meC5zdG9wKCl9LGludGVydmFsOjEz
LHN0b3A6ZnVuY3Rpb24oKXtjbGVhckludGVydmFsKGJhKTtiYT1udWxsfSxzcGVlZHM6e3Nsb3c6
NjAwLGZhc3Q6MjAwLF9kZWZhdWx0OjQwMH0sc3RlcDp7b3BhY2l0eTpmdW5jdGlvbihhKXtjLnN0
eWxlKGEuZWxlbSwib3BhY2l0eSIsYS5ub3cpfSxfZGVmYXVsdDpmdW5jdGlvbihhKXtpZihhLmVs
ZW0uc3R5bGUmJmEuZWxlbS5zdHlsZVthLnByb3BdIT1udWxsKWEuZWxlbS5zdHlsZVthLnByb3Bd
PShhLnByb3A9PT0id2lkdGgifHxhLnByb3A9PT0iaGVpZ2h0Ij9NYXRoLm1heCgwLGEubm93KTph
Lm5vdykrYS51bml0O2Vsc2UgYS5lbGVtW2EucHJvcF09YS5ub3d9fX0pO2lmKGMuZXhwciYmYy5l
eHByLmZpbHRlcnMpYy5leHByLmZpbHRlcnMuYW5pbWF0ZWQ9ZnVuY3Rpb24oYSl7cmV0dXJuIGMu
Z3JlcChjLnRpbWVycyxmdW5jdGlvbihiKXtyZXR1cm4gYT09PQpiLmVsZW19KS5sZW5ndGh9O3Zh
ciB4Yj0vXnQoPzphYmxlfGR8aCkkL2ksSWE9L14oPzpib2R5fGh0bWwpJC9pO2MuZm4ub2Zmc2V0
PSJnZXRCb3VuZGluZ0NsaWVudFJlY3QiaW4gdC5kb2N1bWVudEVsZW1lbnQ/ZnVuY3Rpb24oYSl7
dmFyIGI9dGhpc1swXSxkO2lmKGEpcmV0dXJuIHRoaXMuZWFjaChmdW5jdGlvbihsKXtjLm9mZnNl
dC5zZXRPZmZzZXQodGhpcyxhLGwpfSk7aWYoIWJ8fCFiLm93bmVyRG9jdW1lbnQpcmV0dXJuIG51
bGw7aWYoYj09PWIub3duZXJEb2N1bWVudC5ib2R5KXJldHVybiBjLm9mZnNldC5ib2R5T2Zmc2V0
KGIpO3RyeXtkPWIuZ2V0Qm91bmRpbmdDbGllbnRSZWN0KCl9Y2F0Y2goZSl7fXZhciBmPWIub3du
ZXJEb2N1bWVudCxoPWYuZG9jdW1lbnRFbGVtZW50O2lmKCFkfHwhYy5jb250YWlucyhoLGIpKXJl
dHVybiBkfHx7dG9wOjAsbGVmdDowfTtiPWYuYm9keTtmPWZhKGYpO3JldHVybnt0b3A6ZC50b3Ar
KGYucGFnZVlPZmZzZXR8fGMuc3VwcG9ydC5ib3hNb2RlbCYmCmguc2Nyb2xsVG9wfHxiLnNjcm9s
bFRvcCktKGguY2xpZW50VG9wfHxiLmNsaWVudFRvcHx8MCksbGVmdDpkLmxlZnQrKGYucGFnZVhP
ZmZzZXR8fGMuc3VwcG9ydC5ib3hNb2RlbCYmaC5zY3JvbGxMZWZ0fHxiLnNjcm9sbExlZnQpLSho
LmNsaWVudExlZnR8fGIuY2xpZW50TGVmdHx8MCl9fTpmdW5jdGlvbihhKXt2YXIgYj10aGlzWzBd
O2lmKGEpcmV0dXJuIHRoaXMuZWFjaChmdW5jdGlvbih4KXtjLm9mZnNldC5zZXRPZmZzZXQodGhp
cyxhLHgpfSk7aWYoIWJ8fCFiLm93bmVyRG9jdW1lbnQpcmV0dXJuIG51bGw7aWYoYj09PWIub3du
ZXJEb2N1bWVudC5ib2R5KXJldHVybiBjLm9mZnNldC5ib2R5T2Zmc2V0KGIpO2Mub2Zmc2V0Lmlu
aXRpYWxpemUoKTt2YXIgZCxlPWIub2Zmc2V0UGFyZW50LGY9Yi5vd25lckRvY3VtZW50LGg9Zi5k
b2N1bWVudEVsZW1lbnQsbD1mLmJvZHk7ZD0oZj1mLmRlZmF1bHRWaWV3KT9mLmdldENvbXB1dGVk
U3R5bGUoYixudWxsKTpiLmN1cnJlbnRTdHlsZTsKZm9yKHZhciBrPWIub2Zmc2V0VG9wLG89Yi5v
ZmZzZXRMZWZ0OyhiPWIucGFyZW50Tm9kZSkmJmIhPT1sJiZiIT09aDspe2lmKGMub2Zmc2V0LnN1
cHBvcnRzRml4ZWRQb3NpdGlvbiYmZC5wb3NpdGlvbj09PSJmaXhlZCIpYnJlYWs7ZD1mP2YuZ2V0
Q29tcHV0ZWRTdHlsZShiLG51bGwpOmIuY3VycmVudFN0eWxlO2stPWIuc2Nyb2xsVG9wO28tPWIu
c2Nyb2xsTGVmdDtpZihiPT09ZSl7ays9Yi5vZmZzZXRUb3A7bys9Yi5vZmZzZXRMZWZ0O2lmKGMu
b2Zmc2V0LmRvZXNOb3RBZGRCb3JkZXImJiEoYy5vZmZzZXQuZG9lc0FkZEJvcmRlckZvclRhYmxl
QW5kQ2VsbHMmJnhiLnRlc3QoYi5ub2RlTmFtZSkpKXtrKz1wYXJzZUZsb2F0KGQuYm9yZGVyVG9w
V2lkdGgpfHwwO28rPXBhcnNlRmxvYXQoZC5ib3JkZXJMZWZ0V2lkdGgpfHwwfWU9Yi5vZmZzZXRQ
YXJlbnR9aWYoYy5vZmZzZXQuc3VidHJhY3RzQm9yZGVyRm9yT3ZlcmZsb3dOb3RWaXNpYmxlJiZk
Lm92ZXJmbG93IT09InZpc2libGUiKXtrKz0KcGFyc2VGbG9hdChkLmJvcmRlclRvcFdpZHRoKXx8
MDtvKz1wYXJzZUZsb2F0KGQuYm9yZGVyTGVmdFdpZHRoKXx8MH1kPWR9aWYoZC5wb3NpdGlvbj09
PSJyZWxhdGl2ZSJ8fGQucG9zaXRpb249PT0ic3RhdGljIil7ays9bC5vZmZzZXRUb3A7bys9bC5v
ZmZzZXRMZWZ0fWlmKGMub2Zmc2V0LnN1cHBvcnRzRml4ZWRQb3NpdGlvbiYmZC5wb3NpdGlvbj09
PSJmaXhlZCIpe2srPU1hdGgubWF4KGguc2Nyb2xsVG9wLGwuc2Nyb2xsVG9wKTtvKz1NYXRoLm1h
eChoLnNjcm9sbExlZnQsbC5zY3JvbGxMZWZ0KX1yZXR1cm57dG9wOmssbGVmdDpvfX07Yy5vZmZz
ZXQ9e2luaXRpYWxpemU6ZnVuY3Rpb24oKXt2YXIgYT10LmJvZHksYj10LmNyZWF0ZUVsZW1lbnQo
ImRpdiIpLGQsZSxmLGg9cGFyc2VGbG9hdChjLmNzcyhhLCJtYXJnaW5Ub3AiKSl8fDA7Yy5leHRl
bmQoYi5zdHlsZSx7cG9zaXRpb246ImFic29sdXRlIix0b3A6MCxsZWZ0OjAsbWFyZ2luOjAsYm9y
ZGVyOjAsd2lkdGg6IjFweCIsCmhlaWdodDoiMXB4Iix2aXNpYmlsaXR5OiJoaWRkZW4ifSk7Yi5p
bm5lckhUTUw9IjxkaXYgc3R5bGU9J3Bvc2l0aW9uOmFic29sdXRlO3RvcDowO2xlZnQ6MDttYXJn
aW46MDtib3JkZXI6NXB4IHNvbGlkICMwMDA7cGFkZGluZzowO3dpZHRoOjFweDtoZWlnaHQ6MXB4
Oyc+PGRpdj48L2Rpdj48L2Rpdj48dGFibGUgc3R5bGU9J3Bvc2l0aW9uOmFic29sdXRlO3RvcDow
O2xlZnQ6MDttYXJnaW46MDtib3JkZXI6NXB4IHNvbGlkICMwMDA7cGFkZGluZzowO3dpZHRoOjFw
eDtoZWlnaHQ6MXB4OycgY2VsbHBhZGRpbmc9JzAnIGNlbGxzcGFjaW5nPScwJz48dHI+PHRkPjwv
dGQ+PC90cj48L3RhYmxlPiI7YS5pbnNlcnRCZWZvcmUoYixhLmZpcnN0Q2hpbGQpO2Q9Yi5maXJz
dENoaWxkO2U9ZC5maXJzdENoaWxkO2Y9ZC5uZXh0U2libGluZy5maXJzdENoaWxkLmZpcnN0Q2hp
bGQ7dGhpcy5kb2VzTm90QWRkQm9yZGVyPWUub2Zmc2V0VG9wIT09NTt0aGlzLmRvZXNBZGRCb3Jk
ZXJGb3JUYWJsZUFuZENlbGxzPQpmLm9mZnNldFRvcD09PTU7ZS5zdHlsZS5wb3NpdGlvbj0iZml4
ZWQiO2Uuc3R5bGUudG9wPSIyMHB4Ijt0aGlzLnN1cHBvcnRzRml4ZWRQb3NpdGlvbj1lLm9mZnNl
dFRvcD09PTIwfHxlLm9mZnNldFRvcD09PTE1O2Uuc3R5bGUucG9zaXRpb249ZS5zdHlsZS50b3A9
IiI7ZC5zdHlsZS5vdmVyZmxvdz0iaGlkZGVuIjtkLnN0eWxlLnBvc2l0aW9uPSJyZWxhdGl2ZSI7
dGhpcy5zdWJ0cmFjdHNCb3JkZXJGb3JPdmVyZmxvd05vdFZpc2libGU9ZS5vZmZzZXRUb3A9PT0t
NTt0aGlzLmRvZXNOb3RJbmNsdWRlTWFyZ2luSW5Cb2R5T2Zmc2V0PWEub2Zmc2V0VG9wIT09aDth
LnJlbW92ZUNoaWxkKGIpO2Mub2Zmc2V0LmluaXRpYWxpemU9Yy5ub29wfSxib2R5T2Zmc2V0OmZ1
bmN0aW9uKGEpe3ZhciBiPWEub2Zmc2V0VG9wLGQ9YS5vZmZzZXRMZWZ0O2Mub2Zmc2V0LmluaXRp
YWxpemUoKTtpZihjLm9mZnNldC5kb2VzTm90SW5jbHVkZU1hcmdpbkluQm9keU9mZnNldCl7Yis9
cGFyc2VGbG9hdChjLmNzcyhhLAoibWFyZ2luVG9wIikpfHwwO2QrPXBhcnNlRmxvYXQoYy5jc3Mo
YSwibWFyZ2luTGVmdCIpKXx8MH1yZXR1cm57dG9wOmIsbGVmdDpkfX0sc2V0T2Zmc2V0OmZ1bmN0
aW9uKGEsYixkKXt2YXIgZT1jLmNzcyhhLCJwb3NpdGlvbiIpO2lmKGU9PT0ic3RhdGljIilhLnN0
eWxlLnBvc2l0aW9uPSJyZWxhdGl2ZSI7dmFyIGY9YyhhKSxoPWYub2Zmc2V0KCksbD1jLmNzcyhh
LCJ0b3AiKSxrPWMuY3NzKGEsImxlZnQiKSxvPWU9PT0iYWJzb2x1dGUiJiZjLmluQXJyYXkoImF1
dG8iLFtsLGtdKT4tMTtlPXt9O3ZhciB4PXt9O2lmKG8peD1mLnBvc2l0aW9uKCk7bD1vP3gudG9w
OnBhcnNlSW50KGwsMTApfHwwO2s9bz94LmxlZnQ6cGFyc2VJbnQoaywxMCl8fDA7aWYoYy5pc0Z1
bmN0aW9uKGIpKWI9Yi5jYWxsKGEsZCxoKTtpZihiLnRvcCE9bnVsbCllLnRvcD1iLnRvcC1oLnRv
cCtsO2lmKGIubGVmdCE9bnVsbCllLmxlZnQ9Yi5sZWZ0LWgubGVmdCtrOyJ1c2luZyJpbiBiP2Iu
dXNpbmcuY2FsbChhLAplKTpmLmNzcyhlKX19O2MuZm4uZXh0ZW5kKHtwb3NpdGlvbjpmdW5jdGlv
bigpe2lmKCF0aGlzWzBdKXJldHVybiBudWxsO3ZhciBhPXRoaXNbMF0sYj10aGlzLm9mZnNldFBh
cmVudCgpLGQ9dGhpcy5vZmZzZXQoKSxlPUlhLnRlc3QoYlswXS5ub2RlTmFtZSk/e3RvcDowLGxl
ZnQ6MH06Yi5vZmZzZXQoKTtkLnRvcC09cGFyc2VGbG9hdChjLmNzcyhhLCJtYXJnaW5Ub3AiKSl8
fDA7ZC5sZWZ0LT1wYXJzZUZsb2F0KGMuY3NzKGEsIm1hcmdpbkxlZnQiKSl8fDA7ZS50b3ArPXBh
cnNlRmxvYXQoYy5jc3MoYlswXSwiYm9yZGVyVG9wV2lkdGgiKSl8fDA7ZS5sZWZ0Kz1wYXJzZUZs
b2F0KGMuY3NzKGJbMF0sImJvcmRlckxlZnRXaWR0aCIpKXx8MDtyZXR1cm57dG9wOmQudG9wLWUu
dG9wLGxlZnQ6ZC5sZWZ0LWUubGVmdH19LG9mZnNldFBhcmVudDpmdW5jdGlvbigpe3JldHVybiB0
aGlzLm1hcChmdW5jdGlvbigpe2Zvcih2YXIgYT10aGlzLm9mZnNldFBhcmVudHx8dC5ib2R5O2Em
JiFJYS50ZXN0KGEubm9kZU5hbWUpJiYKYy5jc3MoYSwicG9zaXRpb24iKT09PSJzdGF0aWMiOylh
PWEub2Zmc2V0UGFyZW50O3JldHVybiBhfSl9fSk7Yy5lYWNoKFsiTGVmdCIsIlRvcCJdLGZ1bmN0
aW9uKGEsYil7dmFyIGQ9InNjcm9sbCIrYjtjLmZuW2RdPWZ1bmN0aW9uKGUpe3ZhciBmPXRoaXNb
MF0saDtpZighZilyZXR1cm4gbnVsbDtpZihlIT09QilyZXR1cm4gdGhpcy5lYWNoKGZ1bmN0aW9u
KCl7aWYoaD1mYSh0aGlzKSloLnNjcm9sbFRvKCFhP2U6YyhoKS5zY3JvbGxMZWZ0KCksYT9lOmMo
aCkuc2Nyb2xsVG9wKCkpO2Vsc2UgdGhpc1tkXT1lfSk7ZWxzZSByZXR1cm4oaD1mYShmKSk/InBh
Z2VYT2Zmc2V0ImluIGg/aFthPyJwYWdlWU9mZnNldCI6InBhZ2VYT2Zmc2V0Il06Yy5zdXBwb3J0
LmJveE1vZGVsJiZoLmRvY3VtZW50LmRvY3VtZW50RWxlbWVudFtkXXx8aC5kb2N1bWVudC5ib2R5
W2RdOmZbZF19fSk7Yy5lYWNoKFsiSGVpZ2h0IiwiV2lkdGgiXSxmdW5jdGlvbihhLGIpe3ZhciBk
PWIudG9Mb3dlckNhc2UoKTsKYy5mblsiaW5uZXIiK2JdPWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXNb
MF0/cGFyc2VGbG9hdChjLmNzcyh0aGlzWzBdLGQsInBhZGRpbmciKSk6bnVsbH07Yy5mblsib3V0
ZXIiK2JdPWZ1bmN0aW9uKGUpe3JldHVybiB0aGlzWzBdP3BhcnNlRmxvYXQoYy5jc3ModGhpc1sw
XSxkLGU/Im1hcmdpbiI6ImJvcmRlciIpKTpudWxsfTtjLmZuW2RdPWZ1bmN0aW9uKGUpe3ZhciBm
PXRoaXNbMF07aWYoIWYpcmV0dXJuIGU9PW51bGw/bnVsbDp0aGlzO2lmKGMuaXNGdW5jdGlvbihl
KSlyZXR1cm4gdGhpcy5lYWNoKGZ1bmN0aW9uKGwpe3ZhciBrPWModGhpcyk7a1tkXShlLmNhbGwo
dGhpcyxsLGtbZF0oKSkpfSk7aWYoYy5pc1dpbmRvdyhmKSlyZXR1cm4gZi5kb2N1bWVudC5jb21w
YXRNb2RlPT09IkNTUzFDb21wYXQiJiZmLmRvY3VtZW50LmRvY3VtZW50RWxlbWVudFsiY2xpZW50
IitiXXx8Zi5kb2N1bWVudC5ib2R5WyJjbGllbnQiK2JdO2Vsc2UgaWYoZi5ub2RlVHlwZT09PTkp
cmV0dXJuIE1hdGgubWF4KGYuZG9jdW1lbnRFbGVtZW50WyJjbGllbnQiKwpiXSxmLmJvZHlbInNj
cm9sbCIrYl0sZi5kb2N1bWVudEVsZW1lbnRbInNjcm9sbCIrYl0sZi5ib2R5WyJvZmZzZXQiK2Jd
LGYuZG9jdW1lbnRFbGVtZW50WyJvZmZzZXQiK2JdKTtlbHNlIGlmKGU9PT1CKXtmPWMuY3NzKGYs
ZCk7dmFyIGg9cGFyc2VGbG9hdChmKTtyZXR1cm4gYy5pc05hTihoKT9mOmh9ZWxzZSByZXR1cm4g
dGhpcy5jc3MoZCx0eXBlb2YgZT09PSJzdHJpbmciP2U6ZSsicHgiKX19KX0pKHdpbmRvdyk7Cg==

@@ js/lang-apollo.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJjb20iLC9eI1te
XHJcbl0qLyxudWxsLCIjIl0sWyJwbG4iLC9eW1x0XG5cciBceEEwXSsvLG51bGwsIlx0XG5cciBc
dTAwYTAiXSxbInN0ciIsL15cIig/OlteXCJcXF18XFxbXHNcU10pKig/OlwifCQpLyxudWxsLCci
J11dLFtbImt3ZCIsL14oPzpBRFN8QUR8QVVHfEJaRnxCWk1GfENBRXxDQUZ8Q0F8Q0NTfENPTXxD
U3xEQVN8RENBfERDT018RENTfERET1VCTHxESU18RE9VQkxFfERUQ0J8RFRDRnxEVnxEWENIfEVE
UlVQVHxFWFRFTkR8SU5DUnxJTkRFWHxORFh8SU5ISU5UfExYQ0h8TUFTS3xNU0t8TVB8TVNVfE5P
T1B8T1ZTS3xRWENIfFJBTkR8UkVBRHxSRUxJTlR8UkVTVU1FfFJFVFVSTnxST1J8UlhPUnxTUVVB
UkV8U1V8VENSfFRDQUF8T1ZTS3xUQ0Z8VEN8VFN8V0FORHxXT1J8V1JJVEV8WENIfFhMUXxYWEFM
UXxaTHxaUXxBRER8QURafFNVQnxTVVp8TVBZfE1QUnxNUFp8RFZQfENPTXxBQlN8Q0xBfENMWnxM
RFF8U1RPfFNUUXxBTFN8TExTfExSU3xUUkF8VFNRfFRNSXxUT1Z8QVhUfFRJWHxETFl8SU5QfE9V
VClccy8sCm51bGxdLFsidHlwIiwvXig/Oi0/R0VOQURSfD1NSU5VU3wyQkNBRFJ8Vk58Qk9GfE1N
fC0/MkNBRFJ8LT9bMS02XUROQURSfEFEUkVTfEJCQ09OfFtTRV0/QkFOS1w9P3xCTE9DS3xCTktT
VU18RT9DQURSfENPVU5UXCo/fDI/REVDXCo/fC0/RE5DSEFOfC0/RE5QVFJ8RVFVQUxTfEVSQVNF
fE1FTU9SWXwyP09DVHxSRU1BRFJ8U0VUTE9DfFNVQlJPfE9SR3xCU1N8QkVTfFNZTnxFUVV8REVG
SU5FfEVORClccy8sbnVsbF0sWyJsaXQiLC9eXCcoPzotKig/Olx3fFxcW1x4MjEtXHg3ZV0pKD86
W1x3LV0qfFxcW1x4MjEtXHg3ZV0pWz0hP10/KT8vXSxbInBsbiIsL14tKig/OlshLXpfXXxcXFtc
eDIxLVx4N2VdKSg/Oltcdy1dKnxcXFtceDIxLVx4N2VdKVs9IT9dPy9pXSxbInB1biIsL15bXlx3
XHRcblxyIFx4QTAoKVwiXFxcJztdKy9dXSksWyJhcG9sbG8iLCJhZ2MiLCJhZWEiXSk=

@@ js/lang-css.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwbG4iLC9eWyBc
dFxyXG5cZl0rLyxudWxsLCIgXHRcclxuXHUwMDBjIl1dLFtbInN0ciIsL15cIig/OlteXG5cclxm
XFxcIl18XFwoPzpcclxuP3xcbnxcZil8XFxbXHNcU10pKlwiLyxudWxsXSxbInN0ciIsL15cJyg/
OlteXG5cclxmXFxcJ118XFwoPzpcclxuP3xcbnxcZil8XFxbXHNcU10pKlwnLyxudWxsXSxbImxh
bmctY3NzLXN0ciIsL151cmxcKChbXlwpXCJcJ10qKVwpL2ldLFsia3dkIiwvXig/OnVybHxyZ2J8
XCFpbXBvcnRhbnR8QGltcG9ydHxAcGFnZXxAbWVkaWF8QGNoYXJzZXR8aW5oZXJpdCkoPz1bXlwt
XHddfCQpL2ksbnVsbF0sWyJsYW5nLWNzcy1rdyIsL14oLT8oPzpbX2Etel18KD86XFxbMC05YS1m
XSsgPykpKD86W19hLXowLTlcLV18XFwoPzpcXFswLTlhLWZdKyA/KSkqKVxzKjovaV0sWyJjb20i
LC9eXC9cKlteKl0qXCorKD86W15cLypdW14qXSpcKispKlwvL10sClsiY29tIiwvXig/OjwhLS18
LS1cPikvXSxbImxpdCIsL14oPzpcZCt8XGQqXC5cZCspKD86JXxbYS16XSspPy9pXSxbImxpdCIs
L14jKD86WzAtOWEtZl17M30pezEsMn0vaV0sWyJwbG4iLC9eLT8oPzpbX2Etel18KD86XFxbXGRh
LWZdKyA/KSkoPzpbX2EtelxkXC1dfFxcKD86XFxbXGRhLWZdKyA/KSkqL2ldLFsicHVuIiwvXlte
XHNcd1wnXCJdKy9dXSksWyJjc3MiXSk7UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVT
aW1wbGVMZXhlcihbXSxbWyJrd2QiLC9eLT8oPzpbX2Etel18KD86XFxbXGRhLWZdKyA/KSkoPzpb
X2EtelxkXC1dfFxcKD86XFxbXGRhLWZdKyA/KSkqL2ldXSksWyJjc3Mta3ciXSk7UFIucmVnaXN0
ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbXSxbWyJzdHIiLC9eW15cKVwiXCdd
Ky9dXSksWyJjc3Mtc3RyIl0p

@@ js/lang-hs.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwbG4iLC9eW1x0
XG5ceDBCXHgwQ1xyIF0rLyxudWxsLCJcdFxuXHUwMDBiXHUwMDBjXHIgIl0sWyJzdHIiLC9eXCIo
PzpbXlwiXFxcblx4MENccl18XFxbXHNcU10pKig/OlwifCQpLyxudWxsLCciJ10sWyJzdHIiLC9e
XCcoPzpbXlwnXFxcblx4MENccl18XFxbXiZdKVwnPy8sbnVsbCwiJyJdLFsibGl0IiwvXig/OjBv
WzAtN10rfDB4W1xkYS1mXSt8XGQrKD86XC5cZCspPyg/OmVbK1wtXT9cZCspPykvaSxudWxsLCIw
MTIzNDU2Nzg5Il1dLFtbImNvbSIsL14oPzooPzotLSsoPzpbXlxyXG5ceDBDXSopPyl8KD86XHst
KD86W14tXXwtK1teLVx9XSkqLVx9KSkvXSxbImt3ZCIsL14oPzpjYXNlfGNsYXNzfGRhdGF8ZGVm
YXVsdHxkZXJpdmluZ3xkb3xlbHNlfGlmfGltcG9ydHxpbnxpbmZpeHxpbmZpeGx8aW5maXhyfGlu
c3RhbmNlfGxldHxtb2R1bGV8bmV3dHlwZXxvZnx0aGVufHR5cGV8d2hlcmV8XykoPz1bXmEtekEt
WjAtOVwnXXwkKS8sCm51bGxdLFsicGxuIiwvXig/OltBLVpdW1x3XCddKlwuKSpbYS16QS1aXVtc
d1wnXSovXSxbInB1biIsL15bXlx0XG5ceDBCXHgwQ1xyIGEtekEtWjAtOVwnXCJdKy9dXSksWyJo
cyJdKQ==

@@ js/lang-lisp.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJvcG4iLC9eXCgv
LG51bGwsIigiXSxbImNsbyIsL15cKS8sbnVsbCwiKSJdLFsiY29tIiwvXjtbXlxyXG5dKi8sbnVs
bCwiOyJdLFsicGxuIiwvXltcdFxuXHIgXHhBMF0rLyxudWxsLCJcdFxuXHIgXHUwMGEwIl0sWyJz
dHIiLC9eXCIoPzpbXlwiXFxdfFxcW1xzXFNdKSooPzpcInwkKS8sbnVsbCwnIiddXSxbWyJrd2Qi
LC9eKD86YmxvY2t8Y1thZF0rcnxjYXRjaHxjb25bZHNdfGRlZig/OmluZXx1bil8ZG98ZXF8ZXFs
fGVxdWFsfGVxdWFscHxldmFsLXdoZW58ZmxldHxmb3JtYXR8Z298aWZ8bGFiZWxzfGxhbWJkYXxs
ZXR8bG9hZC10aW1lLXZhbHVlfGxvY2FsbHl8bWFjcm9sZXR8bXVsdGlwbGUtdmFsdWUtY2FsbHxu
aWx8cHJvZ258cHJvZ3Z8cXVvdGV8cmVxdWlyZXxyZXR1cm4tZnJvbXxzZXRxfHN5bWJvbC1tYWNy
b2xldHx0fHRhZ2JvZHl8dGhlfHRocm93fHVud2luZClcYi8sCm51bGxdLFsibGl0IiwvXlsrXC1d
Pyg/OjB4WzAtOWEtZl0rfFxkK1wvXGQrfCg/OlwuXGQrfFxkKyg/OlwuXGQqKT8pKD86W2VkXVsr
XC1dP1xkKyk/KS9pXSxbImxpdCIsL15cJyg/Oi0qKD86XHd8XFxbXHgyMS1ceDdlXSkoPzpbXHct
XSp8XFxbXHgyMS1ceDdlXSlbPSE/XT8pPy9dLFsicGxuIiwvXi0qKD86W2Etel9dfFxcW1x4MjEt
XHg3ZV0pKD86W1x3LV0qfFxcW1x4MjEtXHg3ZV0pWz0hP10/L2ldLFsicHVuIiwvXlteXHdcdFxu
XHIgXHhBMCgpXCJcXFwnO10rL11dKSxbImNsIiwiZWwiLCJsaXNwIiwic2NtIl0p

@@ js/lang-lua.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwbG4iLC9eW1x0
XG5cciBceEEwXSsvLG51bGwsIlx0XG5cciBcdTAwYTAiXSxbInN0ciIsL14oPzpcIig/OlteXCJc
XF18XFxbXHNcU10pKig/OlwifCQpfFwnKD86W15cJ1xcXXxcXFtcc1xTXSkqKD86XCd8JCkpLyxu
dWxsLCJcIiciXV0sW1siY29tIiwvXi0tKD86XFsoPSopXFtbXHNcU10qPyg/OlxdXDFcXXwkKXxb
XlxyXG5dKikvXSxbInN0ciIsL15cWyg9KilcW1tcc1xTXSo/KD86XF1cMVxdfCQpL10sWyJrd2Qi
LC9eKD86YW5kfGJyZWFrfGRvfGVsc2V8ZWxzZWlmfGVuZHxmYWxzZXxmb3J8ZnVuY3Rpb258aWZ8
aW58bG9jYWx8bmlsfG5vdHxvcnxyZXBlYXR8cmV0dXJufHRoZW58dHJ1ZXx1bnRpbHx3aGlsZSlc
Yi8sbnVsbF0sWyJsaXQiLC9eWystXT8oPzoweFtcZGEtZl0rfCg/Oig/OlwuXGQrfFxkKyg/Olwu
XGQqKT8pKD86ZVsrXC1dP1xkKyk/KSkvaV0sClsicGxuIiwvXlthLXpfXVx3Ki9pXSxbInB1biIs
L15bXlx3XHRcblxyIFx4QTBdW15cd1x0XG5cciBceEEwXCJcJ1wtXCs9XSovXV0pLFsibHVhIl0p

@@ js/lang-ml.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwbG4iLC9eW1x0
XG5cciBceEEwXSsvLG51bGwsIlx0XG5cciBcdTAwYTAiXSxbImNvbSIsL14jKD86aWZbXHRcblxy
IFx4QTBdKyg/OlthLXpfJF1bXHdcJ10qfGBgW15cclxuXHRgXSooPzpgYHwkKSl8ZWxzZXxlbmRp
ZnxsaWdodCkvaSxudWxsLCIjIl0sWyJzdHIiLC9eKD86XCIoPzpbXlwiXFxdfFxcW1xzXFNdKSoo
PzpcInwkKXxcJyg/OlteXCdcXF18XFxbXHNcU10pKig/OlwnfCQpKS8sbnVsbCwiXCInIl1dLFtb
ImNvbSIsL14oPzpcL1wvW15cclxuXSp8XChcKltcc1xTXSo/XCpcKSkvXSxbImt3ZCIsL14oPzph
YnN0cmFjdHxhbmR8YXN8YXNzZXJ0fGJlZ2lufGNsYXNzfGRlZmF1bHR8ZGVsZWdhdGV8ZG98ZG9u
ZXxkb3duY2FzdHxkb3dudG98ZWxpZnxlbHNlfGVuZHxleGNlcHRpb258ZXh0ZXJufGZhbHNlfGZp
bmFsbHl8Zm9yfGZ1bnxmdW5jdGlvbnxpZnxpbnxpbmhlcml0fGlubGluZXxpbnRlcmZhY2V8aW50
ZXJuYWx8bGF6eXxsZXR8bWF0Y2h8bWVtYmVyfG1vZHVsZXxtdXRhYmxlfG5hbWVzcGFjZXxuZXd8
bnVsbHxvZnxvcGVufG9yfG92ZXJyaWRlfHByaXZhdGV8cHVibGljfHJlY3xyZXR1cm58c3RhdGlj
fHN0cnVjdHx0aGVufHRvfHRydWV8dHJ5fHR5cGV8dXBjYXN0fHVzZXx2YWx8dm9pZHx3aGVufHdo
aWxlfHdpdGh8eWllbGR8YXNyfGxhbmR8bG9yfGxzbHxsc3J8bHhvcnxtb2R8c2lnfGF0b21pY3xi
cmVha3xjaGVja2VkfGNvbXBvbmVudHxjb25zdHxjb25zdHJhaW50fGNvbnN0cnVjdG9yfGNvbnRp
bnVlfGVhZ2VyfGV2ZW50fGV4dGVybmFsfGZpeGVkfGZ1bmN0b3J8Z2xvYmFsfGluY2x1ZGV8bWV0
aG9kfG1peGlufG9iamVjdHxwYXJhbGxlbHxwcm9jZXNzfHByb3RlY3RlZHxwdXJlfHNlYWxlZHx0
cmFpdHx2aXJ0dWFsfHZvbGF0aWxlKVxiL10sClsibGl0IiwvXlsrXC1dPyg/OjB4W1xkYS1mXSt8
KD86KD86XC5cZCt8XGQrKD86XC5cZCopPykoPzplWytcLV0/XGQrKT8pKS9pXSxbInBsbiIsL14o
PzpbYS16X11cdypbIT8jXT98YGBbXlxyXG5cdGBdKig/OmBgfCQpKS9pXSxbInB1biIsL15bXlx0
XG5cciBceEEwXCJcJ1x3XSsvXV0pLFsiZnMiLCJtbCJdKQ==

@@ js/lang-proto.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5zb3VyY2VEZWNvcmF0b3Ioe2tleXdvcmRzOiJib29s
IGJ5dGVzIGRlZmF1bHQgZG91YmxlIGVudW0gZXh0ZW5kIGV4dGVuc2lvbnMgZmFsc2UgZml4ZWQz
MiBmaXhlZDY0IGZsb2F0IGdyb3VwIGltcG9ydCBpbnQzMiBpbnQ2NCBtYXggbWVzc2FnZSBvcHRp
b24gb3B0aW9uYWwgcGFja2FnZSByZXBlYXRlZCByZXF1aXJlZCByZXR1cm5zIHJwYyBzZXJ2aWNl
IHNmaXhlZDMyIHNmaXhlZDY0IHNpbnQzMiBzaW50NjQgc3RyaW5nIHN5bnRheCB0byB0cnVlIHVp
bnQzMiB1aW50NjQiLGNTdHlsZUNvbW1lbnRzOnRydWV9KSxbInByb3RvIl0p

@@ js/lang-scala.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwbG4iLC9eW1x0
XG5cciBceEEwXSsvLG51bGwsIlx0XG5cciBcdTAwYTAiXSxbInN0ciIsL14oPzoiKD86KD86IiIo
PzoiIj8oPyEiKXxbXlxcIl18XFwuKSoiezAsM30pfCg/OlteIlxyXG5cXF18XFwuKSoiPykpLyxu
dWxsLCciJ10sWyJsaXQiLC9eYCg/OlteXHJcblxcYF18XFwuKSpgPy8sbnVsbCwiYCJdLFsicHVu
IiwvXlshIyUmKCkqKyxcLTo7PD0+P0BcW1xcXF1ee3x9fl0rLyxudWxsLCIhIyUmKCkqKywtOjs8
PT4/QFtcXF1ee3x9fiJdXSxbWyJzdHIiLC9eJyg/OlteXHJcblxcJ118XFwoPzonfFteXHJcbidd
KykpJy9dLFsibGl0IiwvXidbYS16QS1aXyRdW1x3JF0qKD8hWyckXHddKS9dLFsia3dkIiwvXig/
OmFic3RyYWN0fGNhc2V8Y2F0Y2h8Y2xhc3N8ZGVmfGRvfGVsc2V8ZXh0ZW5kc3xmaW5hbHxmaW5h
bGx5fGZvcnxmb3JTb21lfGlmfGltcGxpY2l0fGltcG9ydHxsYXp5fG1hdGNofG5ld3xvYmplY3R8
b3ZlcnJpZGV8cGFja2FnZXxwcml2YXRlfHByb3RlY3RlZHxyZXF1aXJlc3xyZXR1cm58c2VhbGVk
fHN1cGVyfHRocm93fHRyYWl0fHRyeXx0eXBlfHZhbHx2YXJ8d2hpbGV8d2l0aHx5aWVsZClcYi9d
LApbImxpdCIsL14oPzp0cnVlfGZhbHNlfG51bGx8dGhpcylcYi9dLFsibGl0IiwvXig/Oig/OjAo
PzpbMC03XSt8WFswLTlBLUZdKykpTD98KD86KD86MHxbMS05XVswLTldKikoPzooPzpcLlswLTld
Kyk/KD86RVsrXC1dP1swLTldKyk/Rj98TD8pKXxcXC5bMC05XSsoPzpFWytcLV0/WzAtOV0rKT9G
PykvaV0sWyJ0eXAiLC9eWyRfXSpbQS1aXVtfJEEtWjAtOV0qW2Etel1bXHckXSovXSxbInBsbiIs
L15bJGEtekEtWl9dW1x3JF0qL10sWyJjb20iLC9eXC8oPzpcLy4qfFwqKD86XC98XCoqW14qL10p
Kig/OlwqK1wvPyk/KS9dLFsicHVuIiwvXig/OlwuK3xcLykvXV0pLFsic2NhbGEiXSk=

@@ js/lang-sql.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwbG4iLC9eW1x0
XG5cciBceEEwXSsvLG51bGwsIlx0XG5cciBcdTAwYTAiXSxbInN0ciIsL14oPzoiKD86W15cIlxc
XXxcXC4pKiJ8Jyg/OlteXCdcXF18XFwuKSonKS8sbnVsbCwiXCInIl1dLFtbImNvbSIsL14oPzot
LVteXHJcbl0qfFwvXCpbXHNcU10qPyg/OlwqXC98JCkpL10sWyJrd2QiLC9eKD86QUREfEFMTHxB
TFRFUnxBTkR8QU5ZfEFTfEFTQ3xBVVRIT1JJWkFUSU9OfEJBQ0tVUHxCRUdJTnxCRVRXRUVOfEJS
RUFLfEJST1dTRXxCVUxLfEJZfENBU0NBREV8Q0FTRXxDSEVDS3xDSEVDS1BPSU5UfENMT1NFfENM
VVNURVJFRHxDT0FMRVNDRXxDT0xMQVRFfENPTFVNTnxDT01NSVR8Q09NUFVURXxDT05TVFJBSU5U
fENPTlRBSU5TfENPTlRBSU5TVEFCTEV8Q09OVElOVUV8Q09OVkVSVHxDUkVBVEV8Q1JPU1N8Q1VS
UkVOVHxDVVJSRU5UX0RBVEV8Q1VSUkVOVF9USU1FfENVUlJFTlRfVElNRVNUQU1QfENVUlJFTlRf
VVNFUnxDVVJTT1J8REFUQUJBU0V8REJDQ3xERUFMTE9DQVRFfERFQ0xBUkV8REVGQVVMVHxERUxF
VEV8REVOWXxERVNDfERJU0t8RElTVElOQ1R8RElTVFJJQlVURUR8RE9VQkxFfERST1B8RFVNTVl8
RFVNUHxFTFNFfEVORHxFUlJMVkx8RVNDQVBFfEVYQ0VQVHxFWEVDfEVYRUNVVEV8RVhJU1RTfEVY
SVR8RkVUQ0h8RklMRXxGSUxMRkFDVE9SfEZPUnxGT1JFSUdOfEZSRUVURVhUfEZSRUVURVhUVEFC
TEV8RlJPTXxGVUxMfEZVTkNUSU9OfEdPVE98R1JBTlR8R1JPVVB8SEFWSU5HfEhPTERMT0NLfElE
RU5USVRZfElERU5USVRZQ09MfElERU5USVRZX0lOU0VSVHxJRnxJTnxJTkRFWHxJTk5FUnxJTlNF
UlR8SU5URVJTRUNUfElOVE98SVN8Sk9JTnxLRVl8S0lMTHxMRUZUfExJS0V8TElORU5PfExPQUR8
TkFUSU9OQUx8Tk9DSEVDS3xOT05DTFVTVEVSRUR8Tk9UfE5VTEx8TlVMTElGfE9GfE9GRnxPRkZT
RVRTfE9OfE9QRU58T1BFTkRBVEFTT1VSQ0V8T1BFTlFVRVJZfE9QRU5ST1dTRVR8T1BFTlhNTHxP
UFRJT058T1J8T1JERVJ8T1VURVJ8T1ZFUnxQRVJDRU5UfFBMQU58UFJFQ0lTSU9OfFBSSU1BUll8
UFJJTlR8UFJPQ3xQUk9DRURVUkV8UFVCTElDfFJBSVNFUlJPUnxSRUFEfFJFQURURVhUfFJFQ09O
RklHVVJFfFJFRkVSRU5DRVN8UkVQTElDQVRJT058UkVTVE9SRXxSRVNUUklDVHxSRVRVUk58UkVW
T0tFfFJJR0hUfFJPTExCQUNLfFJPV0NPVU5UfFJPV0dVSURDT0x8UlVMRXxTQVZFfFNDSEVNQXxT
RUxFQ1R8U0VTU0lPTl9VU0VSfFNFVHxTRVRVU0VSfFNIVVRET1dOfFNPTUV8U1RBVElTVElDU3xT
WVNURU1fVVNFUnxUQUJMRXxURVhUU0laRXxUSEVOfFRPfFRPUHxUUkFOfFRSQU5TQUNUSU9OfFRS
SUdHRVJ8VFJVTkNBVEV8VFNFUVVBTHxVTklPTnxVTklRVUV8VVBEQVRFfFVQREFURVRFWFR8VVNF
fFVTRVJ8VkFMVUVTfFZBUllJTkd8VklFV3xXQUlURk9SfFdIRU58V0hFUkV8V0hJTEV8V0lUSHxX
UklURVRFWFQpKD89W15cdy1dfCQpL2ksCm51bGxdLFsibGl0IiwvXlsrLV0/KD86MHhbXGRhLWZd
K3woPzooPzpcLlxkK3xcZCsoPzpcLlxkKik/KSg/OmVbK1wtXT9cZCspPykpL2ldLFsicGxuIiwv
XlthLXpfXVtcdy1dKi9pXSxbInB1biIsL15bXlx3XHRcblxyIFx4QTBcIlwnXVteXHdcdFxuXHIg
XHhBMCtcLVwiXCddKi9dXSksWyJzcWwiXSk=

@@ js/lang-vb.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwbG4iLC9eW1x0
XG5cciBceEEwXHUyMDI4XHUyMDI5XSsvLG51bGwsIlx0XG5cciBcdTAwYTBcdTIwMjhcdTIwMjki
XSxbInN0ciIsL14oPzpbXCJcdTIwMUNcdTIwMURdKD86W15cIlx1MjAxQ1x1MjAxRF18W1wiXHUy
MDFDXHUyMDFEXXsyfSkoPzpbXCJcdTIwMUNcdTIwMURdY3wkKXxbXCJcdTIwMUNcdTIwMURdKD86
W15cIlx1MjAxQ1x1MjAxRF18W1wiXHUyMDFDXHUyMDFEXXsyfSkqKD86W1wiXHUyMDFDXHUyMDFE
XXwkKSkvaSxudWxsLCciXHUyMDFjXHUyMDFkJ10sWyJjb20iLC9eW1wnXHUyMDE4XHUyMDE5XVte
XHJcblx1MjAyOFx1MjAyOV0qLyxudWxsLCInXHUyMDE4XHUyMDE5Il1dLFtbImt3ZCIsL14oPzpB
ZGRIYW5kbGVyfEFkZHJlc3NPZnxBbGlhc3xBbmR8QW5kQWxzb3xBbnNpfEFzfEFzc2VtYmx5fEF1
dG98Qm9vbGVhbnxCeVJlZnxCeXRlfEJ5VmFsfENhbGx8Q2FzZXxDYXRjaHxDQm9vbHxDQnl0ZXxD
Q2hhcnxDRGF0ZXxDRGJsfENEZWN8Q2hhcnxDSW50fENsYXNzfENMbmd8Q09ianxDb25zdHxDU2hv
cnR8Q1NuZ3xDU3RyfENUeXBlfERhdGV8RGVjaW1hbHxEZWNsYXJlfERlZmF1bHR8RGVsZWdhdGV8
RGltfERpcmVjdENhc3R8RG98RG91YmxlfEVhY2h8RWxzZXxFbHNlSWZ8RW5kfEVuZElmfEVudW18
RXJhc2V8RXJyb3J8RXZlbnR8RXhpdHxGaW5hbGx5fEZvcnxGcmllbmR8RnVuY3Rpb258R2V0fEdl
dFR5cGV8R29TdWJ8R29Ub3xIYW5kbGVzfElmfEltcGxlbWVudHN8SW1wb3J0c3xJbnxJbmhlcml0
c3xJbnRlZ2VyfEludGVyZmFjZXxJc3xMZXR8TGlifExpa2V8TG9uZ3xMb29wfE1lfE1vZHxNb2R1
bGV8TXVzdEluaGVyaXR8TXVzdE92ZXJyaWRlfE15QmFzZXxNeUNsYXNzfE5hbWVzcGFjZXxOZXd8
TmV4dHxOb3R8Tm90SW5oZXJpdGFibGV8Tm90T3ZlcnJpZGFibGV8T2JqZWN0fE9ufE9wdGlvbnxP
cHRpb25hbHxPcnxPckVsc2V8T3ZlcmxvYWRzfE92ZXJyaWRhYmxlfE92ZXJyaWRlc3xQYXJhbUFy
cmF5fFByZXNlcnZlfFByaXZhdGV8UHJvcGVydHl8UHJvdGVjdGVkfFB1YmxpY3xSYWlzZUV2ZW50
fFJlYWRPbmx5fFJlRGltfFJlbW92ZUhhbmRsZXJ8UmVzdW1lfFJldHVybnxTZWxlY3R8U2V0fFNo
YWRvd3N8U2hhcmVkfFNob3J0fFNpbmdsZXxTdGF0aWN8U3RlcHxTdG9wfFN0cmluZ3xTdHJ1Y3R1
cmV8U3VifFN5bmNMb2NrfFRoZW58VGhyb3d8VG98VHJ5fFR5cGVPZnxVbmljb2RlfFVudGlsfFZh
cmlhbnR8V2VuZHxXaGVufFdoaWxlfFdpdGh8V2l0aEV2ZW50c3xXcml0ZU9ubHl8WG9yfEVuZElm
fEdvU3VifExldHxWYXJpYW50fFdlbmQpXGIvaSwKbnVsbF0sWyJjb20iLC9eUkVNW15cclxuXHUy
MDI4XHUyMDI5XSovaV0sWyJsaXQiLC9eKD86VHJ1ZVxifEZhbHNlXGJ8Tm90aGluZ1xifFxkKyg/
OkVbK1wtXT9cZCtbRlJEXT98W0ZSRFNJTF0pP3woPzomSFswLTlBLUZdK3wmT1swLTddKylbU0lM
XT98XGQqXC5cZCsoPzpFWytcLV0/XGQrKT9bRlJEXT98I1xzKyg/OlxkK1tcLVwvXVxkK1tcLVwv
XVxkKyg/OlxzK1xkKzpcZCsoPzo6XGQrKT8oXHMqKD86QU18UE0pKT8pP3xcZCs6XGQrKD86Olxk
Kyk/KFxzKig/OkFNfFBNKSk/KVxzKyMpL2ldLFsicGxuIiwvXig/Oig/OlthLXpdfF9cdylcdyp8
XFsoPzpbYS16XXxfXHcpXHcqXF0pL2ldLFsicHVuIiwvXlteXHdcdFxuXHIgXCJcJ1xbXF1ceEEw
XHUyMDE4XHUyMDE5XHUyMDFDXHUyMDFEXHUyMDI4XHUyMDI5XSsvXSxbInB1biIsL14oPzpcW3xc
XSkvXV0pLFsidmIiLCJ2YnMiXSk=

@@ js/lang-vhdl.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwbG4iLC9eW1x0
XG5cciBceEEwXSsvLG51bGwsIlx0XG5cciBcdTAwYTAiXV0sW1sic3RyIiwvXig/OltCT1hdPyIo
PzpbXlwiXXwiIikqInwnLicpL2ldLFsiY29tIiwvXi0tW15cclxuXSovXSxbImt3ZCIsL14oPzph
YnN8YWNjZXNzfGFmdGVyfGFsaWFzfGFsbHxhbmR8YXJjaGl0ZWN0dXJlfGFycmF5fGFzc2VydHxh
dHRyaWJ1dGV8YmVnaW58YmxvY2t8Ym9keXxidWZmZXJ8YnVzfGNhc2V8Y29tcG9uZW50fGNvbmZp
Z3VyYXRpb258Y29uc3RhbnR8ZGlzY29ubmVjdHxkb3dudG98ZWxzZXxlbHNpZnxlbmR8ZW50aXR5
fGV4aXR8ZmlsZXxmb3J8ZnVuY3Rpb258Z2VuZXJhdGV8Z2VuZXJpY3xncm91cHxndWFyZGVkfGlm
fGltcHVyZXxpbnxpbmVydGlhbHxpbm91dHxpc3xsYWJlbHxsaWJyYXJ5fGxpbmthZ2V8bGl0ZXJh
bHxsb29wfG1hcHxtb2R8bmFuZHxuZXd8bmV4dHxub3J8bm90fG51bGx8b2Z8b258b3Blbnxvcnxv
dGhlcnN8b3V0fHBhY2thZ2V8cG9ydHxwb3N0cG9uZWR8cHJvY2VkdXJlfHByb2Nlc3N8cHVyZXxy
YW5nZXxyZWNvcmR8cmVnaXN0ZXJ8cmVqZWN0fHJlbXxyZXBvcnR8cmV0dXJufHJvbHxyb3J8c2Vs
ZWN0fHNldmVyaXR5fHNoYXJlZHxzaWduYWx8c2xhfHNsbHxzcmF8c3JsfHN1YnR5cGV8dGhlbnx0
b3x0cmFuc3BvcnR8dHlwZXx1bmFmZmVjdGVkfHVuaXRzfHVudGlsfHVzZXx2YXJpYWJsZXx3YWl0
fHdoZW58d2hpbGV8d2l0aHx4bm9yfHhvcikoPz1bXlx3LV18JCkvaSwKbnVsbF0sWyJ0eXAiLC9e
KD86Yml0fGJpdF92ZWN0b3J8Y2hhcmFjdGVyfGJvb2xlYW58aW50ZWdlcnxyZWFsfHRpbWV8c3Ry
aW5nfHNldmVyaXR5X2xldmVsfHBvc2l0aXZlfG5hdHVyYWx8c2lnbmVkfHVuc2lnbmVkfGxpbmV8
dGV4dHxzdGRfdT9sb2dpYyg/Ol92ZWN0b3IpPykoPz1bXlx3LV18JCkvaSxudWxsXSxbInR5cCIs
L15cJyg/OkFDVElWRXxBU0NFTkRJTkd8QkFTRXxERUxBWUVEfERSSVZJTkd8RFJJVklOR19WQUxV
RXxFVkVOVHxISUdIfElNQUdFfElOU1RBTkNFX05BTUV8TEFTVF9BQ1RJVkV8TEFTVF9FVkVOVHxM
QVNUX1ZBTFVFfExFRlR8TEVGVE9GfExFTkdUSHxMT1d8UEFUSF9OQU1FfFBPU3xQUkVEfFFVSUVU
fFJBTkdFfFJFVkVSU0VfUkFOR0V8UklHSFR8UklHSFRPRnxTSU1QTEVfTkFNRXxTVEFCTEV8U1VD
Q3xUUkFOU0FDVElPTnxWQUx8VkFMVUUpKD89W15cdy1dfCQpL2ksbnVsbF0sWyJsaXQiLC9eXGQr
KD86X1xkKykqKD86I1tcd1xcLl0rIyg/OlsrXC1dP1xkKyg/Ol9cZCspKik/fCg/OlwuXGQrKD86
X1xkKykqKT8oPzpFWytcLV0/XGQrKD86X1xkKykqKT8pL2ldLApbInBsbiIsL14oPzpbYS16XVx3
KnxcXFteXFxdKlxcKS9pXSxbInB1biIsL15bXlx3XHRcblxyIFx4QTBcIlwnXVteXHdcdFxuXHIg
XHhBMFwtXCJcJ10qL11dKSxbInZoZGwiLCJ2aGQiXSk=

@@ js/lang-wiki.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwbG4iLC9eW1x0
IFx4QTBhLWdpLXowLTldKy8sbnVsbCwiXHQgXHUwMGEwYWJjZGVmZ2lqa2xtbm9wcXJzdHV2d3h5
ejAxMjM0NTY3ODkiXSxbInB1biIsL15bPSp+XF5cW1xdXSsvLG51bGwsIj0qfl5bXSJdXSxbWyJs
YW5nLXdpa2kubWV0YSIsLyg/Ol5efFxyXG4/fFxuKSgjW2Etel0rKVxiL10sWyJsaXQiLC9eKD86
W0EtWl1bYS16XVthLXowLTldK1tBLVpdW2Etel1bYS16QS1aMC05XSspXGIvXSxbImxhbmctIiwv
Xlx7XHtceyhbXHNcU10rPylcfVx9XH0vXSxbImxhbmctIiwvXmAoW15cclxuYF0rKWAvXSxbInN0
ciIsL15odHRwcz86XC9cL1teXC8/I1xzXSooPzpcL1tePyNcc10qKT8oPzpcP1teI1xzXSopPyg/
OiNcUyopPy9pXSxbInBsbiIsL14oPzpcclxufFtcc1xTXSlbXiM9Kn5eQS1aaFx7YFxbXHJcbl0q
L11dKSxbIndpa2kiXSk7ClBSLnJlZ2lzdGVyTGFuZ0hhbmRsZXIoUFIuY3JlYXRlU2ltcGxlTGV4
ZXIoW1sia3dkIiwvXiNbYS16XSsvaSxudWxsLCIjIl1dLFtdKSxbIndpa2kubWV0YSJdKQ==

@@ js/lang-yaml.js (base64)
UFIucmVnaXN0ZXJMYW5nSGFuZGxlcihQUi5jcmVhdGVTaW1wbGVMZXhlcihbWyJwdW4iLC9eWzp8
Pj9dKy8sbnVsbCwiOnw+PyJdLFsiZGVjIiwvXiUoPzpZQU1MfFRBRylbXiNcclxuXSsvLG51bGws
IiUiXSxbInR5cCIsL15bJl1cUysvLG51bGwsIiYiXSxbInR5cCIsL14hXFMqLyxudWxsLCIhIl0s
WyJzdHIiLC9eIig/OlteXFwiXXxcXC4pKig/OiJ8JCkvLG51bGwsJyInXSxbInN0ciIsL14nKD86
W14nXXwnJykqKD86J3wkKS8sbnVsbCwiJyJdLFsiY29tIiwvXiNbXlxyXG5dKi8sbnVsbCwiIyJd
LFsicGxuIiwvXlxzKy8sbnVsbCwiIFx0XHJcbiJdXSxbWyJkZWMiLC9eKD86LS0tfFwuXC5cLiko
PzpbXHJcbl18JCkvXSxbInB1biIsL14tL10sWyJrd2QiLC9eXHcrOlsgXHJcbl0vXSxbInBsbiIs
L15cdysvXV0pLApbInlhbWwiLCJ5bWwiXSk=

@@ js/prettify.js (base64)
d2luZG93LlBSX1NIT1VMRF9VU0VfQ09OVElOVUFUSU9OPXRydWU7d2luZG93LlBSX1RBQl9XSURU
SD04O3dpbmRvdy5QUl9ub3JtYWxpemVkSHRtbD13aW5kb3cuUFI9d2luZG93LnByZXR0eVByaW50
T25lPXdpbmRvdy5wcmV0dHlQcmludD12b2lkIDA7d2luZG93Ll9wcl9pc0lFNj1mdW5jdGlvbigp
e3ZhciB5PW5hdmlnYXRvciYmbmF2aWdhdG9yLnVzZXJBZ2VudCYmbmF2aWdhdG9yLnVzZXJBZ2Vu
dC5tYXRjaCgvXGJNU0lFIChbNjc4XSlcLi8pO3k9eT8reVsxXTpmYWxzZTt3aW5kb3cuX3ByX2lz
SUU2PWZ1bmN0aW9uKCl7cmV0dXJuIHl9O3JldHVybiB5fTsKKGZ1bmN0aW9uKCl7ZnVuY3Rpb24g
eShiKXtyZXR1cm4gYi5yZXBsYWNlKEwsIiZhbXA7IikucmVwbGFjZShNLCImbHQ7IikucmVwbGFj
ZShOLCImZ3Q7Iil9ZnVuY3Rpb24gSChiLGYsaSl7c3dpdGNoKGIubm9kZVR5cGUpe2Nhc2UgMTp2
YXIgbz1iLnRhZ05hbWUudG9Mb3dlckNhc2UoKTtmLnB1c2goIjwiLG8pO3ZhciBsPWIuYXR0cmli
dXRlcyxuPWwubGVuZ3RoO2lmKG4pe2lmKGkpe2Zvcih2YXIgcj1bXSxqPW47LS1qPj0wOylyW2pd
PWxbal07ci5zb3J0KGZ1bmN0aW9uKHEsbSl7cmV0dXJuIHEubmFtZTxtLm5hbWU/LTE6cS5uYW1l
PT09bS5uYW1lPzA6MX0pO2w9cn1mb3Ioaj0wO2o8bjsrK2ope3I9bFtqXTtyLnNwZWNpZmllZCYm
Zi5wdXNoKCIgIixyLm5hbWUudG9Mb3dlckNhc2UoKSwnPSInLHIudmFsdWUucmVwbGFjZShMLCIm
YW1wOyIpLnJlcGxhY2UoTSwiJmx0OyIpLnJlcGxhY2UoTiwiJmd0OyIpLnJlcGxhY2UoWCwiJnF1
b3Q7IiksJyInKX19Zi5wdXNoKCI+Iik7CmZvcihsPWIuZmlyc3RDaGlsZDtsO2w9bC5uZXh0U2li
bGluZylIKGwsZixpKTtpZihiLmZpcnN0Q2hpbGR8fCEvXig/OmJyfGxpbmt8aW1nKSQvLnRlc3Qo
bykpZi5wdXNoKCI8LyIsbywiPiIpO2JyZWFrO2Nhc2UgMzpjYXNlIDQ6Zi5wdXNoKHkoYi5ub2Rl
VmFsdWUpKTticmVha319ZnVuY3Rpb24gTyhiKXtmdW5jdGlvbiBmKGMpe2lmKGMuY2hhckF0KDAp
IT09IlxcIilyZXR1cm4gYy5jaGFyQ29kZUF0KDApO3N3aXRjaChjLmNoYXJBdCgxKSl7Y2FzZSAi
YiI6cmV0dXJuIDg7Y2FzZSAidCI6cmV0dXJuIDk7Y2FzZSAibiI6cmV0dXJuIDEwO2Nhc2UgInYi
OnJldHVybiAxMTtjYXNlICJmIjpyZXR1cm4gMTI7Y2FzZSAiciI6cmV0dXJuIDEzO2Nhc2UgInUi
OmNhc2UgIngiOnJldHVybiBwYXJzZUludChjLnN1YnN0cmluZygyKSwxNil8fGMuY2hhckNvZGVB
dCgxKTtjYXNlICIwIjpjYXNlICIxIjpjYXNlICIyIjpjYXNlICIzIjpjYXNlICI0IjpjYXNlICI1
IjpjYXNlICI2IjpjYXNlICI3IjpyZXR1cm4gcGFyc2VJbnQoYy5zdWJzdHJpbmcoMSksCjgpO2Rl
ZmF1bHQ6cmV0dXJuIGMuY2hhckNvZGVBdCgxKX19ZnVuY3Rpb24gaShjKXtpZihjPDMyKXJldHVy
bihjPDE2PyJcXHgwIjoiXFx4IikrYy50b1N0cmluZygxNik7Yz1TdHJpbmcuZnJvbUNoYXJDb2Rl
KGMpO2lmKGM9PT0iXFwifHxjPT09Ii0ifHxjPT09IlsifHxjPT09Il0iKWM9IlxcIitjO3JldHVy
biBjfWZ1bmN0aW9uIG8oYyl7dmFyIGQ9Yy5zdWJzdHJpbmcoMSxjLmxlbmd0aC0xKS5tYXRjaChS
ZWdFeHAoIlxcXFx1WzAtOUEtRmEtZl17NH18XFxcXHhbMC05QS1GYS1mXXsyfXxcXFxcWzAtM11b
MC03XXswLDJ9fFxcXFxbMC03XXsxLDJ9fFxcXFxbXFxzXFxTXXwtfFteLVxcXFxdIiwiZyIpKTtj
PVtdO2Zvcih2YXIgYT1bXSxrPWRbMF09PT0iXiIsZT1rPzE6MCxoPWQubGVuZ3RoO2U8aDsrK2Up
e3ZhciBnPWRbZV07c3dpdGNoKGcpe2Nhc2UgIlxcQiI6Y2FzZSAiXFxiIjpjYXNlICJcXEQiOmNh
c2UgIlxcZCI6Y2FzZSAiXFxTIjpjYXNlICJcXHMiOmNhc2UgIlxcVyI6Y2FzZSAiXFx3IjpjLnB1
c2goZyk7CmNvbnRpbnVlfWc9ZihnKTt2YXIgcztpZihlKzI8aCYmIi0iPT09ZFtlKzFdKXtzPWYo
ZFtlKzJdKTtlKz0yfWVsc2Ugcz1nO2EucHVzaChbZyxzXSk7aWYoIShzPDY1fHxnPjEyMikpe3M8
NjV8fGc+OTB8fGEucHVzaChbTWF0aC5tYXgoNjUsZyl8MzIsTWF0aC5taW4ocyw5MCl8MzJdKTtz
PDk3fHxnPjEyMnx8YS5wdXNoKFtNYXRoLm1heCg5NyxnKSYtMzMsTWF0aC5taW4ocywxMjIpJi0z
M10pfX1hLnNvcnQoZnVuY3Rpb24odix3KXtyZXR1cm4gdlswXS13WzBdfHx3WzFdLXZbMV19KTtk
PVtdO2c9W05hTixOYU5dO2ZvcihlPTA7ZTxhLmxlbmd0aDsrK2Upe2g9YVtlXTtpZihoWzBdPD1n
WzFdKzEpZ1sxXT1NYXRoLm1heChnWzFdLGhbMV0pO2Vsc2UgZC5wdXNoKGc9aCl9YT1bIlsiXTtr
JiZhLnB1c2goIl4iKTthLnB1c2guYXBwbHkoYSxjKTtmb3IoZT0wO2U8ZC5sZW5ndGg7KytlKXto
PWRbZV07YS5wdXNoKGkoaFswXSkpO2lmKGhbMV0+aFswXSl7aFsxXSsxPmhbMF0mJmEucHVzaCgi
LSIpOwphLnB1c2goaShoWzFdKSl9fWEucHVzaCgiXSIpO3JldHVybiBhLmpvaW4oIiIpfWZ1bmN0
aW9uIGwoYyl7Zm9yKHZhciBkPWMuc291cmNlLm1hdGNoKFJlZ0V4cCgiKD86XFxbKD86W15cXHg1
Q1xceDVEXXxcXFxcW1xcc1xcU10pKlxcXXxcXFxcdVtBLUZhLWYwLTldezR9fFxcXFx4W0EtRmEt
ZjAtOV17Mn18XFxcXFswLTldK3xcXFxcW151eDAtOV18XFwoXFw/WzohPV18W1xcKFxcKVxcXl18
W15cXHg1QlxceDVDXFwoXFwpXFxeXSspIiwiZyIpKSxhPWQubGVuZ3RoLGs9W10sZT0wLGg9MDtl
PGE7KytlKXt2YXIgZz1kW2VdO2lmKGc9PT0iKCIpKytoO2Vsc2UgaWYoIlxcIj09PWcuY2hhckF0
KDApKWlmKChnPStnLnN1YnN0cmluZygxKSkmJmc8PWgpa1tnXT0tMX1mb3IoZT0xO2U8ay5sZW5n
dGg7KytlKWlmKC0xPT09a1tlXSlrW2VdPSsrbjtmb3IoaD1lPTA7ZTxhOysrZSl7Zz1kW2VdO2lm
KGc9PT0iKCIpeysraDtpZihrW2hdPT09dW5kZWZpbmVkKWRbZV09Iig/OiJ9ZWxzZSBpZigiXFwi
PT09CmcuY2hhckF0KDApKWlmKChnPStnLnN1YnN0cmluZygxKSkmJmc8PWgpZFtlXT0iXFwiK2tb
aF19Zm9yKGg9ZT0wO2U8YTsrK2UpaWYoIl4iPT09ZFtlXSYmIl4iIT09ZFtlKzFdKWRbZV09IiI7
aWYoYy5pZ25vcmVDYXNlJiZyKWZvcihlPTA7ZTxhOysrZSl7Zz1kW2VdO2M9Zy5jaGFyQXQoMCk7
aWYoZy5sZW5ndGg+PTImJmM9PT0iWyIpZFtlXT1vKGcpO2Vsc2UgaWYoYyE9PSJcXCIpZFtlXT1n
LnJlcGxhY2UoL1thLXpBLVpdL2csZnVuY3Rpb24ocyl7cz1zLmNoYXJDb2RlQXQoMCk7cmV0dXJu
IlsiK1N0cmluZy5mcm9tQ2hhckNvZGUocyYtMzMsc3wzMikrIl0ifSl9cmV0dXJuIGQuam9pbigi
Iil9Zm9yKHZhciBuPTAscj1mYWxzZSxqPWZhbHNlLHE9MCxtPWIubGVuZ3RoO3E8bTsrK3Epe3Zh
ciB0PWJbcV07aWYodC5pZ25vcmVDYXNlKWo9dHJ1ZTtlbHNlIGlmKC9bYS16XS9pLnRlc3QodC5z
b3VyY2UucmVwbGFjZSgvXFx1WzAtOWEtZl17NH18XFx4WzAtOWEtZl17Mn18XFxbXnV4XS9naSwK
IiIpKSl7cj10cnVlO2o9ZmFsc2U7YnJlYWt9fXZhciBwPVtdO3E9MDtmb3IobT1iLmxlbmd0aDtx
PG07KytxKXt0PWJbcV07aWYodC5nbG9iYWx8fHQubXVsdGlsaW5lKXRocm93IEVycm9yKCIiK3Qp
O3AucHVzaCgiKD86IitsKHQpKyIpIil9cmV0dXJuIFJlZ0V4cChwLmpvaW4oInwiKSxqPyJnaSI6
ImciKX1mdW5jdGlvbiBZKGIpe3ZhciBmPTA7cmV0dXJuIGZ1bmN0aW9uKGkpe2Zvcih2YXIgbz1u
dWxsLGw9MCxuPTAscj1pLmxlbmd0aDtuPHI7KytuKXN3aXRjaChpLmNoYXJBdChuKSl7Y2FzZSAi
XHQiOm98fChvPVtdKTtvLnB1c2goaS5zdWJzdHJpbmcobCxuKSk7bD1iLWYlYjtmb3IoZis9bDts
Pj0wO2wtPTE2KW8ucHVzaCgiICAgICAgICAgICAgICAgICIuc3Vic3RyaW5nKDAsbCkpO2w9bisx
O2JyZWFrO2Nhc2UgIlxuIjpmPTA7YnJlYWs7ZGVmYXVsdDorK2Z9aWYoIW8pcmV0dXJuIGk7by5w
dXNoKGkuc3Vic3RyaW5nKGwpKTtyZXR1cm4gby5qb2luKCIiKX19ZnVuY3Rpb24gSShiLApmLGks
byl7aWYoZil7Yj17c291cmNlOmYsYzpifTtpKGIpO28ucHVzaC5hcHBseShvLGIuZCl9fWZ1bmN0
aW9uIEIoYixmKXt2YXIgaT17fSxvOyhmdW5jdGlvbigpe2Zvcih2YXIgcj1iLmNvbmNhdChmKSxq
PVtdLHE9e30sbT0wLHQ9ci5sZW5ndGg7bTx0OysrbSl7dmFyIHA9clttXSxjPXBbM107aWYoYylm
b3IodmFyIGQ9Yy5sZW5ndGg7LS1kPj0wOylpW2MuY2hhckF0KGQpXT1wO3A9cFsxXTtjPSIiK3A7
aWYoIXEuaGFzT3duUHJvcGVydHkoYykpe2oucHVzaChwKTtxW2NdPW51bGx9fWoucHVzaCgvW1ww
LVx1ZmZmZl0vKTtvPU8oail9KSgpO3ZhciBsPWYubGVuZ3RoO2Z1bmN0aW9uIG4ocil7Zm9yKHZh
ciBqPXIuYyxxPVtqLHpdLG09MCx0PXIuc291cmNlLm1hdGNoKG8pfHxbXSxwPXt9LGM9MCxkPXQu
bGVuZ3RoO2M8ZDsrK2Mpe3ZhciBhPXRbY10saz1wW2FdLGU9dm9pZCAwLGg7aWYodHlwZW9mIGs9
PT0ic3RyaW5nIiloPWZhbHNlO2Vsc2V7dmFyIGc9aVthLmNoYXJBdCgwKV07CmlmKGcpe2U9YS5t
YXRjaChnWzFdKTtrPWdbMF19ZWxzZXtmb3IoaD0wO2g8bDsrK2gpe2c9ZltoXTtpZihlPWEubWF0
Y2goZ1sxXSkpe2s9Z1swXTticmVha319ZXx8KGs9eil9aWYoKGg9ay5sZW5ndGg+PTUmJiJsYW5n
LSI9PT1rLnN1YnN0cmluZygwLDUpKSYmIShlJiZ0eXBlb2YgZVsxXT09PSJzdHJpbmciKSl7aD1m
YWxzZTtrPVB9aHx8KHBbYV09ayl9Zz1tO20rPWEubGVuZ3RoO2lmKGgpe2g9ZVsxXTt2YXIgcz1h
LmluZGV4T2YoaCksdj1zK2gubGVuZ3RoO2lmKGVbMl0pe3Y9YS5sZW5ndGgtZVsyXS5sZW5ndGg7
cz12LWgubGVuZ3RofWs9ay5zdWJzdHJpbmcoNSk7SShqK2csYS5zdWJzdHJpbmcoMCxzKSxuLHEp
O0koaitnK3MsaCxRKGssaCkscSk7SShqK2crdixhLnN1YnN0cmluZyh2KSxuLHEpfWVsc2UgcS5w
dXNoKGorZyxrKX1yLmQ9cX1yZXR1cm4gbn1mdW5jdGlvbiB4KGIpe3ZhciBmPVtdLGk9W107aWYo
Yi50cmlwbGVRdW90ZWRTdHJpbmdzKWYucHVzaChbQSwvXig/OlwnXCdcJyg/OlteXCdcXF18XFxb
XHNcU118XCd7MSwyfSg/PVteXCddKSkqKD86XCdcJ1wnfCQpfFwiXCJcIig/OlteXCJcXF18XFxb
XHNcU118XCJ7MSwyfSg/PVteXCJdKSkqKD86XCJcIlwifCQpfFwnKD86W15cXFwnXXxcXFtcc1xT
XSkqKD86XCd8JCl8XCIoPzpbXlxcXCJdfFxcW1xzXFNdKSooPzpcInwkKSkvLApudWxsLCInXCIi
XSk7ZWxzZSBiLm11bHRpTGluZVN0cmluZ3M/Zi5wdXNoKFtBLC9eKD86XCcoPzpbXlxcXCddfFxc
W1xzXFNdKSooPzpcJ3wkKXxcIig/OlteXFxcIl18XFxbXHNcU10pKig/OlwifCQpfFxgKD86W15c
XFxgXXxcXFtcc1xTXSkqKD86XGB8JCkpLyxudWxsLCInXCJgIl0pOmYucHVzaChbQSwvXig/Olwn
KD86W15cXFwnXHJcbl18XFwuKSooPzpcJ3wkKXxcIig/OlteXFxcIlxyXG5dfFxcLikqKD86XCJ8
JCkpLyxudWxsLCJcIiciXSk7Yi52ZXJiYXRpbVN0cmluZ3MmJmkucHVzaChbQSwvXkBcIig/Olte
XCJdfFwiXCIpKig/OlwifCQpLyxudWxsXSk7aWYoYi5oYXNoQ29tbWVudHMpaWYoYi5jU3R5bGVD
b21tZW50cyl7Zi5wdXNoKFtDLC9eIyg/Oig/OmRlZmluZXxlbGlmfGVsc2V8ZW5kaWZ8ZXJyb3J8
aWZkZWZ8aW5jbHVkZXxpZm5kZWZ8bGluZXxwcmFnbWF8dW5kZWZ8d2FybmluZylcYnxbXlxyXG5d
KikvLG51bGwsIiMiXSk7aS5wdXNoKFtBLC9ePCg/Oig/Oig/OlwuXC5cLykqfFwvPykoPzpbXHct
XSsoPzpcL1tcdy1dKykrKT9bXHctXStcLmh8W2Etel1cdyopPi8sCm51bGxdKX1lbHNlIGYucHVz
aChbQywvXiNbXlxyXG5dKi8sbnVsbCwiIyJdKTtpZihiLmNTdHlsZUNvbW1lbnRzKXtpLnB1c2go
W0MsL15cL1wvW15cclxuXSovLG51bGxdKTtpLnB1c2goW0MsL15cL1wqW1xzXFNdKj8oPzpcKlwv
fCQpLyxudWxsXSl9Yi5yZWdleExpdGVyYWxzJiZpLnB1c2goWyJsYW5nLXJlZ2V4IixSZWdFeHAo
Il4iK1orIigvKD89W14vKl0pKD86W14vXFx4NUJcXHg1Q118XFx4NUNbXFxzXFxTXXxcXHg1Qig/
OlteXFx4NUNcXHg1RF18XFx4NUNbXFxzXFxTXSkqKD86XFx4NUR8JCkpKy8pIildKTtiPWIua2V5
d29yZHMucmVwbGFjZSgvXlxzK3xccyskL2csIiIpO2IubGVuZ3RoJiZpLnB1c2goW1IsUmVnRXhw
KCJeKD86IitiLnJlcGxhY2UoL1xzKy9nLCJ8IikrIilcXGIiKSxudWxsXSk7Zi5wdXNoKFt6LC9e
XHMrLyxudWxsLCIgXHJcblx0XHUwMGEwIl0pO2kucHVzaChbSiwvXkBbYS16XyRdW2Etel8kQDAt
OV0qL2ksbnVsbF0sW1MsL15AP1tBLVpdK1thLXpdW0EtWmEtel8kQDAtOV0qLywKbnVsbF0sW3os
L15bYS16XyRdW2Etel8kQDAtOV0qL2ksbnVsbF0sW0osL14oPzoweFthLWYwLTldK3woPzpcZCg/
Ol9cZCspKlxkKig/OlwuXGQqKT98XC5cZFwrKSg/OmVbK1wtXT9cZCspPylbYS16XSovaSxudWxs
LCIwMTIzNDU2Nzg5Il0sW0UsL14uW15cc1x3XC4kQFwnXCJcYFwvXCNdKi8sbnVsbF0pO3JldHVy
biBCKGYsaSl9ZnVuY3Rpb24gJChiKXtmdW5jdGlvbiBmKEQpe2lmKEQ+cil7aWYoaiYmaiE9PXEp
e24ucHVzaCgiPC9zcGFuPiIpO2o9bnVsbH1pZighaiYmcSl7aj1xO24ucHVzaCgnPHNwYW4gY2xh
c3M9IicsaiwnIj4nKX12YXIgVD15KHAoaS5zdWJzdHJpbmcocixEKSkpLnJlcGxhY2UoZT9kOmMs
IiQxJiMxNjA7Iik7ZT1rLnRlc3QoVCk7bi5wdXNoKFQucmVwbGFjZShhLHMpKTtyPUR9fXZhciBp
PWIuc291cmNlLG89Yi5nLGw9Yi5kLG49W10scj0wLGo9bnVsbCxxPW51bGwsbT0wLHQ9MCxwPVko
d2luZG93LlBSX1RBQl9XSURUSCksYz0vKFtcclxuIF0pIC9nLApkPS8oXnwgKSAvZ20sYT0vXHJc
bj98XG4vZyxrPS9bIFxyXG5dJC8sZT10cnVlLGg9d2luZG93Ll9wcl9pc0lFNigpO2g9aD9iLmIu
dGFnTmFtZT09PSJQUkUiP2g9PT02PyImIzE2MDtcclxuIjpoPT09Nz8iJiMxNjA7PGJyPlxyIjoi
JiMxNjA7XHIiOiImIzE2MDs8YnIgLz4iOiI8YnIgLz4iO3ZhciBnPWIuYi5jbGFzc05hbWUubWF0
Y2goL1xibGluZW51bXNcYig/OjooXGQrKSk/LykscztpZihnKXtmb3IodmFyIHY9W10sdz0wO3c8
MTA7Kyt3KXZbd109aCsnPC9saT48bGkgY2xhc3M9IkwnK3crJyI+Jzt2YXIgRj1nWzFdJiZnWzFd
Lmxlbmd0aD9nWzFdLTE6MDtuLnB1c2goJzxvbCBjbGFzcz0ibGluZW51bXMiPjxsaSBjbGFzcz0i
TCcsRiUxMCwnIicpO0YmJm4ucHVzaCgnIHZhbHVlPSInLEYrMSwnIicpO24ucHVzaCgiPiIpO3M9
ZnVuY3Rpb24oKXt2YXIgRD12WysrRiUxMF07cmV0dXJuIGo/Ijwvc3Bhbj4iK0QrJzxzcGFuIGNs
YXNzPSInK2orJyI+JzpEfX1lbHNlIHM9aDsKZm9yKDs7KWlmKG08by5sZW5ndGg/dDxsLmxlbmd0
aD9vW21dPD1sW3RdOnRydWU6ZmFsc2Upe2Yob1ttXSk7aWYoail7bi5wdXNoKCI8L3NwYW4+Iik7
aj1udWxsfW4ucHVzaChvW20rMV0pO20rPTJ9ZWxzZSBpZih0PGwubGVuZ3RoKXtmKGxbdF0pO3E9
bFt0KzFdO3QrPTJ9ZWxzZSBicmVhaztmKGkubGVuZ3RoKTtqJiZuLnB1c2goIjwvc3Bhbj4iKTtn
JiZuLnB1c2goIjwvbGk+PC9vbD4iKTtiLmE9bi5qb2luKCIiKX1mdW5jdGlvbiB1KGIsZil7Zm9y
KHZhciBpPWYubGVuZ3RoOy0taT49MDspe3ZhciBvPWZbaV07aWYoRy5oYXNPd25Qcm9wZXJ0eShv
KSkiY29uc29sZSJpbiB3aW5kb3cmJmNvbnNvbGUud2FybigiY2Fubm90IG92ZXJyaWRlIGxhbmd1
YWdlIGhhbmRsZXIgJXMiLG8pO2Vsc2UgR1tvXT1ifX1mdW5jdGlvbiBRKGIsZil7YiYmRy5oYXNP
d25Qcm9wZXJ0eShiKXx8KGI9L15ccyo8Ly50ZXN0KGYpPyJkZWZhdWx0LW1hcmt1cCI6ImRlZmF1
bHQtY29kZSIpO3JldHVybiBHW2JdfQpmdW5jdGlvbiBVKGIpe3ZhciBmPWIuZixpPWIuZTtiLmE9
Zjt0cnl7dmFyIG8sbD1mLm1hdGNoKGFhKTtmPVtdO3ZhciBuPTAscj1bXTtpZihsKWZvcih2YXIg
aj0wLHE9bC5sZW5ndGg7ajxxOysrail7dmFyIG09bFtqXTtpZihtLmxlbmd0aD4xJiZtLmNoYXJB
dCgwKT09PSI8Iil7aWYoIWJhLnRlc3QobSkpaWYoY2EudGVzdChtKSl7Zi5wdXNoKG0uc3Vic3Ry
aW5nKDksbS5sZW5ndGgtMykpO24rPW0ubGVuZ3RoLTEyfWVsc2UgaWYoZGEudGVzdChtKSl7Zi5w
dXNoKCJcbiIpOysrbn1lbHNlIGlmKG0uaW5kZXhPZihWKT49MCYmbS5yZXBsYWNlKC9ccyhcdysp
XHMqPVxzKig/OlwiKFteXCJdKilcInwnKFteXCddKiknfChcUyspKS9nLCcgJDE9IiQyJDMkNCIn
KS5tYXRjaCgvW2NDXVtsTF1bYUFdW3NTXVtzU109XCJbXlwiXSpcYm5vY29kZVxiLykpe3ZhciB0
PW0ubWF0Y2goVylbMl0scD0xLGM7Yz1qKzE7YTpmb3IoO2M8cTsrK2Mpe3ZhciBkPWxbY10ubWF0
Y2goVyk7aWYoZCYmCmRbMl09PT10KWlmKGRbMV09PT0iLyIpe2lmKC0tcD09PTApYnJlYWsgYX1l
bHNlKytwfWlmKGM8cSl7ci5wdXNoKG4sbC5zbGljZShqLGMrMSkuam9pbigiIikpO2o9Y31lbHNl
IHIucHVzaChuLG0pfWVsc2Ugci5wdXNoKG4sbSl9ZWxzZXt2YXIgYTtwPW07dmFyIGs9cC5pbmRl
eE9mKCImIik7aWYoazwwKWE9cDtlbHNle2ZvcigtLWs7KGs9cC5pbmRleE9mKCImIyIsaysxKSk+
PTA7KXt2YXIgZT1wLmluZGV4T2YoIjsiLGspO2lmKGU+PTApe3ZhciBoPXAuc3Vic3RyaW5nKGsr
MyxlKSxnPTEwO2lmKGgmJmguY2hhckF0KDApPT09IngiKXtoPWguc3Vic3RyaW5nKDEpO2c9MTZ9
dmFyIHM9cGFyc2VJbnQoaCxnKTtpc05hTihzKXx8KHA9cC5zdWJzdHJpbmcoMCxrKStTdHJpbmcu
ZnJvbUNoYXJDb2RlKHMpK3Auc3Vic3RyaW5nKGUrMSkpfX1hPXAucmVwbGFjZShlYSwiPCIpLnJl
cGxhY2UoZmEsIj4iKS5yZXBsYWNlKGdhLCInIikucmVwbGFjZShoYSwnIicpLnJlcGxhY2UoaWEs
IiAiKS5yZXBsYWNlKGphLAoiJiIpfWYucHVzaChhKTtuKz1hLmxlbmd0aH19bz17c291cmNlOmYu
am9pbigiIiksaDpyfTt2YXIgdj1vLnNvdXJjZTtiLnNvdXJjZT12O2IuYz0wO2IuZz1vLmg7UShp
LHYpKGIpOyQoYil9Y2F0Y2godyl7aWYoImNvbnNvbGUiaW4gd2luZG93KWNvbnNvbGUubG9nKHcm
Jncuc3RhY2s/dy5zdGFjazp3KX19dmFyIEE9InN0ciIsUj0ia3dkIixDPSJjb20iLFM9InR5cCIs
Sj0ibGl0IixFPSJwdW4iLHo9InBsbiIsUD0ic3JjIixWPSJub2NvZGUiLFo9ZnVuY3Rpb24oKXtm
b3IodmFyIGI9WyIhIiwiIT0iLCIhPT0iLCIjIiwiJSIsIiU9IiwiJiIsIiYmIiwiJiY9IiwiJj0i
LCIoIiwiKiIsIio9IiwiKz0iLCIsIiwiLT0iLCItPiIsIi8iLCIvPSIsIjoiLCI6OiIsIjsiLCI8
IiwiPDwiLCI8PD0iLCI8PSIsIj0iLCI9PSIsIj09PSIsIj4iLCI+PSIsIj4+IiwiPj49IiwiPj4+
IiwiPj4+PSIsIj8iLCJAIiwiWyIsIl4iLCJePSIsIl5eIiwiXl49IiwieyIsInwiLCJ8PSIsInx8
IiwifHw9IiwKIn4iLCJicmVhayIsImNhc2UiLCJjb250aW51ZSIsImRlbGV0ZSIsImRvIiwiZWxz
ZSIsImZpbmFsbHkiLCJpbnN0YW5jZW9mIiwicmV0dXJuIiwidGhyb3ciLCJ0cnkiLCJ0eXBlb2Yi
XSxmPSIoPzpeXnxbKy1dIixpPTA7aTxiLmxlbmd0aDsrK2kpZis9InwiK2JbaV0ucmVwbGFjZSgv
KFtePTw+OiZhLXpdKS9nLCJcXCQxIik7Zis9IilcXHMqIjtyZXR1cm4gZn0oKSxMPS8mL2csTT0v
PC9nLE49Lz4vZyxYPS9cIi9nLGVhPS8mbHQ7L2csZmE9LyZndDsvZyxnYT0vJmFwb3M7L2csaGE9
LyZxdW90Oy9nLGphPS8mYW1wOy9nLGlhPS8mbmJzcDsvZyxrYT0vW1xyXG5dL2csSz1udWxsLGFh
PVJlZ0V4cCgiW148XSt8PCEtLVtcXHNcXFNdKj8tLVw+fDwhXFxbQ0RBVEFcXFtbXFxzXFxTXSo/
XFxdXFxdPnw8Lz9bYS16QS1aXSg/OltePlwiJ118J1teJ10qJ3xcIlteXCJdKlwiKSo+fDwiLCJn
IiksYmE9L148XCEtLS8sY2E9L148IVxbQ0RBVEFcWy8sZGE9L148YnJcYi9pLFc9L148KFwvPyko
W2EtekEtWl1bYS16QS1aMC05XSopLywKbGE9eCh7a2V5d29yZHM6ImJyZWFrIGNvbnRpbnVlIGRv
IGVsc2UgZm9yIGlmIHJldHVybiB3aGlsZSBhdXRvIGNhc2UgY2hhciBjb25zdCBkZWZhdWx0IGRv
dWJsZSBlbnVtIGV4dGVybiBmbG9hdCBnb3RvIGludCBsb25nIHJlZ2lzdGVyIHNob3J0IHNpZ25l
ZCBzaXplb2Ygc3RhdGljIHN0cnVjdCBzd2l0Y2ggdHlwZWRlZiB1bmlvbiB1bnNpZ25lZCB2b2lk
IHZvbGF0aWxlIGNhdGNoIGNsYXNzIGRlbGV0ZSBmYWxzZSBpbXBvcnQgbmV3IG9wZXJhdG9yIHBy
aXZhdGUgcHJvdGVjdGVkIHB1YmxpYyB0aGlzIHRocm93IHRydWUgdHJ5IHR5cGVvZiBhbGlnbm9m
IGFsaWduX3VuaW9uIGFzbSBheGlvbSBib29sIGNvbmNlcHQgY29uY2VwdF9tYXAgY29uc3RfY2Fz
dCBjb25zdGV4cHIgZGVjbHR5cGUgZHluYW1pY19jYXN0IGV4cGxpY2l0IGV4cG9ydCBmcmllbmQg
aW5saW5lIGxhdGVfY2hlY2sgbXV0YWJsZSBuYW1lc3BhY2UgbnVsbHB0ciByZWludGVycHJldF9j
YXN0IHN0YXRpY19hc3NlcnQgc3RhdGljX2Nhc3QgdGVtcGxhdGUgdHlwZWlkIHR5cGVuYW1lIHVz
aW5nIHZpcnR1YWwgd2NoYXJfdCB3aGVyZSBicmVhayBjb250aW51ZSBkbyBlbHNlIGZvciBpZiBy
ZXR1cm4gd2hpbGUgYXV0byBjYXNlIGNoYXIgY29uc3QgZGVmYXVsdCBkb3VibGUgZW51bSBleHRl
cm4gZmxvYXQgZ290byBpbnQgbG9uZyByZWdpc3RlciBzaG9ydCBzaWduZWQgc2l6ZW9mIHN0YXRp
YyBzdHJ1Y3Qgc3dpdGNoIHR5cGVkZWYgdW5pb24gdW5zaWduZWQgdm9pZCB2b2xhdGlsZSBjYXRj
aCBjbGFzcyBkZWxldGUgZmFsc2UgaW1wb3J0IG5ldyBvcGVyYXRvciBwcml2YXRlIHByb3RlY3Rl
ZCBwdWJsaWMgdGhpcyB0aHJvdyB0cnVlIHRyeSB0eXBlb2YgYWJzdHJhY3QgYm9vbGVhbiBieXRl
IGV4dGVuZHMgZmluYWwgZmluYWxseSBpbXBsZW1lbnRzIGltcG9ydCBpbnN0YW5jZW9mIG51bGwg
bmF0aXZlIHBhY2thZ2Ugc3RyaWN0ZnAgc3VwZXIgc3luY2hyb25pemVkIHRocm93cyB0cmFuc2ll
bnQgYXMgYmFzZSBieSBjaGVja2VkIGRlY2ltYWwgZGVsZWdhdGUgZGVzY2VuZGluZyBldmVudCBm
aXhlZCBmb3JlYWNoIGZyb20gZ3JvdXAgaW1wbGljaXQgaW4gaW50ZXJmYWNlIGludGVybmFsIGlu
dG8gaXMgbG9jayBvYmplY3Qgb3V0IG92ZXJyaWRlIG9yZGVyYnkgcGFyYW1zIHBhcnRpYWwgcmVh
ZG9ubHkgcmVmIHNieXRlIHNlYWxlZCBzdGFja2FsbG9jIHN0cmluZyBzZWxlY3QgdWludCB1bG9u
ZyB1bmNoZWNrZWQgdW5zYWZlIHVzaG9ydCB2YXIgYnJlYWsgY29udGludWUgZG8gZWxzZSBmb3Ig
aWYgcmV0dXJuIHdoaWxlIGF1dG8gY2FzZSBjaGFyIGNvbnN0IGRlZmF1bHQgZG91YmxlIGVudW0g
ZXh0ZXJuIGZsb2F0IGdvdG8gaW50IGxvbmcgcmVnaXN0ZXIgc2hvcnQgc2lnbmVkIHNpemVvZiBz
dGF0aWMgc3RydWN0IHN3aXRjaCB0eXBlZGVmIHVuaW9uIHVuc2lnbmVkIHZvaWQgdm9sYXRpbGUg
Y2F0Y2ggY2xhc3MgZGVsZXRlIGZhbHNlIGltcG9ydCBuZXcgb3BlcmF0b3IgcHJpdmF0ZSBwcm90
ZWN0ZWQgcHVibGljIHRoaXMgdGhyb3cgdHJ1ZSB0cnkgdHlwZW9mIGRlYnVnZ2VyIGV2YWwgZXhw
b3J0IGZ1bmN0aW9uIGdldCBudWxsIHNldCB1bmRlZmluZWQgdmFyIHdpdGggSW5maW5pdHkgTmFO
IGNhbGxlciBkZWxldGUgZGllIGRvIGR1bXAgZWxzaWYgZXZhbCBleGl0IGZvcmVhY2ggZm9yIGdv
dG8gaWYgaW1wb3J0IGxhc3QgbG9jYWwgbXkgbmV4dCBubyBvdXIgcHJpbnQgcGFja2FnZSByZWRv
IHJlcXVpcmUgc3ViIHVuZGVmIHVubGVzcyB1bnRpbCB1c2Ugd2FudGFycmF5IHdoaWxlIEJFR0lO
IEVORCBicmVhayBjb250aW51ZSBkbyBlbHNlIGZvciBpZiByZXR1cm4gd2hpbGUgYW5kIGFzIGFz
c2VydCBjbGFzcyBkZWYgZGVsIGVsaWYgZXhjZXB0IGV4ZWMgZmluYWxseSBmcm9tIGdsb2JhbCBp
bXBvcnQgaW4gaXMgbGFtYmRhIG5vbmxvY2FsIG5vdCBvciBwYXNzIHByaW50IHJhaXNlIHRyeSB3
aXRoIHlpZWxkIEZhbHNlIFRydWUgTm9uZSBicmVhayBjb250aW51ZSBkbyBlbHNlIGZvciBpZiBy
ZXR1cm4gd2hpbGUgYWxpYXMgYW5kIGJlZ2luIGNhc2UgY2xhc3MgZGVmIGRlZmluZWQgZWxzaWYg
ZW5kIGVuc3VyZSBmYWxzZSBpbiBtb2R1bGUgbmV4dCBuaWwgbm90IG9yIHJlZG8gcmVzY3VlIHJl
dHJ5IHNlbGYgc3VwZXIgdGhlbiB0cnVlIHVuZGVmIHVubGVzcyB1bnRpbCB3aGVuIHlpZWxkIEJF
R0lOIEVORCBicmVhayBjb250aW51ZSBkbyBlbHNlIGZvciBpZiByZXR1cm4gd2hpbGUgY2FzZSBk
b25lIGVsaWYgZXNhYyBldmFsIGZpIGZ1bmN0aW9uIGluIGxvY2FsIHNldCB0aGVuIHVudGlsICIs
Cmhhc2hDb21tZW50czp0cnVlLGNTdHlsZUNvbW1lbnRzOnRydWUsbXVsdGlMaW5lU3RyaW5nczp0
cnVlLHJlZ2V4TGl0ZXJhbHM6dHJ1ZX0pLEc9e307dShsYSxbImRlZmF1bHQtY29kZSJdKTt1KEIo
W10sW1t6LC9eW148P10rL10sWyJkZWMiLC9ePCFcd1tePl0qKD86PnwkKS9dLFtDLC9ePFwhLS1b
XHNcU10qPyg/Oi1cLT58JCkvXSxbImxhbmctIiwvXjxcPyhbXHNcU10rPykoPzpcPz58JCkvXSxb
ImxhbmctIiwvXjwlKFtcc1xTXSs/KSg/OiU+fCQpL10sW0UsL14oPzo8WyU/XXxbJT9dPikvXSxb
ImxhbmctIiwvXjx4bXBcYltePl0qPihbXHNcU10rPyk8XC94bXBcYltePl0qPi9pXSxbImxhbmct
anMiLC9ePHNjcmlwdFxiW14+XSo+KFtcc1xTXSo/KSg8XC9zY3JpcHRcYltePl0qPikvaV0sWyJs
YW5nLWNzcyIsL148c3R5bGVcYltePl0qPihbXHNcU10qPykoPFwvc3R5bGVcYltePl0qPikvaV0s
WyJsYW5nLWluLnRhZyIsL14oPFwvP1thLXpdW148Pl0qPikvaV1dKSxbImRlZmF1bHQtbWFya3Vw
IiwKImh0bSIsImh0bWwiLCJteG1sIiwieGh0bWwiLCJ4bWwiLCJ4c2wiXSk7dShCKFtbeiwvXltc
c10rLyxudWxsLCIgXHRcclxuIl0sWyJhdHYiLC9eKD86XCJbXlwiXSpcIj98XCdbXlwnXSpcJz8p
LyxudWxsLCJcIiciXV0sW1sidGFnIiwvXl48XC8/W2Etel0oPzpbXHcuOi1dKlx3KT98XC8/PiQv
aV0sWyJhdG4iLC9eKD8hc3R5bGVbXHM9XXxvbilbYS16XSg/OltcdzotXSpcdyk/L2ldLFsibGFu
Zy11cS52YWwiLC9ePVxzKihbXj5cJ1wiXHNdKig/OltePlwnXCJcc1wvXXxcLyg/PVxzKSkpL10s
W0UsL15bPTw+XC9dKy9dLFsibGFuZy1qcyIsL15vblx3K1xzKj1ccypcIihbXlwiXSspXCIvaV0s
WyJsYW5nLWpzIiwvXm9uXHcrXHMqPVxzKlwnKFteXCddKylcJy9pXSxbImxhbmctanMiLC9eb25c
dytccyo9XHMqKFteXCJcJz5cc10rKS9pXSxbImxhbmctY3NzIiwvXnN0eWxlXHMqPVxzKlwiKFte
XCJdKylcIi9pXSxbImxhbmctY3NzIiwvXnN0eWxlXHMqPVxzKlwnKFteXCddKylcJy9pXSwKWyJs
YW5nLWNzcyIsL15zdHlsZVxzKj1ccyooW15cIlwnPlxzXSspL2ldXSksWyJpbi50YWciXSk7dShC
KFtdLFtbImF0diIsL15bXHNcU10rL11dKSxbInVxLnZhbCJdKTt1KHgoe2tleXdvcmRzOiJicmVh
ayBjb250aW51ZSBkbyBlbHNlIGZvciBpZiByZXR1cm4gd2hpbGUgYXV0byBjYXNlIGNoYXIgY29u
c3QgZGVmYXVsdCBkb3VibGUgZW51bSBleHRlcm4gZmxvYXQgZ290byBpbnQgbG9uZyByZWdpc3Rl
ciBzaG9ydCBzaWduZWQgc2l6ZW9mIHN0YXRpYyBzdHJ1Y3Qgc3dpdGNoIHR5cGVkZWYgdW5pb24g
dW5zaWduZWQgdm9pZCB2b2xhdGlsZSBjYXRjaCBjbGFzcyBkZWxldGUgZmFsc2UgaW1wb3J0IG5l
dyBvcGVyYXRvciBwcml2YXRlIHByb3RlY3RlZCBwdWJsaWMgdGhpcyB0aHJvdyB0cnVlIHRyeSB0
eXBlb2YgYWxpZ25vZiBhbGlnbl91bmlvbiBhc20gYXhpb20gYm9vbCBjb25jZXB0IGNvbmNlcHRf
bWFwIGNvbnN0X2Nhc3QgY29uc3RleHByIGRlY2x0eXBlIGR5bmFtaWNfY2FzdCBleHBsaWNpdCBl
eHBvcnQgZnJpZW5kIGlubGluZSBsYXRlX2NoZWNrIG11dGFibGUgbmFtZXNwYWNlIG51bGxwdHIg
cmVpbnRlcnByZXRfY2FzdCBzdGF0aWNfYXNzZXJ0IHN0YXRpY19jYXN0IHRlbXBsYXRlIHR5cGVp
ZCB0eXBlbmFtZSB1c2luZyB2aXJ0dWFsIHdjaGFyX3Qgd2hlcmUgIiwKaGFzaENvbW1lbnRzOnRy
dWUsY1N0eWxlQ29tbWVudHM6dHJ1ZX0pLFsiYyIsImNjIiwiY3BwIiwiY3h4IiwiY3ljIiwibSJd
KTt1KHgoe2tleXdvcmRzOiJudWxsIHRydWUgZmFsc2UifSksWyJqc29uIl0pO3UoeCh7a2V5d29y
ZHM6ImJyZWFrIGNvbnRpbnVlIGRvIGVsc2UgZm9yIGlmIHJldHVybiB3aGlsZSBhdXRvIGNhc2Ug
Y2hhciBjb25zdCBkZWZhdWx0IGRvdWJsZSBlbnVtIGV4dGVybiBmbG9hdCBnb3RvIGludCBsb25n
IHJlZ2lzdGVyIHNob3J0IHNpZ25lZCBzaXplb2Ygc3RhdGljIHN0cnVjdCBzd2l0Y2ggdHlwZWRl
ZiB1bmlvbiB1bnNpZ25lZCB2b2lkIHZvbGF0aWxlIGNhdGNoIGNsYXNzIGRlbGV0ZSBmYWxzZSBp
bXBvcnQgbmV3IG9wZXJhdG9yIHByaXZhdGUgcHJvdGVjdGVkIHB1YmxpYyB0aGlzIHRocm93IHRy
dWUgdHJ5IHR5cGVvZiBhYnN0cmFjdCBib29sZWFuIGJ5dGUgZXh0ZW5kcyBmaW5hbCBmaW5hbGx5
IGltcGxlbWVudHMgaW1wb3J0IGluc3RhbmNlb2YgbnVsbCBuYXRpdmUgcGFja2FnZSBzdHJpY3Rm
cCBzdXBlciBzeW5jaHJvbml6ZWQgdGhyb3dzIHRyYW5zaWVudCBhcyBiYXNlIGJ5IGNoZWNrZWQg
ZGVjaW1hbCBkZWxlZ2F0ZSBkZXNjZW5kaW5nIGV2ZW50IGZpeGVkIGZvcmVhY2ggZnJvbSBncm91
cCBpbXBsaWNpdCBpbiBpbnRlcmZhY2UgaW50ZXJuYWwgaW50byBpcyBsb2NrIG9iamVjdCBvdXQg
b3ZlcnJpZGUgb3JkZXJieSBwYXJhbXMgcGFydGlhbCByZWFkb25seSByZWYgc2J5dGUgc2VhbGVk
IHN0YWNrYWxsb2Mgc3RyaW5nIHNlbGVjdCB1aW50IHVsb25nIHVuY2hlY2tlZCB1bnNhZmUgdXNo
b3J0IHZhciAiLApoYXNoQ29tbWVudHM6dHJ1ZSxjU3R5bGVDb21tZW50czp0cnVlLHZlcmJhdGlt
U3RyaW5nczp0cnVlfSksWyJjcyJdKTt1KHgoe2tleXdvcmRzOiJicmVhayBjb250aW51ZSBkbyBl
bHNlIGZvciBpZiByZXR1cm4gd2hpbGUgYXV0byBjYXNlIGNoYXIgY29uc3QgZGVmYXVsdCBkb3Vi
bGUgZW51bSBleHRlcm4gZmxvYXQgZ290byBpbnQgbG9uZyByZWdpc3RlciBzaG9ydCBzaWduZWQg
c2l6ZW9mIHN0YXRpYyBzdHJ1Y3Qgc3dpdGNoIHR5cGVkZWYgdW5pb24gdW5zaWduZWQgdm9pZCB2
b2xhdGlsZSBjYXRjaCBjbGFzcyBkZWxldGUgZmFsc2UgaW1wb3J0IG5ldyBvcGVyYXRvciBwcml2
YXRlIHByb3RlY3RlZCBwdWJsaWMgdGhpcyB0aHJvdyB0cnVlIHRyeSB0eXBlb2YgYWJzdHJhY3Qg
Ym9vbGVhbiBieXRlIGV4dGVuZHMgZmluYWwgZmluYWxseSBpbXBsZW1lbnRzIGltcG9ydCBpbnN0
YW5jZW9mIG51bGwgbmF0aXZlIHBhY2thZ2Ugc3RyaWN0ZnAgc3VwZXIgc3luY2hyb25pemVkIHRo
cm93cyB0cmFuc2llbnQgIiwKY1N0eWxlQ29tbWVudHM6dHJ1ZX0pLFsiamF2YSJdKTt1KHgoe2tl
eXdvcmRzOiJicmVhayBjb250aW51ZSBkbyBlbHNlIGZvciBpZiByZXR1cm4gd2hpbGUgY2FzZSBk
b25lIGVsaWYgZXNhYyBldmFsIGZpIGZ1bmN0aW9uIGluIGxvY2FsIHNldCB0aGVuIHVudGlsICIs
aGFzaENvbW1lbnRzOnRydWUsbXVsdGlMaW5lU3RyaW5nczp0cnVlfSksWyJic2giLCJjc2giLCJz
aCJdKTt1KHgoe2tleXdvcmRzOiJicmVhayBjb250aW51ZSBkbyBlbHNlIGZvciBpZiByZXR1cm4g
d2hpbGUgYW5kIGFzIGFzc2VydCBjbGFzcyBkZWYgZGVsIGVsaWYgZXhjZXB0IGV4ZWMgZmluYWxs
eSBmcm9tIGdsb2JhbCBpbXBvcnQgaW4gaXMgbGFtYmRhIG5vbmxvY2FsIG5vdCBvciBwYXNzIHBy
aW50IHJhaXNlIHRyeSB3aXRoIHlpZWxkIEZhbHNlIFRydWUgTm9uZSAiLGhhc2hDb21tZW50czp0
cnVlLG11bHRpTGluZVN0cmluZ3M6dHJ1ZSx0cmlwbGVRdW90ZWRTdHJpbmdzOnRydWV9KSxbImN2
IiwicHkiXSk7CnUoeCh7a2V5d29yZHM6ImNhbGxlciBkZWxldGUgZGllIGRvIGR1bXAgZWxzaWYg
ZXZhbCBleGl0IGZvcmVhY2ggZm9yIGdvdG8gaWYgaW1wb3J0IGxhc3QgbG9jYWwgbXkgbmV4dCBu
byBvdXIgcHJpbnQgcGFja2FnZSByZWRvIHJlcXVpcmUgc3ViIHVuZGVmIHVubGVzcyB1bnRpbCB1
c2Ugd2FudGFycmF5IHdoaWxlIEJFR0lOIEVORCAiLGhhc2hDb21tZW50czp0cnVlLG11bHRpTGlu
ZVN0cmluZ3M6dHJ1ZSxyZWdleExpdGVyYWxzOnRydWV9KSxbInBlcmwiLCJwbCIsInBtIl0pO3Uo
eCh7a2V5d29yZHM6ImJyZWFrIGNvbnRpbnVlIGRvIGVsc2UgZm9yIGlmIHJldHVybiB3aGlsZSBh
bGlhcyBhbmQgYmVnaW4gY2FzZSBjbGFzcyBkZWYgZGVmaW5lZCBlbHNpZiBlbmQgZW5zdXJlIGZh
bHNlIGluIG1vZHVsZSBuZXh0IG5pbCBub3Qgb3IgcmVkbyByZXNjdWUgcmV0cnkgc2VsZiBzdXBl
ciB0aGVuIHRydWUgdW5kZWYgdW5sZXNzIHVudGlsIHdoZW4geWllbGQgQkVHSU4gRU5EICIsaGFz
aENvbW1lbnRzOnRydWUsCm11bHRpTGluZVN0cmluZ3M6dHJ1ZSxyZWdleExpdGVyYWxzOnRydWV9
KSxbInJiIl0pO3UoeCh7a2V5d29yZHM6ImJyZWFrIGNvbnRpbnVlIGRvIGVsc2UgZm9yIGlmIHJl
dHVybiB3aGlsZSBhdXRvIGNhc2UgY2hhciBjb25zdCBkZWZhdWx0IGRvdWJsZSBlbnVtIGV4dGVy
biBmbG9hdCBnb3RvIGludCBsb25nIHJlZ2lzdGVyIHNob3J0IHNpZ25lZCBzaXplb2Ygc3RhdGlj
IHN0cnVjdCBzd2l0Y2ggdHlwZWRlZiB1bmlvbiB1bnNpZ25lZCB2b2lkIHZvbGF0aWxlIGNhdGNo
IGNsYXNzIGRlbGV0ZSBmYWxzZSBpbXBvcnQgbmV3IG9wZXJhdG9yIHByaXZhdGUgcHJvdGVjdGVk
IHB1YmxpYyB0aGlzIHRocm93IHRydWUgdHJ5IHR5cGVvZiBkZWJ1Z2dlciBldmFsIGV4cG9ydCBm
dW5jdGlvbiBnZXQgbnVsbCBzZXQgdW5kZWZpbmVkIHZhciB3aXRoIEluZmluaXR5IE5hTiAiLGNT
dHlsZUNvbW1lbnRzOnRydWUscmVnZXhMaXRlcmFsczp0cnVlfSksWyJqcyJdKTt1KEIoW10sW1tB
LC9eW1xzXFNdKy9dXSksClsicmVnZXgiXSk7d2luZG93LlBSX25vcm1hbGl6ZWRIdG1sPUg7d2lu
ZG93LnByZXR0eVByaW50T25lPWZ1bmN0aW9uKGIsZil7dmFyIGk9e2Y6YixlOmZ9O1UoaSk7cmV0
dXJuIGkuYX07d2luZG93LnByZXR0eVByaW50PWZ1bmN0aW9uKGIpe2Z1bmN0aW9uIGYoKXtmb3Io
dmFyIHQ9d2luZG93LlBSX1NIT1VMRF9VU0VfQ09OVElOVUFUSU9OP2oubm93KCkrMjUwOkluZmlu
aXR5O3E8by5sZW5ndGgmJmoubm93KCk8dDtxKyspe3ZhciBwPW9bcV07aWYocC5jbGFzc05hbWUm
JnAuY2xhc3NOYW1lLmluZGV4T2YoInByZXR0eXByaW50Iik+PTApe3ZhciBjPXAuY2xhc3NOYW1l
Lm1hdGNoKC9cYmxhbmctKFx3KylcYi8pO2lmKGMpYz1jWzFdO2Zvcih2YXIgZD1mYWxzZSxhPXAu
cGFyZW50Tm9kZTthO2E9YS5wYXJlbnROb2RlKWlmKChhLnRhZ05hbWU9PT0icHJlInx8YS50YWdO
YW1lPT09ImNvZGUifHxhLnRhZ05hbWU9PT0ieG1wIikmJmEuY2xhc3NOYW1lJiZhLmNsYXNzTmFt
ZS5pbmRleE9mKCJwcmV0dHlwcmludCIpPj0KMCl7ZD10cnVlO2JyZWFrfWlmKCFkKXthPXA7aWYo
bnVsbD09PUspe2Q9ZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgiUFJFIik7ZC5hcHBlbmRDaGlsZChk
b2N1bWVudC5jcmVhdGVUZXh0Tm9kZSgnPCFET0NUWVBFIGZvbyBQVUJMSUMgImZvbyBiYXIiPlxu
PGZvbyAvPicpKTtLPSEvPC8udGVzdChkLmlubmVySFRNTCl9aWYoSyl7ZD1hLmlubmVySFRNTDtp
ZigiWE1QIj09PWEudGFnTmFtZSlkPXkoZCk7ZWxzZXthPWE7aWYoIlBSRSI9PT1hLnRhZ05hbWUp
YT10cnVlO2Vsc2UgaWYoa2EudGVzdChkKSl7dmFyIGs9IiI7aWYoYS5jdXJyZW50U3R5bGUpaz1h
LmN1cnJlbnRTdHlsZS53aGl0ZVNwYWNlO2Vsc2UgaWYod2luZG93LmdldENvbXB1dGVkU3R5bGUp
az13aW5kb3cuZ2V0Q29tcHV0ZWRTdHlsZShhLG51bGwpLndoaXRlU3BhY2U7YT0ha3x8az09PSJw
cmUifWVsc2UgYT10cnVlO2F8fChkPWQucmVwbGFjZSgvKDxiclxzKlwvPz4pW1xyXG5dKy9nLCIk
MSIpLnJlcGxhY2UoLyg/OltcclxuXStbIFx0XSopKy9nLAoiICIpKX1kPWR9ZWxzZXtkPVtdO2Zv
cihhPWEuZmlyc3RDaGlsZDthO2E9YS5uZXh0U2libGluZylIKGEsZCk7ZD1kLmpvaW4oIiIpfWQ9
ZC5yZXBsYWNlKC8oPzpcclxuP3xcbikkLywiIik7bT17ZjpkLGU6YyxiOnB9O1UobSk7aWYocD1t
LmEpe2M9bS5iO2lmKCJYTVAiPT09Yy50YWdOYW1lKXtkPWRvY3VtZW50LmNyZWF0ZUVsZW1lbnQo
IlBSRSIpO2ZvcihhPTA7YTxjLmF0dHJpYnV0ZXMubGVuZ3RoOysrYSl7az1jLmF0dHJpYnV0ZXNb
YV07aWYoay5zcGVjaWZpZWQpaWYoay5uYW1lLnRvTG93ZXJDYXNlKCk9PT0iY2xhc3MiKWQuY2xh
c3NOYW1lPWsudmFsdWU7ZWxzZSBkLnNldEF0dHJpYnV0ZShrLm5hbWUsay52YWx1ZSl9ZC5pbm5l
ckhUTUw9cDtjLnBhcmVudE5vZGUucmVwbGFjZUNoaWxkKGQsYyl9ZWxzZSBjLmlubmVySFRNTD1w
fX19fWlmKHE8by5sZW5ndGgpc2V0VGltZW91dChmLDI1MCk7ZWxzZSBiJiZiKCl9Zm9yKHZhciBp
PVtkb2N1bWVudC5nZXRFbGVtZW50c0J5VGFnTmFtZSgicHJlIiksCmRvY3VtZW50LmdldEVsZW1l
bnRzQnlUYWdOYW1lKCJjb2RlIiksZG9jdW1lbnQuZ2V0RWxlbWVudHNCeVRhZ05hbWUoInhtcCIp
XSxvPVtdLGw9MDtsPGkubGVuZ3RoOysrbClmb3IodmFyIG49MCxyPWlbbF0ubGVuZ3RoO248cjsr
K24pby5wdXNoKGlbbF1bbl0pO2k9bnVsbDt2YXIgaj1EYXRlO2oubm93fHwoaj17bm93OmZ1bmN0
aW9uKCl7cmV0dXJuKG5ldyBEYXRlKS5nZXRUaW1lKCl9fSk7dmFyIHE9MCxtO2YoKX07d2luZG93
LlBSPXtjb21iaW5lUHJlZml4UGF0dGVybnM6TyxjcmVhdGVTaW1wbGVMZXhlcjpCLHJlZ2lzdGVy
TGFuZ0hhbmRsZXI6dSxzb3VyY2VEZWNvcmF0b3I6eCxQUl9BVFRSSUJfTkFNRToiYXRuIixQUl9B
VFRSSUJfVkFMVUU6ImF0diIsUFJfQ09NTUVOVDpDLFBSX0RFQ0xBUkFUSU9OOiJkZWMiLFBSX0tF
WVdPUkQ6UixQUl9MSVRFUkFMOkosUFJfTk9DT0RFOlYsUFJfUExBSU46eixQUl9QVU5DVFVBVElP
TjpFLFBSX1NPVVJDRTpQLFBSX1NUUklORzpBLApQUl9UQUc6InRhZyIsUFJfVFlQRTpTfX0pKCk=

__END__

=head1 NAME

Mojolicious::Static - Serve Static Files

=head1 SYNOPSIS

    use Mojolicious::Static;

=head1 DESCRIPTION

L<Mojolicious::Static> is a dispatcher for static files with C<Range> and
C<If-Modified-Since> support.

=head1 FILES

L<Mojolicious::Static> has a few popular static files bundled.

=head2 C<favicon.ico>

Mojolicious favicon.

    Copyright (C) 2010, Sebastian Riedel.

Licensed under the CC-NC-ND License, Version 3.0
L<http://creativecommons.org/licenses/by-nc-nd/3.0>.

=head2 C<mojolicious-black.png>

Black Mojolicious logo.

    Copyright (C) 2010, Sebastian Riedel.

Licensed under the CC-NC-ND License, Version 3.0
L<http://creativecommons.org/licenses/by-nc-nd/3.0>.

=head2 C<css/prettify-mojo.css>

Mojolicious theme for C<prettify.js>.

    Copyright (C) 2010, Sebastian Riedel.

Licensed under the CC-NC-ND License, Version 3.0
L<http://creativecommons.org/licenses/by-nc-nd/3.0>.

=head2 C</js/jquery.js>

   Version 1.4.4

jQuery is a fast and concise JavaScript Library that simplifies HTML document
traversing, event handling, animating, and Ajax interactions for rapid web
development. jQuery is designed to change the way that you write JavaScript.

    Copyright 2010, John Resig.

Licensed under the MIT License, L<http://creativecommons.org/licenses/MIT>.

=head2 C</js/prettify.js>

    Version 21-Jul-2010

A Javascript module and CSS file that allows syntax highlighting of source
code snippets in an html page.

    Copyright (C) 2006, Google Inc.

Licensed under the Apache License, Version 2.0
L<http://www.apache.org/licenses/LICENSE-2.0>.

=head1 ATTRIBUTES

L<Mojolicious::Static> implements the following attributes.

=head2 C<default_static_class>

    my $class = $static->default_static_class;
    $static   = $static->default_static_class('main');

The dispatcher will use this class to look for files in the C<DATA> section.

=head2 C<prefix>

    my $prefix = $static->prefix;
    $static    = $static->prefix('/static');

Prefix path to remove from incoming paths before dispatching.

=head2 C<root>

    my $root = $static->root;
    $static  = $static->root('/foo/bar/files');

Directory to serve static files from.

=head1 METHODS

L<Mojolicious::Static> inherits all methods from L<Mojo::Base>
and implements the following ones.

=head2 C<dispatch>

    my $success = $static->dispatch($c);

Dispatch a L<Mojolicious::Controller> object.

=head2 C<serve>

    my $success = $static->serve($c, 'foo/bar.html');

Serve a specific file.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
