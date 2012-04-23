package Mojo::Util;
use Mojo::Base 'Exporter';

use Digest::MD5 qw/md5 md5_hex/;
use Digest::SHA qw/sha1 sha1_hex/;
use Encode 'find_encoding';
use MIME::Base64 qw/decode_base64 encode_base64/;
use MIME::QuotedPrint qw/decode_qp encode_qp/;

# Punycode bootstring parameters
use constant {
  PC_BASE         => 36,
  PC_TMIN         => 1,
  PC_TMAX         => 26,
  PC_SKEW         => 38,
  PC_DAMP         => 700,
  PC_INITIAL_BIAS => 72,
  PC_INITIAL_N    => 128
};

# Punycode delimiter
my $DELIMITER = chr 0x2D;

# HTML5 entities for html_unescape (without "apos")
my %ENTITIES = (
  'aacgr;'                           => "\x{03ac}",
  'Aacgr;'                           => "\x{0386}",
  'aacute'                           => "\x{00e1}",
  'aacute;'                          => "\x{00e1}",
  'Aacute'                           => "\x{00c1}",
  'Aacute;'                          => "\x{00c1}",
  'abreve;'                          => "\x{0103}",
  'Abreve;'                          => "\x{0102}",
  'ac;'                              => "\x{223e}",
  'acd;'                             => "\x{223f}",
  'acE;'                             => "\x{223f}",
  'acirc'                            => "\x{00e2}",
  'acirc;'                           => "\x{00e2}",
  'Acirc'                            => "\x{00c2}",
  'Acirc;'                           => "\x{00c2}",
  'acute'                            => "\x{00b4}",
  'acute;'                           => "\x{00b4}",
  'acy;'                             => "\x{0430}",
  'Acy;'                             => "\x{0410}",
  'aelig'                            => "\x{00e6}",
  'aelig;'                           => "\x{00e6}",
  'AElig'                            => "\x{00c6}",
  'AElig;'                           => "\x{00c6}",
  'af;'                              => "\x{2061}",
  'afr;'                             => "\x{1d51e}",
  'Afr;'                             => "\x{1d504}",
  'agr;'                             => "\x{03b1}",
  'Agr;'                             => "\x{0391}",
  'agrave'                           => "\x{00e0}",
  'agrave;'                          => "\x{00e0}",
  'Agrave'                           => "\x{00c0}",
  'Agrave;'                          => "\x{00c0}",
  'alefsym;'                         => "\x{2135}",
  'aleph;'                           => "\x{2135}",
  'alpha;'                           => "\x{03b1}",
  'Alpha;'                           => "\x{0391}",
  'amacr;'                           => "\x{0101}",
  'Amacr;'                           => "\x{0100}",
  'amalg;'                           => "\x{2a3f}",
  'amp'                              => "\x{0026}",
  'amp;'                             => "\x{0026}",
  'AMP'                              => "\x{0026}",
  'AMP;'                             => "\x{0026}",
  'and;'                             => "\x{2227}",
  'And;'                             => "\x{2a53}",
  'andand;'                          => "\x{2a55}",
  'andd;'                            => "\x{2a5c}",
  'andslope;'                        => "\x{2a58}",
  'andv;'                            => "\x{2a5a}",
  'ang;'                             => "\x{2220}",
  'ange;'                            => "\x{29a4}",
  'angle;'                           => "\x{2220}",
  'angmsd;'                          => "\x{2221}",
  'angmsdaa;'                        => "\x{29a8}",
  'angmsdab;'                        => "\x{29a9}",
  'angmsdac;'                        => "\x{29aa}",
  'angmsdad;'                        => "\x{29ab}",
  'angmsdae;'                        => "\x{29ac}",
  'angmsdaf;'                        => "\x{29ad}",
  'angmsdag;'                        => "\x{29ae}",
  'angmsdah;'                        => "\x{29af}",
  'angrt;'                           => "\x{221f}",
  'angrtvb;'                         => "\x{22be}",
  'angrtvbd;'                        => "\x{299d}",
  'angsph;'                          => "\x{2222}",
  'angst;'                           => "\x{00c5}",
  'angzarr;'                         => "\x{237c}",
  'aogon;'                           => "\x{0105}",
  'Aogon;'                           => "\x{0104}",
  'aopf;'                            => "\x{1d552}",
  'Aopf;'                            => "\x{1d538}",
  'ap;'                              => "\x{2248}",
  'apacir;'                          => "\x{2a6f}",
  'ape;'                             => "\x{224a}",
  'apE;'                             => "\x{2a70}",
  'apid;'                            => "\x{224b}",
  '#39;'                             => "\x{0027}",
  'ApplyFunction;'                   => "\x{2061}",
  'approx;'                          => "\x{2248}",
  'approxeq;'                        => "\x{224a}",
  'aring'                            => "\x{00e5}",
  'aring;'                           => "\x{00e5}",
  'Aring'                            => "\x{00c5}",
  'Aring;'                           => "\x{00c5}",
  'ascr;'                            => "\x{1d4b6}",
  'Ascr;'                            => "\x{1d49c}",
  'Assign;'                          => "\x{2254}",
  'ast;'                             => "\x{002a}",
  'asymp;'                           => "\x{2248}",
  'asympeq;'                         => "\x{224d}",
  'atilde'                           => "\x{00e3}",
  'atilde;'                          => "\x{00e3}",
  'Atilde'                           => "\x{00c3}",
  'Atilde;'                          => "\x{00c3}",
  'auml'                             => "\x{00e4}",
  'auml;'                            => "\x{00e4}",
  'Auml'                             => "\x{00c4}",
  'Auml;'                            => "\x{00c4}",
  'awconint;'                        => "\x{2233}",
  'awint;'                           => "\x{2a11}",
  'b.alpha;'                         => "\x{1d6c2}",
  'b.beta;'                          => "\x{1d6c3}",
  'b.chi;'                           => "\x{1d6d8}",
  'b.delta;'                         => "\x{1d6c5}",
  'b.Delta;'                         => "\x{1d6ab}",
  'b.epsi;'                          => "\x{1d6c6}",
  'b.epsiv;'                         => "\x{1d6dc}",
  'b.eta;'                           => "\x{1d6c8}",
  'b.gamma;'                         => "\x{1d6c4}",
  'b.Gamma;'                         => "\x{1d6aa}",
  'b.gammad;'                        => "\x{1d7cb}",
  'b.Gammad;'                        => "\x{1d7ca}",
  'b.iota;'                          => "\x{1d6ca}",
  'b.kappa;'                         => "\x{1d6cb}",
  'b.kappav;'                        => "\x{1d6de}",
  'b.lambda;'                        => "\x{1d6cc}",
  'b.Lambda;'                        => "\x{1d6b2}",
  'b.mu;'                            => "\x{1d6cd}",
  'b.nu;'                            => "\x{1d6ce}",
  'b.omega;'                         => "\x{1d6da}",
  'b.Omega;'                         => "\x{1d6c0}",
  'b.phi;'                           => "\x{1d6d7}",
  'b.Phi;'                           => "\x{1d6bd}",
  'b.phiv;'                          => "\x{1d6df}",
  'b.pi;'                            => "\x{1d6d1}",
  'b.Pi;'                            => "\x{1d6b7}",
  'b.piv;'                           => "\x{1d6e1}",
  'b.psi;'                           => "\x{1d6d9}",
  'b.Psi;'                           => "\x{1d6bf}",
  'b.rho;'                           => "\x{1d6d2}",
  'b.rhov;'                          => "\x{1d6e0}",
  'b.sigma;'                         => "\x{1d6d4}",
  'b.Sigma;'                         => "\x{1d6ba}",
  'b.sigmav;'                        => "\x{1d6d3}",
  'b.tau;'                           => "\x{1d6d5}",
  'b.Theta;'                         => "\x{1d6af}",
  'b.thetas;'                        => "\x{1d6c9}",
  'b.thetav;'                        => "\x{1d6dd}",
  'b.upsi;'                          => "\x{1d6d6}",
  'b.Upsi;'                          => "\x{1d6bc}",
  'b.xi;'                            => "\x{1d6cf}",
  'b.Xi;'                            => "\x{1d6b5}",
  'b.zeta;'                          => "\x{1d6c7}",
  'backcong;'                        => "\x{224c}",
  'backepsilon;'                     => "\x{03f6}",
  'backprime;'                       => "\x{2035}",
  'backsim;'                         => "\x{223d}",
  'backsimeq;'                       => "\x{22cd}",
  'Backslash;'                       => "\x{2216}",
  'Barv;'                            => "\x{2ae7}",
  'barvee;'                          => "\x{22bd}",
  'barwed;'                          => "\x{2305}",
  'Barwed;'                          => "\x{2306}",
  'barwedge;'                        => "\x{2305}",
  'bbrk;'                            => "\x{23b5}",
  'bbrktbrk;'                        => "\x{23b6}",
  'bcong;'                           => "\x{224c}",
  'bcy;'                             => "\x{0431}",
  'Bcy;'                             => "\x{0411}",
  'bdquo;'                           => "\x{201e}",
  'becaus;'                          => "\x{2235}",
  'because;'                         => "\x{2235}",
  'Because;'                         => "\x{2235}",
  'bemptyv;'                         => "\x{29b0}",
  'bepsi;'                           => "\x{03f6}",
  'bernou;'                          => "\x{212c}",
  'Bernoullis;'                      => "\x{212c}",
  'beta;'                            => "\x{03b2}",
  'Beta;'                            => "\x{0392}",
  'beth;'                            => "\x{2136}",
  'between;'                         => "\x{226c}",
  'bfr;'                             => "\x{1d51f}",
  'Bfr;'                             => "\x{1d505}",
  'bgr;'                             => "\x{03b2}",
  'Bgr;'                             => "\x{0392}",
  'bigcap;'                          => "\x{22c2}",
  'bigcirc;'                         => "\x{25ef}",
  'bigcup;'                          => "\x{22c3}",
  'bigodot;'                         => "\x{2a00}",
  'bigoplus;'                        => "\x{2a01}",
  'bigotimes;'                       => "\x{2a02}",
  'bigsqcup;'                        => "\x{2a06}",
  'bigstar;'                         => "\x{2605}",
  'bigtriangledown;'                 => "\x{25bd}",
  'bigtriangleup;'                   => "\x{25b3}",
  'biguplus;'                        => "\x{2a04}",
  'bigvee;'                          => "\x{22c1}",
  'bigwedge;'                        => "\x{22c0}",
  'bkarow;'                          => "\x{290d}",
  'blacklozenge;'                    => "\x{29eb}",
  'blacksquare;'                     => "\x{25aa}",
  'blacktriangle;'                   => "\x{25b4}",
  'blacktriangledown;'               => "\x{25be}",
  'blacktriangleleft;'               => "\x{25c2}",
  'blacktriangleright;'              => "\x{25b8}",
  'blank;'                           => "\x{2423}",
  'blk12;'                           => "\x{2592}",
  'blk14;'                           => "\x{2591}",
  'blk34;'                           => "\x{2593}",
  'block;'                           => "\x{2588}",
  'bne;'                             => "\x{2588}",
  'bnequiv;'                         => "\x{2588}",
  'bnot;'                            => "\x{2310}",
  'bNot;'                            => "\x{2aed}",
  'bopf;'                            => "\x{1d553}",
  'Bopf;'                            => "\x{1d539}",
  'bot;'                             => "\x{22a5}",
  'bottom;'                          => "\x{22a5}",
  'bowtie;'                          => "\x{22c8}",
  'boxbox;'                          => "\x{29c9}",
  'boxdl;'                           => "\x{2510}",
  'boxdL;'                           => "\x{2555}",
  'boxDl;'                           => "\x{2556}",
  'boxDL;'                           => "\x{2557}",
  'boxdr;'                           => "\x{250c}",
  'boxdR;'                           => "\x{2552}",
  'boxDr;'                           => "\x{2553}",
  'boxDR;'                           => "\x{2554}",
  'boxh;'                            => "\x{2500}",
  'boxH;'                            => "\x{2550}",
  'boxhd;'                           => "\x{252c}",
  'boxhD;'                           => "\x{2565}",
  'boxHd;'                           => "\x{2564}",
  'boxHD;'                           => "\x{2566}",
  'boxhu;'                           => "\x{2534}",
  'boxhU;'                           => "\x{2568}",
  'boxHu;'                           => "\x{2567}",
  'boxHU;'                           => "\x{2569}",
  'boxminus;'                        => "\x{229f}",
  'boxplus;'                         => "\x{229e}",
  'boxtimes;'                        => "\x{22a0}",
  'boxul;'                           => "\x{2518}",
  'boxuL;'                           => "\x{255b}",
  'boxUl;'                           => "\x{255c}",
  'boxUL;'                           => "\x{255d}",
  'boxur;'                           => "\x{2514}",
  'boxuR;'                           => "\x{2558}",
  'boxUr;'                           => "\x{2559}",
  'boxUR;'                           => "\x{255a}",
  'boxv;'                            => "\x{2502}",
  'boxV;'                            => "\x{2551}",
  'boxvh;'                           => "\x{253c}",
  'boxvH;'                           => "\x{256a}",
  'boxVh;'                           => "\x{256b}",
  'boxVH;'                           => "\x{256c}",
  'boxvl;'                           => "\x{2524}",
  'boxvL;'                           => "\x{2561}",
  'boxVl;'                           => "\x{2562}",
  'boxVL;'                           => "\x{2563}",
  'boxvr;'                           => "\x{251c}",
  'boxvR;'                           => "\x{255e}",
  'boxVr;'                           => "\x{255f}",
  'boxVR;'                           => "\x{2560}",
  'bprime;'                          => "\x{2035}",
  'breve;'                           => "\x{02d8}",
  'Breve;'                           => "\x{02d8}",
  'brvbar'                           => "\x{00a6}",
  'brvbar;'                          => "\x{00a6}",
  'bscr;'                            => "\x{1d4b7}",
  'Bscr;'                            => "\x{212c}",
  'bsemi;'                           => "\x{204f}",
  'bsim;'                            => "\x{223d}",
  'bsime;'                           => "\x{22cd}",
  'bsol;'                            => "\x{005c}",
  'bsolb;'                           => "\x{29c5}",
  'bsolhsub;'                        => "\x{27c8}",
  'bull;'                            => "\x{2022}",
  'bullet;'                          => "\x{2022}",
  'bump;'                            => "\x{224e}",
  'bumpe;'                           => "\x{224f}",
  'bumpE;'                           => "\x{2aae}",
  'bumpeq;'                          => "\x{224f}",
  'Bumpeq;'                          => "\x{224e}",
  'cacute;'                          => "\x{0107}",
  'Cacute;'                          => "\x{0106}",
  'cap;'                             => "\x{2229}",
  'Cap;'                             => "\x{22d2}",
  'capand;'                          => "\x{2a44}",
  'capbrcup;'                        => "\x{2a49}",
  'capcap;'                          => "\x{2a4b}",
  'capcup;'                          => "\x{2a47}",
  'capdot;'                          => "\x{2a40}",
  'CapitalDifferentialD;'            => "\x{2145}",
  'caps;'                            => "\x{2145}",
  'caret;'                           => "\x{2041}",
  'caron;'                           => "\x{02c7}",
  'Cayleys;'                         => "\x{212d}",
  'ccaps;'                           => "\x{2a4d}",
  'ccaron;'                          => "\x{010d}",
  'Ccaron;'                          => "\x{010c}",
  'ccedil'                           => "\x{00e7}",
  'ccedil;'                          => "\x{00e7}",
  'Ccedil'                           => "\x{00c7}",
  'Ccedil;'                          => "\x{00c7}",
  'ccirc;'                           => "\x{0109}",
  'Ccirc;'                           => "\x{0108}",
  'Cconint;'                         => "\x{2230}",
  'ccups;'                           => "\x{2a4c}",
  'ccupssm;'                         => "\x{2a50}",
  'cdot;'                            => "\x{010b}",
  'Cdot;'                            => "\x{010a}",
  'cedil'                            => "\x{00b8}",
  'cedil;'                           => "\x{00b8}",
  'Cedilla;'                         => "\x{00b8}",
  'cemptyv;'                         => "\x{29b2}",
  'cent'                             => "\x{00a2}",
  'cent;'                            => "\x{00a2}",
  'centerdot;'                       => "\x{00b7}",
  'CenterDot;'                       => "\x{00b7}",
  'cfr;'                             => "\x{1d520}",
  'Cfr;'                             => "\x{212d}",
  'chcy;'                            => "\x{0447}",
  'CHcy;'                            => "\x{0427}",
  'check;'                           => "\x{2713}",
  'checkmark;'                       => "\x{2713}",
  'chi;'                             => "\x{03c7}",
  'Chi;'                             => "\x{03a7}",
  'cir;'                             => "\x{25cb}",
  'circ;'                            => "\x{02c6}",
  'circeq;'                          => "\x{2257}",
  'circlearrowleft;'                 => "\x{21ba}",
  'circlearrowright;'                => "\x{21bb}",
  'circledast;'                      => "\x{229b}",
  'circledcirc;'                     => "\x{229a}",
  'circleddash;'                     => "\x{229d}",
  'CircleDot;'                       => "\x{2299}",
  'circledR;'                        => "\x{00ae}",
  'circledS;'                        => "\x{24c8}",
  'CircleMinus;'                     => "\x{2296}",
  'CirclePlus;'                      => "\x{2295}",
  'CircleTimes;'                     => "\x{2297}",
  'cire;'                            => "\x{2257}",
  'cirE;'                            => "\x{29c3}",
  'cirfnint;'                        => "\x{2a10}",
  'cirmid;'                          => "\x{2aef}",
  'cirscir;'                         => "\x{29c2}",
  'ClockwiseContourIntegral;'        => "\x{2232}",
  'CloseCurlyDoubleQuote;'           => "\x{201d}",
  'CloseCurlyQuote;'                 => "\x{2019}",
  'clubs;'                           => "\x{2663}",
  'clubsuit;'                        => "\x{2663}",
  'colon;'                           => "\x{003a}",
  'Colon;'                           => "\x{2237}",
  'colone;'                          => "\x{2254}",
  'Colone;'                          => "\x{2a74}",
  'coloneq;'                         => "\x{2254}",
  'comma;'                           => "\x{002c}",
  'commat;'                          => "\x{0040}",
  'comp;'                            => "\x{2201}",
  'compfn;'                          => "\x{2218}",
  'complement;'                      => "\x{2201}",
  'complexes;'                       => "\x{2102}",
  'cong;'                            => "\x{2245}",
  'congdot;'                         => "\x{2a6d}",
  'Congruent;'                       => "\x{2261}",
  'conint;'                          => "\x{222e}",
  'Conint;'                          => "\x{222f}",
  'ContourIntegral;'                 => "\x{222e}",
  'copf;'                            => "\x{1d554}",
  'Copf;'                            => "\x{2102}",
  'coprod;'                          => "\x{2210}",
  'Coproduct;'                       => "\x{2210}",
  'copy'                             => "\x{00a9}",
  'copy;'                            => "\x{00a9}",
  'COPY'                             => "\x{00a9}",
  'COPY;'                            => "\x{00a9}",
  'copysr;'                          => "\x{2117}",
  'CounterClockwiseContourIntegral;' => "\x{2233}",
  'crarr;'                           => "\x{21b5}",
  'cross;'                           => "\x{2717}",
  'Cross;'                           => "\x{2a2f}",
  'cscr;'                            => "\x{1d4b8}",
  'Cscr;'                            => "\x{1d49e}",
  'csub;'                            => "\x{2acf}",
  'csube;'                           => "\x{2ad1}",
  'csup;'                            => "\x{2ad0}",
  'csupe;'                           => "\x{2ad2}",
  'ctdot;'                           => "\x{22ef}",
  'cudarrl;'                         => "\x{2938}",
  'cudarrr;'                         => "\x{2935}",
  'cuepr;'                           => "\x{22de}",
  'cuesc;'                           => "\x{22df}",
  'cularr;'                          => "\x{21b6}",
  'cularrp;'                         => "\x{293d}",
  'cup;'                             => "\x{222a}",
  'Cup;'                             => "\x{22d3}",
  'cupbrcap;'                        => "\x{2a48}",
  'cupcap;'                          => "\x{2a46}",
  'CupCap;'                          => "\x{224d}",
  'cupcup;'                          => "\x{2a4a}",
  'cupdot;'                          => "\x{228d}",
  'cupor;'                           => "\x{2a45}",
  'cups;'                            => "\x{2a45}",
  'curarr;'                          => "\x{21b7}",
  'curarrm;'                         => "\x{293c}",
  'curlyeqprec;'                     => "\x{22de}",
  'curlyeqsucc;'                     => "\x{22df}",
  'curlyvee;'                        => "\x{22ce}",
  'curlywedge;'                      => "\x{22cf}",
  'curren'                           => "\x{00a4}",
  'curren;'                          => "\x{00a4}",
  'curvearrowleft;'                  => "\x{21b6}",
  'curvearrowright;'                 => "\x{21b7}",
  'cuvee;'                           => "\x{22ce}",
  'cuwed;'                           => "\x{22cf}",
  'cwconint;'                        => "\x{2232}",
  'cwint;'                           => "\x{2231}",
  'cylcty;'                          => "\x{232d}",
  'dagger;'                          => "\x{2020}",
  'Dagger;'                          => "\x{2021}",
  'daleth;'                          => "\x{2138}",
  'darr;'                            => "\x{2193}",
  'dArr;'                            => "\x{21d3}",
  'Darr;'                            => "\x{21a1}",
  'dash;'                            => "\x{2010}",
  'dashv;'                           => "\x{22a3}",
  'Dashv;'                           => "\x{2ae4}",
  'dbkarow;'                         => "\x{290f}",
  'dblac;'                           => "\x{02dd}",
  'dcaron;'                          => "\x{010f}",
  'Dcaron;'                          => "\x{010e}",
  'dcy;'                             => "\x{0434}",
  'Dcy;'                             => "\x{0414}",
  'dd;'                              => "\x{2146}",
  'DD;'                              => "\x{2145}",
  'ddagger;'                         => "\x{2021}",
  'ddarr;'                           => "\x{21ca}",
  'DDotrahd;'                        => "\x{2911}",
  'ddotseq;'                         => "\x{2a77}",
  'deg'                              => "\x{00b0}",
  'deg;'                             => "\x{00b0}",
  'Del;'                             => "\x{2207}",
  'delta;'                           => "\x{03b4}",
  'Delta;'                           => "\x{0394}",
  'demptyv;'                         => "\x{29b1}",
  'dfisht;'                          => "\x{297f}",
  'dfr;'                             => "\x{1d521}",
  'Dfr;'                             => "\x{1d507}",
  'dgr;'                             => "\x{03b4}",
  'Dgr;'                             => "\x{0394}",
  'dHar;'                            => "\x{2965}",
  'dharl;'                           => "\x{21c3}",
  'dharr;'                           => "\x{21c2}",
  'DiacriticalAcute;'                => "\x{00b4}",
  'DiacriticalDot;'                  => "\x{02d9}",
  'DiacriticalDoubleAcute;'          => "\x{02dd}",
  'DiacriticalGrave;'                => "\x{0060}",
  'DiacriticalTilde;'                => "\x{02dc}",
  'diam;'                            => "\x{22c4}",
  'diamond;'                         => "\x{22c4}",
  'Diamond;'                         => "\x{22c4}",
  'diamondsuit;'                     => "\x{2666}",
  'diams;'                           => "\x{2666}",
  'die;'                             => "\x{00a8}",
  'DifferentialD;'                   => "\x{2146}",
  'digamma;'                         => "\x{03dd}",
  'disin;'                           => "\x{22f2}",
  'div;'                             => "\x{00f7}",
  'divide'                           => "\x{00f7}",
  'divide;'                          => "\x{00f7}",
  'divideontimes;'                   => "\x{22c7}",
  'divonx;'                          => "\x{22c7}",
  'djcy;'                            => "\x{0452}",
  'DJcy;'                            => "\x{0402}",
  'dlcorn;'                          => "\x{231e}",
  'dlcrop;'                          => "\x{230d}",
  'dollar;'                          => "\x{0024}",
  'dopf;'                            => "\x{1d555}",
  'Dopf;'                            => "\x{1d53b}",
  'dot;'                             => "\x{02d9}",
  'Dot;'                             => "\x{00a8}",
  'DotDot;'                          => "\x{20dc}",
  'doteq;'                           => "\x{2250}",
  'doteqdot;'                        => "\x{2251}",
  'DotEqual;'                        => "\x{2250}",
  'dotminus;'                        => "\x{2238}",
  'dotplus;'                         => "\x{2214}",
  'dotsquare;'                       => "\x{22a1}",
  'doublebarwedge;'                  => "\x{2306}",
  'DoubleContourIntegral;'           => "\x{222f}",
  'DoubleDot;'                       => "\x{00a8}",
  'DoubleDownArrow;'                 => "\x{21d3}",
  'DoubleLeftArrow;'                 => "\x{21d0}",
  'DoubleLeftRightArrow;'            => "\x{21d4}",
  'DoubleLeftTee;'                   => "\x{2ae4}",
  'DoubleLongLeftArrow;'             => "\x{27f8}",
  'DoubleLongLeftRightArrow;'        => "\x{27fa}",
  'DoubleLongRightArrow;'            => "\x{27f9}",
  'DoubleRightArrow;'                => "\x{21d2}",
  'DoubleRightTee;'                  => "\x{22a8}",
  'DoubleUpArrow;'                   => "\x{21d1}",
  'DoubleUpDownArrow;'               => "\x{21d5}",
  'DoubleVerticalBar;'               => "\x{2225}",
  'downarrow;'                       => "\x{2193}",
  'Downarrow;'                       => "\x{21d3}",
  'DownArrow;'                       => "\x{2193}",
  'DownArrowBar;'                    => "\x{2913}",
  'DownArrowUpArrow;'                => "\x{21f5}",
  'DownBreve;'                       => "\x{0311}",
  'downdownarrows;'                  => "\x{21ca}",
  'downharpoonleft;'                 => "\x{21c3}",
  'downharpoonright;'                => "\x{21c2}",
  'DownLeftRightVector;'             => "\x{2950}",
  'DownLeftTeeVector;'               => "\x{295e}",
  'DownLeftVector;'                  => "\x{21bd}",
  'DownLeftVectorBar;'               => "\x{2956}",
  'DownRightTeeVector;'              => "\x{295f}",
  'DownRightVector;'                 => "\x{21c1}",
  'DownRightVectorBar;'              => "\x{2957}",
  'DownTee;'                         => "\x{22a4}",
  'DownTeeArrow;'                    => "\x{21a7}",
  'drbkarow;'                        => "\x{2910}",
  'drcorn;'                          => "\x{231f}",
  'drcrop;'                          => "\x{230c}",
  'dscr;'                            => "\x{1d4b9}",
  'Dscr;'                            => "\x{1d49f}",
  'dscy;'                            => "\x{0455}",
  'DScy;'                            => "\x{0405}",
  'dsol;'                            => "\x{29f6}",
  'dstrok;'                          => "\x{0111}",
  'Dstrok;'                          => "\x{0110}",
  'dtdot;'                           => "\x{22f1}",
  'dtri;'                            => "\x{25bf}",
  'dtrif;'                           => "\x{25be}",
  'duarr;'                           => "\x{21f5}",
  'duhar;'                           => "\x{296f}",
  'dwangle;'                         => "\x{29a6}",
  'dzcy;'                            => "\x{045f}",
  'DZcy;'                            => "\x{040f}",
  'dzigrarr;'                        => "\x{27ff}",
  'eacgr;'                           => "\x{03ad}",
  'Eacgr;'                           => "\x{0388}",
  'eacute'                           => "\x{00e9}",
  'eacute;'                          => "\x{00e9}",
  'Eacute'                           => "\x{00c9}",
  'Eacute;'                          => "\x{00c9}",
  'easter;'                          => "\x{2a6e}",
  'ecaron;'                          => "\x{011b}",
  'Ecaron;'                          => "\x{011a}",
  'ecir;'                            => "\x{2256}",
  'ecirc'                            => "\x{00ea}",
  'ecirc;'                           => "\x{00ea}",
  'Ecirc'                            => "\x{00ca}",
  'Ecirc;'                           => "\x{00ca}",
  'ecolon;'                          => "\x{2255}",
  'ecy;'                             => "\x{044d}",
  'Ecy;'                             => "\x{042d}",
  'eDDot;'                           => "\x{2a77}",
  'edot;'                            => "\x{0117}",
  'eDot;'                            => "\x{2251}",
  'Edot;'                            => "\x{0116}",
  'ee;'                              => "\x{2147}",
  'eeacgr;'                          => "\x{03ae}",
  'EEacgr;'                          => "\x{0389}",
  'eegr;'                            => "\x{03b7}",
  'EEgr;'                            => "\x{0397}",
  'efDot;'                           => "\x{2252}",
  'efr;'                             => "\x{1d522}",
  'Efr;'                             => "\x{1d508}",
  'eg;'                              => "\x{2a9a}",
  'egr;'                             => "\x{03b5}",
  'Egr;'                             => "\x{0395}",
  'egrave'                           => "\x{00e8}",
  'egrave;'                          => "\x{00e8}",
  'Egrave'                           => "\x{00c8}",
  'Egrave;'                          => "\x{00c8}",
  'egs;'                             => "\x{2a96}",
  'egsdot;'                          => "\x{2a98}",
  'el;'                              => "\x{2a99}",
  'Element;'                         => "\x{2208}",
  'elinters;'                        => "\x{23e7}",
  'ell;'                             => "\x{2113}",
  'els;'                             => "\x{2a95}",
  'elsdot;'                          => "\x{2a97}",
  'emacr;'                           => "\x{0113}",
  'Emacr;'                           => "\x{0112}",
  'empty;'                           => "\x{2205}",
  'emptyset;'                        => "\x{2205}",
  'EmptySmallSquare;'                => "\x{25fb}",
  'emptyv;'                          => "\x{2205}",
  'EmptyVerySmallSquare;'            => "\x{25ab}",
  'emsp;'                            => "\x{2003}",
  'emsp13;'                          => "\x{2004}",
  'emsp14;'                          => "\x{2005}",
  'eng;'                             => "\x{014b}",
  'ENG;'                             => "\x{014a}",
  'ensp;'                            => "\x{2002}",
  'eogon;'                           => "\x{0119}",
  'Eogon;'                           => "\x{0118}",
  'eopf;'                            => "\x{1d556}",
  'Eopf;'                            => "\x{1d53c}",
  'epar;'                            => "\x{22d5}",
  'eparsl;'                          => "\x{29e3}",
  'eplus;'                           => "\x{2a71}",
  'epsi;'                            => "\x{03b5}",
  'epsilon;'                         => "\x{03b5}",
  'Epsilon;'                         => "\x{0395}",
  'epsiv;'                           => "\x{03f5}",
  'eqcirc;'                          => "\x{2256}",
  'eqcolon;'                         => "\x{2255}",
  'eqsim;'                           => "\x{2242}",
  'eqslantgtr;'                      => "\x{2a96}",
  'eqslantless;'                     => "\x{2a95}",
  'Equal;'                           => "\x{2a75}",
  'equals;'                          => "\x{003d}",
  'EqualTilde;'                      => "\x{2242}",
  'equest;'                          => "\x{225f}",
  'Equilibrium;'                     => "\x{21cc}",
  'equiv;'                           => "\x{2261}",
  'equivDD;'                         => "\x{2a78}",
  'eqvparsl;'                        => "\x{29e5}",
  'erarr;'                           => "\x{2971}",
  'erDot;'                           => "\x{2253}",
  'escr;'                            => "\x{212f}",
  'Escr;'                            => "\x{2130}",
  'esdot;'                           => "\x{2250}",
  'esim;'                            => "\x{2242}",
  'Esim;'                            => "\x{2a73}",
  'eta;'                             => "\x{03b7}",
  'Eta;'                             => "\x{0397}",
  'eth'                              => "\x{00f0}",
  'eth;'                             => "\x{00f0}",
  'ETH'                              => "\x{00d0}",
  'ETH;'                             => "\x{00d0}",
  'euml'                             => "\x{00eb}",
  'euml;'                            => "\x{00eb}",
  'Euml'                             => "\x{00cb}",
  'Euml;'                            => "\x{00cb}",
  'euro;'                            => "\x{20ac}",
  'excl;'                            => "\x{0021}",
  'exist;'                           => "\x{2203}",
  'Exists;'                          => "\x{2203}",
  'expectation;'                     => "\x{2130}",
  'exponentiale;'                    => "\x{2147}",
  'ExponentialE;'                    => "\x{2147}",
  'fallingdotseq;'                   => "\x{2252}",
  'fcy;'                             => "\x{0444}",
  'Fcy;'                             => "\x{0424}",
  'female;'                          => "\x{2640}",
  'ffilig;'                          => "\x{fb03}",
  'fflig;'                           => "\x{fb00}",
  'ffllig;'                          => "\x{fb04}",
  'ffr;'                             => "\x{1d523}",
  'Ffr;'                             => "\x{1d509}",
  'filig;'                           => "\x{fb01}",
  'FilledSmallSquare;'               => "\x{25fc}",
  'FilledVerySmallSquare;'           => "\x{25aa}",
  'fjlig;'                           => "\x{25aa}",
  'flat;'                            => "\x{266d}",
  'fllig;'                           => "\x{fb02}",
  'fltns;'                           => "\x{25b1}",
  'fnof;'                            => "\x{0192}",
  'fopf;'                            => "\x{1d557}",
  'Fopf;'                            => "\x{1d53d}",
  'forall;'                          => "\x{2200}",
  'ForAll;'                          => "\x{2200}",
  'fork;'                            => "\x{22d4}",
  'forkv;'                           => "\x{2ad9}",
  'Fouriertrf;'                      => "\x{2131}",
  'fpartint;'                        => "\x{2a0d}",
  'frac12'                           => "\x{00bd}",
  'frac12;'                          => "\x{00bd}",
  'frac13;'                          => "\x{2153}",
  'frac14'                           => "\x{00bc}",
  'frac14;'                          => "\x{00bc}",
  'frac15;'                          => "\x{2155}",
  'frac16;'                          => "\x{2159}",
  'frac18;'                          => "\x{215b}",
  'frac23;'                          => "\x{2154}",
  'frac25;'                          => "\x{2156}",
  'frac34'                           => "\x{00be}",
  'frac34;'                          => "\x{00be}",
  'frac35;'                          => "\x{2157}",
  'frac38;'                          => "\x{215c}",
  'frac45;'                          => "\x{2158}",
  'frac56;'                          => "\x{215a}",
  'frac58;'                          => "\x{215d}",
  'frac78;'                          => "\x{215e}",
  'frasl;'                           => "\x{2044}",
  'frown;'                           => "\x{2322}",
  'fscr;'                            => "\x{1d4bb}",
  'Fscr;'                            => "\x{2131}",
  'gacute;'                          => "\x{01f5}",
  'gamma;'                           => "\x{03b3}",
  'Gamma;'                           => "\x{0393}",
  'gammad;'                          => "\x{03dd}",
  'Gammad;'                          => "\x{03dc}",
  'gap;'                             => "\x{2a86}",
  'gbreve;'                          => "\x{011f}",
  'Gbreve;'                          => "\x{011e}",
  'Gcedil;'                          => "\x{0122}",
  'gcirc;'                           => "\x{011d}",
  'Gcirc;'                           => "\x{011c}",
  'gcy;'                             => "\x{0433}",
  'Gcy;'                             => "\x{0413}",
  'gdot;'                            => "\x{0121}",
  'Gdot;'                            => "\x{0120}",
  'ge;'                              => "\x{2265}",
  'gE;'                              => "\x{2267}",
  'gel;'                             => "\x{22db}",
  'gEl;'                             => "\x{2a8c}",
  'geq;'                             => "\x{2265}",
  'geqq;'                            => "\x{2267}",
  'geqslant;'                        => "\x{2a7e}",
  'ges;'                             => "\x{2a7e}",
  'gescc;'                           => "\x{2aa9}",
  'gesdot;'                          => "\x{2a80}",
  'gesdoto;'                         => "\x{2a82}",
  'gesdotol;'                        => "\x{2a84}",
  'gesl;'                            => "\x{2a84}",
  'gesles;'                          => "\x{2a94}",
  'gfr;'                             => "\x{1d524}",
  'Gfr;'                             => "\x{1d50a}",
  'gg;'                              => "\x{226b}",
  'Gg;'                              => "\x{22d9}",
  'ggg;'                             => "\x{22d9}",
  'ggr;'                             => "\x{03b3}",
  'Ggr;'                             => "\x{0393}",
  'gimel;'                           => "\x{2137}",
  'gjcy;'                            => "\x{0453}",
  'GJcy;'                            => "\x{0403}",
  'gl;'                              => "\x{2277}",
  'gla;'                             => "\x{2aa5}",
  'glE;'                             => "\x{2a92}",
  'glj;'                             => "\x{2aa4}",
  'gnap;'                            => "\x{2a8a}",
  'gnapprox;'                        => "\x{2a8a}",
  'gne;'                             => "\x{2a88}",
  'gnE;'                             => "\x{2269}",
  'gneq;'                            => "\x{2a88}",
  'gneqq;'                           => "\x{2269}",
  'gnsim;'                           => "\x{22e7}",
  'gopf;'                            => "\x{1d558}",
  'Gopf;'                            => "\x{1d53e}",
  'grave;'                           => "\x{0060}",
  'GreaterEqual;'                    => "\x{2265}",
  'GreaterEqualLess;'                => "\x{22db}",
  'GreaterFullEqual;'                => "\x{2267}",
  'GreaterGreater;'                  => "\x{2aa2}",
  'GreaterLess;'                     => "\x{2277}",
  'GreaterSlantEqual;'               => "\x{2a7e}",
  'GreaterTilde;'                    => "\x{2273}",
  'gscr;'                            => "\x{210a}",
  'Gscr;'                            => "\x{1d4a2}",
  'gsim;'                            => "\x{2273}",
  'gsime;'                           => "\x{2a8e}",
  'gsiml;'                           => "\x{2a90}",
  'gt'                               => "\x{003e}",
  'gt;'                              => "\x{003e}",
  'Gt;'                              => "\x{226b}",
  'GT'                               => "\x{003e}",
  'GT;'                              => "\x{003e}",
  'gtcc;'                            => "\x{2aa7}",
  'gtcir;'                           => "\x{2a7a}",
  'gtdot;'                           => "\x{22d7}",
  'gtlPar;'                          => "\x{2995}",
  'gtquest;'                         => "\x{2a7c}",
  'gtrapprox;'                       => "\x{2a86}",
  'gtrarr;'                          => "\x{2978}",
  'gtrdot;'                          => "\x{22d7}",
  'gtreqless;'                       => "\x{22db}",
  'gtreqqless;'                      => "\x{2a8c}",
  'gtrless;'                         => "\x{2277}",
  'gtrsim;'                          => "\x{2273}",
  'gvertneqq;'                       => "\x{2273}",
  'gvnE;'                            => "\x{2273}",
  'Hacek;'                           => "\x{02c7}",
  'hairsp;'                          => "\x{200a}",
  'half;'                            => "\x{00bd}",
  'hamilt;'                          => "\x{210b}",
  'hardcy;'                          => "\x{044a}",
  'HARDcy;'                          => "\x{042a}",
  'harr;'                            => "\x{2194}",
  'hArr;'                            => "\x{21d4}",
  'harrcir;'                         => "\x{2948}",
  'harrw;'                           => "\x{21ad}",
  'Hat;'                             => "\x{005e}",
  'hbar;'                            => "\x{210f}",
  'hcirc;'                           => "\x{0125}",
  'Hcirc;'                           => "\x{0124}",
  'hearts;'                          => "\x{2665}",
  'heartsuit;'                       => "\x{2665}",
  'hellip;'                          => "\x{2026}",
  'hercon;'                          => "\x{22b9}",
  'hfr;'                             => "\x{1d525}",
  'Hfr;'                             => "\x{210c}",
  'HilbertSpace;'                    => "\x{210b}",
  'hksearow;'                        => "\x{2925}",
  'hkswarow;'                        => "\x{2926}",
  'hoarr;'                           => "\x{21ff}",
  'homtht;'                          => "\x{223b}",
  'hookleftarrow;'                   => "\x{21a9}",
  'hookrightarrow;'                  => "\x{21aa}",
  'hopf;'                            => "\x{1d559}",
  'Hopf;'                            => "\x{210d}",
  'horbar;'                          => "\x{2015}",
  'HorizontalLine;'                  => "\x{2500}",
  'hscr;'                            => "\x{1d4bd}",
  'Hscr;'                            => "\x{210b}",
  'hslash;'                          => "\x{210f}",
  'hstrok;'                          => "\x{0127}",
  'Hstrok;'                          => "\x{0126}",
  'HumpDownHump;'                    => "\x{224e}",
  'HumpEqual;'                       => "\x{224f}",
  'hybull;'                          => "\x{2043}",
  'hyphen;'                          => "\x{2010}",
  'iacgr;'                           => "\x{03af}",
  'Iacgr;'                           => "\x{038a}",
  'iacute'                           => "\x{00ed}",
  'iacute;'                          => "\x{00ed}",
  'Iacute'                           => "\x{00cd}",
  'Iacute;'                          => "\x{00cd}",
  'ic;'                              => "\x{2063}",
  'icirc'                            => "\x{00ee}",
  'icirc;'                           => "\x{00ee}",
  'Icirc'                            => "\x{00ce}",
  'Icirc;'                           => "\x{00ce}",
  'icy;'                             => "\x{0438}",
  'Icy;'                             => "\x{0418}",
  'idiagr;'                          => "\x{0390}",
  'idigr;'                           => "\x{03ca}",
  'Idigr;'                           => "\x{03aa}",
  'Idot;'                            => "\x{0130}",
  'iecy;'                            => "\x{0435}",
  'IEcy;'                            => "\x{0415}",
  'iexcl'                            => "\x{00a1}",
  'iexcl;'                           => "\x{00a1}",
  'iff;'                             => "\x{21d4}",
  'ifr;'                             => "\x{1d526}",
  'Ifr;'                             => "\x{2111}",
  'igr;'                             => "\x{03b9}",
  'Igr;'                             => "\x{0399}",
  'igrave'                           => "\x{00ec}",
  'igrave;'                          => "\x{00ec}",
  'Igrave'                           => "\x{00cc}",
  'Igrave;'                          => "\x{00cc}",
  'ii;'                              => "\x{2148}",
  'iiiint;'                          => "\x{2a0c}",
  'iiint;'                           => "\x{222d}",
  'iinfin;'                          => "\x{29dc}",
  'iiota;'                           => "\x{2129}",
  'ijlig;'                           => "\x{0133}",
  'IJlig;'                           => "\x{0132}",
  'Im;'                              => "\x{2111}",
  'imacr;'                           => "\x{012b}",
  'Imacr;'                           => "\x{012a}",
  'image;'                           => "\x{2111}",
  'ImaginaryI;'                      => "\x{2148}",
  'imagline;'                        => "\x{2110}",
  'imagpart;'                        => "\x{2111}",
  'imath;'                           => "\x{0131}",
  'imof;'                            => "\x{22b7}",
  'imped;'                           => "\x{01b5}",
  'Implies;'                         => "\x{21d2}",
  'in;'                              => "\x{2208}",
  'incare;'                          => "\x{2105}",
  'infin;'                           => "\x{221e}",
  'infintie;'                        => "\x{29dd}",
  'inodot;'                          => "\x{0131}",
  'int;'                             => "\x{222b}",
  'Int;'                             => "\x{222c}",
  'intcal;'                          => "\x{22ba}",
  'integers;'                        => "\x{2124}",
  'Integral;'                        => "\x{222b}",
  'intercal;'                        => "\x{22ba}",
  'Intersection;'                    => "\x{22c2}",
  'intlarhk;'                        => "\x{2a17}",
  'intprod;'                         => "\x{2a3c}",
  'InvisibleComma;'                  => "\x{2063}",
  'InvisibleTimes;'                  => "\x{2062}",
  'iocy;'                            => "\x{0451}",
  'IOcy;'                            => "\x{0401}",
  'iogon;'                           => "\x{012f}",
  'Iogon;'                           => "\x{012e}",
  'iopf;'                            => "\x{1d55a}",
  'Iopf;'                            => "\x{1d540}",
  'iota;'                            => "\x{03b9}",
  'Iota;'                            => "\x{0399}",
  'iprod;'                           => "\x{2a3c}",
  'iquest'                           => "\x{00bf}",
  'iquest;'                          => "\x{00bf}",
  'iscr;'                            => "\x{1d4be}",
  'Iscr;'                            => "\x{2110}",
  'isin;'                            => "\x{2208}",
  'isindot;'                         => "\x{22f5}",
  'isinE;'                           => "\x{22f9}",
  'isins;'                           => "\x{22f4}",
  'isinsv;'                          => "\x{22f3}",
  'isinv;'                           => "\x{2208}",
  'it;'                              => "\x{2062}",
  'itilde;'                          => "\x{0129}",
  'Itilde;'                          => "\x{0128}",
  'iukcy;'                           => "\x{0456}",
  'Iukcy;'                           => "\x{0406}",
  'iuml'                             => "\x{00ef}",
  'iuml;'                            => "\x{00ef}",
  'Iuml'                             => "\x{00cf}",
  'Iuml;'                            => "\x{00cf}",
  'jcirc;'                           => "\x{0135}",
  'Jcirc;'                           => "\x{0134}",
  'jcy;'                             => "\x{0439}",
  'Jcy;'                             => "\x{0419}",
  'jfr;'                             => "\x{1d527}",
  'Jfr;'                             => "\x{1d50d}",
  'jmath;'                           => "\x{0237}",
  'jopf;'                            => "\x{1d55b}",
  'Jopf;'                            => "\x{1d541}",
  'jscr;'                            => "\x{1d4bf}",
  'Jscr;'                            => "\x{1d4a5}",
  'jsercy;'                          => "\x{0458}",
  'Jsercy;'                          => "\x{0408}",
  'jukcy;'                           => "\x{0454}",
  'Jukcy;'                           => "\x{0404}",
  'kappa;'                           => "\x{03ba}",
  'Kappa;'                           => "\x{039a}",
  'kappav;'                          => "\x{03f0}",
  'kcedil;'                          => "\x{0137}",
  'Kcedil;'                          => "\x{0136}",
  'kcy;'                             => "\x{043a}",
  'Kcy;'                             => "\x{041a}",
  'kfr;'                             => "\x{1d528}",
  'Kfr;'                             => "\x{1d50e}",
  'kgr;'                             => "\x{03ba}",
  'Kgr;'                             => "\x{039a}",
  'kgreen;'                          => "\x{0138}",
  'khcy;'                            => "\x{0445}",
  'KHcy;'                            => "\x{0425}",
  'khgr;'                            => "\x{03c7}",
  'KHgr;'                            => "\x{03a7}",
  'kjcy;'                            => "\x{045c}",
  'KJcy;'                            => "\x{040c}",
  'kopf;'                            => "\x{1d55c}",
  'Kopf;'                            => "\x{1d542}",
  'kscr;'                            => "\x{1d4c0}",
  'Kscr;'                            => "\x{1d4a6}",
  'lAarr;'                           => "\x{21da}",
  'lacute;'                          => "\x{013a}",
  'Lacute;'                          => "\x{0139}",
  'laemptyv;'                        => "\x{29b4}",
  'lagran;'                          => "\x{2112}",
  'lambda;'                          => "\x{03bb}",
  'Lambda;'                          => "\x{039b}",
  'lang;'                            => "\x{27e8}",
  'Lang;'                            => "\x{27ea}",
  'langd;'                           => "\x{2991}",
  'langle;'                          => "\x{27e8}",
  'lap;'                             => "\x{2a85}",
  'Laplacetrf;'                      => "\x{2112}",
  'laquo'                            => "\x{00ab}",
  'laquo;'                           => "\x{00ab}",
  'larr;'                            => "\x{2190}",
  'lArr;'                            => "\x{21d0}",
  'Larr;'                            => "\x{219e}",
  'larrb;'                           => "\x{21e4}",
  'larrbfs;'                         => "\x{291f}",
  'larrfs;'                          => "\x{291d}",
  'larrhk;'                          => "\x{21a9}",
  'larrlp;'                          => "\x{21ab}",
  'larrpl;'                          => "\x{2939}",
  'larrsim;'                         => "\x{2973}",
  'larrtl;'                          => "\x{21a2}",
  'lat;'                             => "\x{2aab}",
  'latail;'                          => "\x{2919}",
  'lAtail;'                          => "\x{291b}",
  'late;'                            => "\x{2aad}",
  'lates;'                           => "\x{2aad}",
  'lbarr;'                           => "\x{290c}",
  'lBarr;'                           => "\x{290e}",
  'lbbrk;'                           => "\x{2772}",
  'lbrace;'                          => "\x{007b}",
  'lbrack;'                          => "\x{005b}",
  'lbrke;'                           => "\x{298b}",
  'lbrksld;'                         => "\x{298f}",
  'lbrkslu;'                         => "\x{298d}",
  'lcaron;'                          => "\x{013e}",
  'Lcaron;'                          => "\x{013d}",
  'lcedil;'                          => "\x{013c}",
  'Lcedil;'                          => "\x{013b}",
  'lceil;'                           => "\x{2308}",
  'lcub;'                            => "\x{007b}",
  'lcy;'                             => "\x{043b}",
  'Lcy;'                             => "\x{041b}",
  'ldca;'                            => "\x{2936}",
  'ldquo;'                           => "\x{201c}",
  'ldquor;'                          => "\x{201e}",
  'ldrdhar;'                         => "\x{2967}",
  'ldrushar;'                        => "\x{294b}",
  'ldsh;'                            => "\x{21b2}",
  'le;'                              => "\x{2264}",
  'lE;'                              => "\x{2266}",
  'LeftAngleBracket;'                => "\x{27e8}",
  'leftarrow;'                       => "\x{2190}",
  'Leftarrow;'                       => "\x{21d0}",
  'LeftArrow;'                       => "\x{2190}",
  'LeftArrowBar;'                    => "\x{21e4}",
  'LeftArrowRightArrow;'             => "\x{21c6}",
  'leftarrowtail;'                   => "\x{21a2}",
  'LeftCeiling;'                     => "\x{2308}",
  'LeftDoubleBracket;'               => "\x{27e6}",
  'LeftDownTeeVector;'               => "\x{2961}",
  'LeftDownVector;'                  => "\x{21c3}",
  'LeftDownVectorBar;'               => "\x{2959}",
  'LeftFloor;'                       => "\x{230a}",
  'leftharpoondown;'                 => "\x{21bd}",
  'leftharpoonup;'                   => "\x{21bc}",
  'leftleftarrows;'                  => "\x{21c7}",
  'leftrightarrow;'                  => "\x{2194}",
  'Leftrightarrow;'                  => "\x{21d4}",
  'LeftRightArrow;'                  => "\x{2194}",
  'leftrightarrows;'                 => "\x{21c6}",
  'leftrightharpoons;'               => "\x{21cb}",
  'leftrightsquigarrow;'             => "\x{21ad}",
  'LeftRightVector;'                 => "\x{294e}",
  'LeftTee;'                         => "\x{22a3}",
  'LeftTeeArrow;'                    => "\x{21a4}",
  'LeftTeeVector;'                   => "\x{295a}",
  'leftthreetimes;'                  => "\x{22cb}",
  'LeftTriangle;'                    => "\x{22b2}",
  'LeftTriangleBar;'                 => "\x{29cf}",
  'LeftTriangleEqual;'               => "\x{22b4}",
  'LeftUpDownVector;'                => "\x{2951}",
  'LeftUpTeeVector;'                 => "\x{2960}",
  'LeftUpVector;'                    => "\x{21bf}",
  'LeftUpVectorBar;'                 => "\x{2958}",
  'LeftVector;'                      => "\x{21bc}",
  'LeftVectorBar;'                   => "\x{2952}",
  'leg;'                             => "\x{22da}",
  'lEg;'                             => "\x{2a8b}",
  'leq;'                             => "\x{2264}",
  'leqq;'                            => "\x{2266}",
  'leqslant;'                        => "\x{2a7d}",
  'les;'                             => "\x{2a7d}",
  'lescc;'                           => "\x{2aa8}",
  'lesdot;'                          => "\x{2a7f}",
  'lesdoto;'                         => "\x{2a81}",
  'lesdotor;'                        => "\x{2a83}",
  'lesg;'                            => "\x{2a83}",
  'lesges;'                          => "\x{2a93}",
  'lessapprox;'                      => "\x{2a85}",
  'lessdot;'                         => "\x{22d6}",
  'lesseqgtr;'                       => "\x{22da}",
  'lesseqqgtr;'                      => "\x{2a8b}",
  'LessEqualGreater;'                => "\x{22da}",
  'LessFullEqual;'                   => "\x{2266}",
  'LessGreater;'                     => "\x{2276}",
  'lessgtr;'                         => "\x{2276}",
  'LessLess;'                        => "\x{2aa1}",
  'lesssim;'                         => "\x{2272}",
  'LessSlantEqual;'                  => "\x{2a7d}",
  'LessTilde;'                       => "\x{2272}",
  'lfisht;'                          => "\x{297c}",
  'lfloor;'                          => "\x{230a}",
  'lfr;'                             => "\x{1d529}",
  'Lfr;'                             => "\x{1d50f}",
  'lg;'                              => "\x{2276}",
  'lgE;'                             => "\x{2a91}",
  'lgr;'                             => "\x{03bb}",
  'Lgr;'                             => "\x{039b}",
  'lHar;'                            => "\x{2962}",
  'lhard;'                           => "\x{21bd}",
  'lharu;'                           => "\x{21bc}",
  'lharul;'                          => "\x{296a}",
  'lhblk;'                           => "\x{2584}",
  'ljcy;'                            => "\x{0459}",
  'LJcy;'                            => "\x{0409}",
  'll;'                              => "\x{226a}",
  'Ll;'                              => "\x{22d8}",
  'llarr;'                           => "\x{21c7}",
  'llcorner;'                        => "\x{231e}",
  'Lleftarrow;'                      => "\x{21da}",
  'llhard;'                          => "\x{296b}",
  'lltri;'                           => "\x{25fa}",
  'lmidot;'                          => "\x{0140}",
  'Lmidot;'                          => "\x{013f}",
  'lmoust;'                          => "\x{23b0}",
  'lmoustache;'                      => "\x{23b0}",
  'lnap;'                            => "\x{2a89}",
  'lnapprox;'                        => "\x{2a89}",
  'lne;'                             => "\x{2a87}",
  'lnE;'                             => "\x{2268}",
  'lneq;'                            => "\x{2a87}",
  'lneqq;'                           => "\x{2268}",
  'lnsim;'                           => "\x{22e6}",
  'loang;'                           => "\x{27ec}",
  'loarr;'                           => "\x{21fd}",
  'lobrk;'                           => "\x{27e6}",
  'longleftarrow;'                   => "\x{27f5}",
  'Longleftarrow;'                   => "\x{27f8}",
  'LongLeftArrow;'                   => "\x{27f5}",
  'longleftrightarrow;'              => "\x{27f7}",
  'Longleftrightarrow;'              => "\x{27fa}",
  'LongLeftRightArrow;'              => "\x{27f7}",
  'longmapsto;'                      => "\x{27fc}",
  'longrightarrow;'                  => "\x{27f6}",
  'Longrightarrow;'                  => "\x{27f9}",
  'LongRightArrow;'                  => "\x{27f6}",
  'looparrowleft;'                   => "\x{21ab}",
  'looparrowright;'                  => "\x{21ac}",
  'lopar;'                           => "\x{2985}",
  'lopf;'                            => "\x{1d55d}",
  'Lopf;'                            => "\x{1d543}",
  'loplus;'                          => "\x{2a2d}",
  'lotimes;'                         => "\x{2a34}",
  'lowast;'                          => "\x{2217}",
  'lowbar;'                          => "\x{005f}",
  'LowerLeftArrow;'                  => "\x{2199}",
  'LowerRightArrow;'                 => "\x{2198}",
  'loz;'                             => "\x{25ca}",
  'lozenge;'                         => "\x{25ca}",
  'lozf;'                            => "\x{29eb}",
  'lpar;'                            => "\x{0028}",
  'lparlt;'                          => "\x{2993}",
  'lrarr;'                           => "\x{21c6}",
  'lrcorner;'                        => "\x{231f}",
  'lrhar;'                           => "\x{21cb}",
  'lrhard;'                          => "\x{296d}",
  'lrm;'                             => "\x{200e}",
  'lrtri;'                           => "\x{22bf}",
  'lsaquo;'                          => "\x{2039}",
  'lscr;'                            => "\x{1d4c1}",
  'Lscr;'                            => "\x{2112}",
  'lsh;'                             => "\x{21b0}",
  'Lsh;'                             => "\x{21b0}",
  'lsim;'                            => "\x{2272}",
  'lsime;'                           => "\x{2a8d}",
  'lsimg;'                           => "\x{2a8f}",
  'lsqb;'                            => "\x{005b}",
  'lsquo;'                           => "\x{2018}",
  'lsquor;'                          => "\x{201a}",
  'lstrok;'                          => "\x{0142}",
  'Lstrok;'                          => "\x{0141}",
  'lt'                               => "\x{003c}",
  'lt;'                              => "\x{003c}",
  'Lt;'                              => "\x{226a}",
  'LT'                               => "\x{003c}",
  'LT;'                              => "\x{003c}",
  'ltcc;'                            => "\x{2aa6}",
  'ltcir;'                           => "\x{2a79}",
  'ltdot;'                           => "\x{22d6}",
  'lthree;'                          => "\x{22cb}",
  'ltimes;'                          => "\x{22c9}",
  'ltlarr;'                          => "\x{2976}",
  'ltquest;'                         => "\x{2a7b}",
  'ltri;'                            => "\x{25c3}",
  'ltrie;'                           => "\x{22b4}",
  'ltrif;'                           => "\x{25c2}",
  'ltrPar;'                          => "\x{2996}",
  'lurdshar;'                        => "\x{294a}",
  'luruhar;'                         => "\x{2966}",
  'lvertneqq;'                       => "\x{2966}",
  'lvnE;'                            => "\x{2966}",
  'macr'                             => "\x{00af}",
  'macr;'                            => "\x{00af}",
  'male;'                            => "\x{2642}",
  'malt;'                            => "\x{2720}",
  'maltese;'                         => "\x{2720}",
  'map;'                             => "\x{21a6}",
  'Map;'                             => "\x{2905}",
  'mapsto;'                          => "\x{21a6}",
  'mapstodown;'                      => "\x{21a7}",
  'mapstoleft;'                      => "\x{21a4}",
  'mapstoup;'                        => "\x{21a5}",
  'marker;'                          => "\x{25ae}",
  'mcomma;'                          => "\x{2a29}",
  'mcy;'                             => "\x{043c}",
  'Mcy;'                             => "\x{041c}",
  'mdash;'                           => "\x{2014}",
  'mDDot;'                           => "\x{223a}",
  'measuredangle;'                   => "\x{2221}",
  'MediumSpace;'                     => "\x{205f}",
  'Mellintrf;'                       => "\x{2133}",
  'mfr;'                             => "\x{1d52a}",
  'Mfr;'                             => "\x{1d510}",
  'mgr;'                             => "\x{03bc}",
  'Mgr;'                             => "\x{039c}",
  'mho;'                             => "\x{2127}",
  'micro'                            => "\x{00b5}",
  'micro;'                           => "\x{00b5}",
  'mid;'                             => "\x{2223}",
  'midast;'                          => "\x{002a}",
  'midcir;'                          => "\x{2af0}",
  'middot'                           => "\x{00b7}",
  'middot;'                          => "\x{00b7}",
  'minus;'                           => "\x{2212}",
  'minusb;'                          => "\x{229f}",
  'minusd;'                          => "\x{2238}",
  'minusdu;'                         => "\x{2a2a}",
  'MinusPlus;'                       => "\x{2213}",
  'mlcp;'                            => "\x{2adb}",
  'mldr;'                            => "\x{2026}",
  'mnplus;'                          => "\x{2213}",
  'models;'                          => "\x{22a7}",
  'mopf;'                            => "\x{1d55e}",
  'Mopf;'                            => "\x{1d544}",
  'mp;'                              => "\x{2213}",
  'mscr;'                            => "\x{1d4c2}",
  'Mscr;'                            => "\x{2133}",
  'mstpos;'                          => "\x{223e}",
  'mu;'                              => "\x{03bc}",
  'Mu;'                              => "\x{039c}",
  'multimap;'                        => "\x{22b8}",
  'mumap;'                           => "\x{22b8}",
  'nabla;'                           => "\x{2207}",
  'nacute;'                          => "\x{0144}",
  'Nacute;'                          => "\x{0143}",
  'nang;'                            => "\x{0143}",
  'nap;'                             => "\x{2249}",
  'napE;'                            => "\x{2249}",
  'napid;'                           => "\x{2249}",
  'napos;'                           => "\x{0149}",
  'napprox;'                         => "\x{2249}",
  'natur;'                           => "\x{266e}",
  'natural;'                         => "\x{266e}",
  'naturals;'                        => "\x{2115}",
  'nbsp'                             => "\x{00a0}",
  'nbsp;'                            => "\x{00a0}",
  'nbump;'                           => "\x{00a0}",
  'nbumpe;'                          => "\x{00a0}",
  'ncap;'                            => "\x{2a43}",
  'ncaron;'                          => "\x{0148}",
  'Ncaron;'                          => "\x{0147}",
  'ncedil;'                          => "\x{0146}",
  'Ncedil;'                          => "\x{0145}",
  'ncong;'                           => "\x{2247}",
  'ncongdot;'                        => "\x{2247}",
  'ncup;'                            => "\x{2a42}",
  'ncy;'                             => "\x{043d}",
  'Ncy;'                             => "\x{041d}",
  'ndash;'                           => "\x{2013}",
  'ne;'                              => "\x{2260}",
  'nearhk;'                          => "\x{2924}",
  'nearr;'                           => "\x{2197}",
  'neArr;'                           => "\x{21d7}",
  'nearrow;'                         => "\x{2197}",
  'nedot;'                           => "\x{2197}",
  'NegativeMediumSpace;'             => "\x{200b}",
  'NegativeThickSpace;'              => "\x{200b}",
  'NegativeThinSpace;'               => "\x{200b}",
  'NegativeVeryThinSpace;'           => "\x{200b}",
  'nequiv;'                          => "\x{2262}",
  'nesear;'                          => "\x{2928}",
  'nesim;'                           => "\x{2928}",
  'NestedGreaterGreater;'            => "\x{226b}",
  'NestedLessLess;'                  => "\x{226a}",
  'NewLine;'                         => "\x{000a}",
  'nexist;'                          => "\x{2204}",
  'nexists;'                         => "\x{2204}",
  'nfr;'                             => "\x{1d52b}",
  'Nfr;'                             => "\x{1d511}",
  'nge;'                             => "\x{2271}",
  'ngE;'                             => "\x{2271}",
  'ngeq;'                            => "\x{2271}",
  'ngeqq;'                           => "\x{2271}",
  'ngeqslant;'                       => "\x{2271}",
  'nges;'                            => "\x{2271}",
  'nGg;'                             => "\x{2271}",
  'ngr;'                             => "\x{03bd}",
  'Ngr;'                             => "\x{039d}",
  'ngsim;'                           => "\x{2275}",
  'ngt;'                             => "\x{226f}",
  'nGt;'                             => "\x{226f}",
  'ngtr;'                            => "\x{226f}",
  'nGtv;'                            => "\x{226f}",
  'nharr;'                           => "\x{21ae}",
  'nhArr;'                           => "\x{21ce}",
  'nhpar;'                           => "\x{2af2}",
  'ni;'                              => "\x{220b}",
  'nis;'                             => "\x{22fc}",
  'nisd;'                            => "\x{22fa}",
  'niv;'                             => "\x{220b}",
  'njcy;'                            => "\x{045a}",
  'NJcy;'                            => "\x{040a}",
  'nlarr;'                           => "\x{219a}",
  'nlArr;'                           => "\x{21cd}",
  'nldr;'                            => "\x{2025}",
  'nle;'                             => "\x{2270}",
  'nlE;'                             => "\x{2270}",
  'nleftarrow;'                      => "\x{219a}",
  'nLeftarrow;'                      => "\x{21cd}",
  'nleftrightarrow;'                 => "\x{21ae}",
  'nLeftrightarrow;'                 => "\x{21ce}",
  'nleq;'                            => "\x{2270}",
  'nleqq;'                           => "\x{2270}",
  'nleqslant;'                       => "\x{2270}",
  'nles;'                            => "\x{2270}",
  'nless;'                           => "\x{226e}",
  'nLl;'                             => "\x{226e}",
  'nlsim;'                           => "\x{2274}",
  'nlt;'                             => "\x{226e}",
  'nLt;'                             => "\x{226e}",
  'nltri;'                           => "\x{22ea}",
  'nltrie;'                          => "\x{22ec}",
  'nLtv;'                            => "\x{22ec}",
  'nmid;'                            => "\x{2224}",
  'NoBreak;'                         => "\x{2060}",
  'NonBreakingSpace;'                => "\x{00a0}",
  'nopf;'                            => "\x{1d55f}",
  'Nopf;'                            => "\x{2115}",
  'not'                              => "\x{00ac}",
  'not;'                             => "\x{00ac}",
  'Not;'                             => "\x{2aec}",
  'NotCongruent;'                    => "\x{2262}",
  'NotCupCap;'                       => "\x{226d}",
  'NotDoubleVerticalBar;'            => "\x{2226}",
  'NotElement;'                      => "\x{2209}",
  'NotEqual;'                        => "\x{2260}",
  'NotEqualTilde;'                   => "\x{2260}",
  'NotExists;'                       => "\x{2204}",
  'NotGreater;'                      => "\x{226f}",
  'NotGreaterEqual;'                 => "\x{2271}",
  'NotGreaterFullEqual;'             => "\x{2271}",
  'NotGreaterGreater;'               => "\x{2271}",
  'NotGreaterLess;'                  => "\x{2279}",
  'NotGreaterSlantEqual;'            => "\x{2279}",
  'NotGreaterTilde;'                 => "\x{2275}",
  'NotHumpDownHump;'                 => "\x{2275}",
  'NotHumpEqual;'                    => "\x{2275}",
  'notin;'                           => "\x{2209}",
  'notindot;'                        => "\x{2209}",
  'notinE;'                          => "\x{2209}",
  'notinva;'                         => "\x{2209}",
  'notinvb;'                         => "\x{22f7}",
  'notinvc;'                         => "\x{22f6}",
  'NotLeftTriangle;'                 => "\x{22ea}",
  'NotLeftTriangleBar;'              => "\x{22ea}",
  'NotLeftTriangleEqual;'            => "\x{22ec}",
  'NotLess;'                         => "\x{226e}",
  'NotLessEqual;'                    => "\x{2270}",
  'NotLessGreater;'                  => "\x{2278}",
  'NotLessLess;'                     => "\x{2278}",
  'NotLessSlantEqual;'               => "\x{2278}",
  'NotLessTilde;'                    => "\x{2274}",
  'NotNestedGreaterGreater;'         => "\x{2274}",
  'NotNestedLessLess;'               => "\x{2274}",
  'notni;'                           => "\x{220c}",
  'notniva;'                         => "\x{220c}",
  'notnivb;'                         => "\x{22fe}",
  'notnivc;'                         => "\x{22fd}",
  'NotPrecedes;'                     => "\x{2280}",
  'NotPrecedesEqual;'                => "\x{2280}",
  'NotPrecedesSlantEqual;'           => "\x{22e0}",
  'NotReverseElement;'               => "\x{220c}",
  'NotRightTriangle;'                => "\x{22eb}",
  'NotRightTriangleBar;'             => "\x{22eb}",
  'NotRightTriangleEqual;'           => "\x{22ed}",
  'NotSquareSubset;'                 => "\x{22ed}",
  'NotSquareSubsetEqual;'            => "\x{22e2}",
  'NotSquareSuperset;'               => "\x{22e2}",
  'NotSquareSupersetEqual;'          => "\x{22e3}",
  'NotSubset;'                       => "\x{22e3}",
  'NotSubsetEqual;'                  => "\x{2288}",
  'NotSucceeds;'                     => "\x{2281}",
  'NotSucceedsEqual;'                => "\x{2281}",
  'NotSucceedsSlantEqual;'           => "\x{22e1}",
  'NotSucceedsTilde;'                => "\x{22e1}",
  'NotSuperset;'                     => "\x{22e1}",
  'NotSupersetEqual;'                => "\x{2289}",
  'NotTilde;'                        => "\x{2241}",
  'NotTildeEqual;'                   => "\x{2244}",
  'NotTildeFullEqual;'               => "\x{2247}",
  'NotTildeTilde;'                   => "\x{2249}",
  'NotVerticalBar;'                  => "\x{2224}",
  'npar;'                            => "\x{2226}",
  'nparallel;'                       => "\x{2226}",
  'nparsl;'                          => "\x{2226}",
  'npart;'                           => "\x{2226}",
  'npolint;'                         => "\x{2a14}",
  'npr;'                             => "\x{2280}",
  'nprcue;'                          => "\x{22e0}",
  'npre;'                            => "\x{22e0}",
  'nprec;'                           => "\x{2280}",
  'npreceq;'                         => "\x{2280}",
  'nrarr;'                           => "\x{219b}",
  'nrArr;'                           => "\x{21cf}",
  'nrarrc;'                          => "\x{21cf}",
  'nrarrw;'                          => "\x{21cf}",
  'nrightarrow;'                     => "\x{219b}",
  'nRightarrow;'                     => "\x{21cf}",
  'nrtri;'                           => "\x{22eb}",
  'nrtrie;'                          => "\x{22ed}",
  'nsc;'                             => "\x{2281}",
  'nsccue;'                          => "\x{22e1}",
  'nsce;'                            => "\x{22e1}",
  'nscr;'                            => "\x{1d4c3}",
  'Nscr;'                            => "\x{1d4a9}",
  'nshortmid;'                       => "\x{2224}",
  'nshortparallel;'                  => "\x{2226}",
  'nsim;'                            => "\x{2241}",
  'nsime;'                           => "\x{2244}",
  'nsimeq;'                          => "\x{2244}",
  'nsmid;'                           => "\x{2224}",
  'nspar;'                           => "\x{2226}",
  'nsqsube;'                         => "\x{22e2}",
  'nsqsupe;'                         => "\x{22e3}",
  'nsub;'                            => "\x{2284}",
  'nsube;'                           => "\x{2288}",
  'nsubE;'                           => "\x{2288}",
  'nsubset;'                         => "\x{2288}",
  'nsubseteq;'                       => "\x{2288}",
  'nsubseteqq;'                      => "\x{2288}",
  'nsucc;'                           => "\x{2281}",
  'nsucceq;'                         => "\x{2281}",
  'nsup;'                            => "\x{2285}",
  'nsupe;'                           => "\x{2289}",
  'nsupE;'                           => "\x{2289}",
  'nsupset;'                         => "\x{2289}",
  'nsupseteq;'                       => "\x{2289}",
  'nsupseteqq;'                      => "\x{2289}",
  'ntgl;'                            => "\x{2279}",
  'ntilde'                           => "\x{00f1}",
  'ntilde;'                          => "\x{00f1}",
  'Ntilde'                           => "\x{00d1}",
  'Ntilde;'                          => "\x{00d1}",
  'ntlg;'                            => "\x{2278}",
  'ntriangleleft;'                   => "\x{22ea}",
  'ntrianglelefteq;'                 => "\x{22ec}",
  'ntriangleright;'                  => "\x{22eb}",
  'ntrianglerighteq;'                => "\x{22ed}",
  'nu;'                              => "\x{03bd}",
  'Nu;'                              => "\x{039d}",
  'num;'                             => "\x{0023}",
  'numero;'                          => "\x{2116}",
  'numsp;'                           => "\x{2007}",
  'nvap;'                            => "\x{2007}",
  'nvdash;'                          => "\x{22ac}",
  'nvDash;'                          => "\x{22ad}",
  'nVdash;'                          => "\x{22ae}",
  'nVDash;'                          => "\x{22af}",
  'nvge;'                            => "\x{22af}",
  'nvgt;'                            => "\x{22af}",
  'nvHarr;'                          => "\x{2904}",
  'nvinfin;'                         => "\x{29de}",
  'nvlArr;'                          => "\x{2902}",
  'nvle;'                            => "\x{2902}",
  'nvlt;'                            => "\x{2902}",
  'nvltrie;'                         => "\x{2902}",
  'nvrArr;'                          => "\x{2903}",
  'nvrtrie;'                         => "\x{2903}",
  'nvsim;'                           => "\x{2903}",
  'nwarhk;'                          => "\x{2923}",
  'nwarr;'                           => "\x{2196}",
  'nwArr;'                           => "\x{21d6}",
  'nwarrow;'                         => "\x{2196}",
  'nwnear;'                          => "\x{2927}",
  'oacgr;'                           => "\x{03cc}",
  'Oacgr;'                           => "\x{038c}",
  'oacute'                           => "\x{00f3}",
  'oacute;'                          => "\x{00f3}",
  'Oacute'                           => "\x{00d3}",
  'Oacute;'                          => "\x{00d3}",
  'oast;'                            => "\x{229b}",
  'ocir;'                            => "\x{229a}",
  'ocirc'                            => "\x{00f4}",
  'ocirc;'                           => "\x{00f4}",
  'Ocirc'                            => "\x{00d4}",
  'Ocirc;'                           => "\x{00d4}",
  'ocy;'                             => "\x{043e}",
  'Ocy;'                             => "\x{041e}",
  'odash;'                           => "\x{229d}",
  'odblac;'                          => "\x{0151}",
  'Odblac;'                          => "\x{0150}",
  'odiv;'                            => "\x{2a38}",
  'odot;'                            => "\x{2299}",
  'odsold;'                          => "\x{29bc}",
  'oelig;'                           => "\x{0153}",
  'OElig;'                           => "\x{0152}",
  'ofcir;'                           => "\x{29bf}",
  'ofr;'                             => "\x{1d52c}",
  'Ofr;'                             => "\x{1d512}",
  'ogon;'                            => "\x{02db}",
  'ogr;'                             => "\x{03bf}",
  'Ogr;'                             => "\x{039f}",
  'ograve'                           => "\x{00f2}",
  'ograve;'                          => "\x{00f2}",
  'Ograve'                           => "\x{00d2}",
  'Ograve;'                          => "\x{00d2}",
  'ogt;'                             => "\x{29c1}",
  'ohacgr;'                          => "\x{03ce}",
  'OHacgr;'                          => "\x{038f}",
  'ohbar;'                           => "\x{29b5}",
  'ohgr;'                            => "\x{03c9}",
  'OHgr;'                            => "\x{03a9}",
  'ohm;'                             => "\x{03a9}",
  'oint;'                            => "\x{222e}",
  'olarr;'                           => "\x{21ba}",
  'olcir;'                           => "\x{29be}",
  'olcross;'                         => "\x{29bb}",
  'oline;'                           => "\x{203e}",
  'olt;'                             => "\x{29c0}",
  'omacr;'                           => "\x{014d}",
  'Omacr;'                           => "\x{014c}",
  'omega;'                           => "\x{03c9}",
  'Omega;'                           => "\x{03a9}",
  'omicron;'                         => "\x{03bf}",
  'Omicron;'                         => "\x{039f}",
  'omid;'                            => "\x{29b6}",
  'ominus;'                          => "\x{2296}",
  'oopf;'                            => "\x{1d560}",
  'Oopf;'                            => "\x{1d546}",
  'opar;'                            => "\x{29b7}",
  'OpenCurlyDoubleQuote;'            => "\x{201c}",
  'OpenCurlyQuote;'                  => "\x{2018}",
  'operp;'                           => "\x{29b9}",
  'oplus;'                           => "\x{2295}",
  'or;'                              => "\x{2228}",
  'Or;'                              => "\x{2a54}",
  'orarr;'                           => "\x{21bb}",
  'ord;'                             => "\x{2a5d}",
  'order;'                           => "\x{2134}",
  'orderof;'                         => "\x{2134}",
  'ordf'                             => "\x{00aa}",
  'ordf;'                            => "\x{00aa}",
  'ordm'                             => "\x{00ba}",
  'ordm;'                            => "\x{00ba}",
  'origof;'                          => "\x{22b6}",
  'oror;'                            => "\x{2a56}",
  'orslope;'                         => "\x{2a57}",
  'orv;'                             => "\x{2a5b}",
  'oS;'                              => "\x{24c8}",
  'oscr;'                            => "\x{2134}",
  'Oscr;'                            => "\x{1d4aa}",
  'oslash'                           => "\x{00f8}",
  'oslash;'                          => "\x{00f8}",
  'Oslash'                           => "\x{00d8}",
  'Oslash;'                          => "\x{00d8}",
  'osol;'                            => "\x{2298}",
  'otilde'                           => "\x{00f5}",
  'otilde;'                          => "\x{00f5}",
  'Otilde'                           => "\x{00d5}",
  'Otilde;'                          => "\x{00d5}",
  'otimes;'                          => "\x{2297}",
  'Otimes;'                          => "\x{2a37}",
  'otimesas;'                        => "\x{2a36}",
  'ouml'                             => "\x{00f6}",
  'ouml;'                            => "\x{00f6}",
  'Ouml'                             => "\x{00d6}",
  'Ouml;'                            => "\x{00d6}",
  'ovbar;'                           => "\x{233d}",
  'OverBar;'                         => "\x{203e}",
  'OverBrace;'                       => "\x{23de}",
  'OverBracket;'                     => "\x{23b4}",
  'OverParenthesis;'                 => "\x{23dc}",
  'par;'                             => "\x{2225}",
  'para'                             => "\x{00b6}",
  'para;'                            => "\x{00b6}",
  'parallel;'                        => "\x{2225}",
  'parsim;'                          => "\x{2af3}",
  'parsl;'                           => "\x{2afd}",
  'part;'                            => "\x{2202}",
  'PartialD;'                        => "\x{2202}",
  'pcy;'                             => "\x{043f}",
  'Pcy;'                             => "\x{041f}",
  'percnt;'                          => "\x{0025}",
  'period;'                          => "\x{002e}",
  'permil;'                          => "\x{2030}",
  'perp;'                            => "\x{22a5}",
  'pertenk;'                         => "\x{2031}",
  'pfr;'                             => "\x{1d52d}",
  'Pfr;'                             => "\x{1d513}",
  'pgr;'                             => "\x{03c0}",
  'Pgr;'                             => "\x{03a0}",
  'phgr;'                            => "\x{03c6}",
  'PHgr;'                            => "\x{03a6}",
  'phi;'                             => "\x{03c6}",
  'Phi;'                             => "\x{03a6}",
  'phiv;'                            => "\x{03d5}",
  'phmmat;'                          => "\x{2133}",
  'phone;'                           => "\x{260e}",
  'pi;'                              => "\x{03c0}",
  'Pi;'                              => "\x{03a0}",
  'pitchfork;'                       => "\x{22d4}",
  'piv;'                             => "\x{03d6}",
  'planck;'                          => "\x{210f}",
  'planckh;'                         => "\x{210e}",
  'plankv;'                          => "\x{210f}",
  'plus;'                            => "\x{002b}",
  'plusacir;'                        => "\x{2a23}",
  'plusb;'                           => "\x{229e}",
  'pluscir;'                         => "\x{2a22}",
  'plusdo;'                          => "\x{2214}",
  'plusdu;'                          => "\x{2a25}",
  'pluse;'                           => "\x{2a72}",
  'PlusMinus;'                       => "\x{00b1}",
  'plusmn'                           => "\x{00b1}",
  'plusmn;'                          => "\x{00b1}",
  'plussim;'                         => "\x{2a26}",
  'plustwo;'                         => "\x{2a27}",
  'pm;'                              => "\x{00b1}",
  'Poincareplane;'                   => "\x{210c}",
  'pointint;'                        => "\x{2a15}",
  'popf;'                            => "\x{1d561}",
  'Popf;'                            => "\x{2119}",
  'pound'                            => "\x{00a3}",
  'pound;'                           => "\x{00a3}",
  'pr;'                              => "\x{227a}",
  'Pr;'                              => "\x{2abb}",
  'prap;'                            => "\x{2ab7}",
  'prcue;'                           => "\x{227c}",
  'pre;'                             => "\x{2aaf}",
  'prE;'                             => "\x{2ab3}",
  'prec;'                            => "\x{227a}",
  'precapprox;'                      => "\x{2ab7}",
  'preccurlyeq;'                     => "\x{227c}",
  'Precedes;'                        => "\x{227a}",
  'PrecedesEqual;'                   => "\x{2aaf}",
  'PrecedesSlantEqual;'              => "\x{227c}",
  'PrecedesTilde;'                   => "\x{227e}",
  'preceq;'                          => "\x{2aaf}",
  'precnapprox;'                     => "\x{2ab9}",
  'precneqq;'                        => "\x{2ab5}",
  'precnsim;'                        => "\x{22e8}",
  'precsim;'                         => "\x{227e}",
  'prime;'                           => "\x{2032}",
  'Prime;'                           => "\x{2033}",
  'primes;'                          => "\x{2119}",
  'prnap;'                           => "\x{2ab9}",
  'prnE;'                            => "\x{2ab5}",
  'prnsim;'                          => "\x{22e8}",
  'prod;'                            => "\x{220f}",
  'Product;'                         => "\x{220f}",
  'profalar;'                        => "\x{232e}",
  'profline;'                        => "\x{2312}",
  'profsurf;'                        => "\x{2313}",
  'prop;'                            => "\x{221d}",
  'Proportion;'                      => "\x{2237}",
  'Proportional;'                    => "\x{221d}",
  'propto;'                          => "\x{221d}",
  'prsim;'                           => "\x{227e}",
  'prurel;'                          => "\x{22b0}",
  'pscr;'                            => "\x{1d4c5}",
  'Pscr;'                            => "\x{1d4ab}",
  'psgr;'                            => "\x{03c8}",
  'PSgr;'                            => "\x{03a8}",
  'psi;'                             => "\x{03c8}",
  'Psi;'                             => "\x{03a8}",
  'puncsp;'                          => "\x{2008}",
  'qfr;'                             => "\x{1d52e}",
  'Qfr;'                             => "\x{1d514}",
  'qint;'                            => "\x{2a0c}",
  'qopf;'                            => "\x{1d562}",
  'Qopf;'                            => "\x{211a}",
  'qprime;'                          => "\x{2057}",
  'qscr;'                            => "\x{1d4c6}",
  'Qscr;'                            => "\x{1d4ac}",
  'quaternions;'                     => "\x{210d}",
  'quatint;'                         => "\x{2a16}",
  'quest;'                           => "\x{003f}",
  'questeq;'                         => "\x{225f}",
  'quot'                             => "\x{0022}",
  'quot;'                            => "\x{0022}",
  'QUOT'                             => "\x{0022}",
  'QUOT;'                            => "\x{0022}",
  'rAarr;'                           => "\x{21db}",
  'race;'                            => "\x{21db}",
  'racute;'                          => "\x{0155}",
  'Racute;'                          => "\x{0154}",
  'radic;'                           => "\x{221a}",
  'raemptyv;'                        => "\x{29b3}",
  'rang;'                            => "\x{27e9}",
  'Rang;'                            => "\x{27eb}",
  'rangd;'                           => "\x{2992}",
  'range;'                           => "\x{29a5}",
  'rangle;'                          => "\x{27e9}",
  'raquo'                            => "\x{00bb}",
  'raquo;'                           => "\x{00bb}",
  'rarr;'                            => "\x{2192}",
  'rArr;'                            => "\x{21d2}",
  'Rarr;'                            => "\x{21a0}",
  'rarrap;'                          => "\x{2975}",
  'rarrb;'                           => "\x{21e5}",
  'rarrbfs;'                         => "\x{2920}",
  'rarrc;'                           => "\x{2933}",
  'rarrfs;'                          => "\x{291e}",
  'rarrhk;'                          => "\x{21aa}",
  'rarrlp;'                          => "\x{21ac}",
  'rarrpl;'                          => "\x{2945}",
  'rarrsim;'                         => "\x{2974}",
  'rarrtl;'                          => "\x{21a3}",
  'Rarrtl;'                          => "\x{2916}",
  'rarrw;'                           => "\x{219d}",
  'ratail;'                          => "\x{291a}",
  'rAtail;'                          => "\x{291c}",
  'ratio;'                           => "\x{2236}",
  'rationals;'                       => "\x{211a}",
  'rbarr;'                           => "\x{290d}",
  'rBarr;'                           => "\x{290f}",
  'RBarr;'                           => "\x{2910}",
  'rbbrk;'                           => "\x{2773}",
  'rbrace;'                          => "\x{007d}",
  'rbrack;'                          => "\x{005d}",
  'rbrke;'                           => "\x{298c}",
  'rbrksld;'                         => "\x{298e}",
  'rbrkslu;'                         => "\x{2990}",
  'rcaron;'                          => "\x{0159}",
  'Rcaron;'                          => "\x{0158}",
  'rcedil;'                          => "\x{0157}",
  'Rcedil;'                          => "\x{0156}",
  'rceil;'                           => "\x{2309}",
  'rcub;'                            => "\x{007d}",
  'rcy;'                             => "\x{0440}",
  'Rcy;'                             => "\x{0420}",
  'rdca;'                            => "\x{2937}",
  'rdldhar;'                         => "\x{2969}",
  'rdquo;'                           => "\x{201d}",
  'rdquor;'                          => "\x{201d}",
  'rdsh;'                            => "\x{21b3}",
  'Re;'                              => "\x{211c}",
  'real;'                            => "\x{211c}",
  'realine;'                         => "\x{211b}",
  'realpart;'                        => "\x{211c}",
  'reals;'                           => "\x{211d}",
  'rect;'                            => "\x{25ad}",
  'reg'                              => "\x{00ae}",
  'reg;'                             => "\x{00ae}",
  'REG'                              => "\x{00ae}",
  'REG;'                             => "\x{00ae}",
  'ReverseElement;'                  => "\x{220b}",
  'ReverseEquilibrium;'              => "\x{21cb}",
  'ReverseUpEquilibrium;'            => "\x{296f}",
  'rfisht;'                          => "\x{297d}",
  'rfloor;'                          => "\x{230b}",
  'rfr;'                             => "\x{1d52f}",
  'Rfr;'                             => "\x{211c}",
  'rgr;'                             => "\x{03c1}",
  'Rgr;'                             => "\x{03a1}",
  'rHar;'                            => "\x{2964}",
  'rhard;'                           => "\x{21c1}",
  'rharu;'                           => "\x{21c0}",
  'rharul;'                          => "\x{296c}",
  'rho;'                             => "\x{03c1}",
  'Rho;'                             => "\x{03a1}",
  'rhov;'                            => "\x{03f1}",
  'RightAngleBracket;'               => "\x{27e9}",
  'rightarrow;'                      => "\x{2192}",
  'Rightarrow;'                      => "\x{21d2}",
  'RightArrow;'                      => "\x{2192}",
  'RightArrowBar;'                   => "\x{21e5}",
  'RightArrowLeftArrow;'             => "\x{21c4}",
  'rightarrowtail;'                  => "\x{21a3}",
  'RightCeiling;'                    => "\x{2309}",
  'RightDoubleBracket;'              => "\x{27e7}",
  'RightDownTeeVector;'              => "\x{295d}",
  'RightDownVector;'                 => "\x{21c2}",
  'RightDownVectorBar;'              => "\x{2955}",
  'RightFloor;'                      => "\x{230b}",
  'rightharpoondown;'                => "\x{21c1}",
  'rightharpoonup;'                  => "\x{21c0}",
  'rightleftarrows;'                 => "\x{21c4}",
  'rightleftharpoons;'               => "\x{21cc}",
  'rightrightarrows;'                => "\x{21c9}",
  'rightsquigarrow;'                 => "\x{219d}",
  'RightTee;'                        => "\x{22a2}",
  'RightTeeArrow;'                   => "\x{21a6}",
  'RightTeeVector;'                  => "\x{295b}",
  'rightthreetimes;'                 => "\x{22cc}",
  'RightTriangle;'                   => "\x{22b3}",
  'RightTriangleBar;'                => "\x{29d0}",
  'RightTriangleEqual;'              => "\x{22b5}",
  'RightUpDownVector;'               => "\x{294f}",
  'RightUpTeeVector;'                => "\x{295c}",
  'RightUpVector;'                   => "\x{21be}",
  'RightUpVectorBar;'                => "\x{2954}",
  'RightVector;'                     => "\x{21c0}",
  'RightVectorBar;'                  => "\x{2953}",
  'ring;'                            => "\x{02da}",
  'risingdotseq;'                    => "\x{2253}",
  'rlarr;'                           => "\x{21c4}",
  'rlhar;'                           => "\x{21cc}",
  'rlm;'                             => "\x{200f}",
  'rmoust;'                          => "\x{23b1}",
  'rmoustache;'                      => "\x{23b1}",
  'rnmid;'                           => "\x{2aee}",
  'roang;'                           => "\x{27ed}",
  'roarr;'                           => "\x{21fe}",
  'robrk;'                           => "\x{27e7}",
  'ropar;'                           => "\x{2986}",
  'ropf;'                            => "\x{1d563}",
  'Ropf;'                            => "\x{211d}",
  'roplus;'                          => "\x{2a2e}",
  'rotimes;'                         => "\x{2a35}",
  'RoundImplies;'                    => "\x{2970}",
  'rpar;'                            => "\x{0029}",
  'rpargt;'                          => "\x{2994}",
  'rppolint;'                        => "\x{2a12}",
  'rrarr;'                           => "\x{21c9}",
  'Rrightarrow;'                     => "\x{21db}",
  'rsaquo;'                          => "\x{203a}",
  'rscr;'                            => "\x{1d4c7}",
  'Rscr;'                            => "\x{211b}",
  'rsh;'                             => "\x{21b1}",
  'Rsh;'                             => "\x{21b1}",
  'rsqb;'                            => "\x{005d}",
  'rsquo;'                           => "\x{2019}",
  'rsquor;'                          => "\x{2019}",
  'rthree;'                          => "\x{22cc}",
  'rtimes;'                          => "\x{22ca}",
  'rtri;'                            => "\x{25b9}",
  'rtrie;'                           => "\x{22b5}",
  'rtrif;'                           => "\x{25b8}",
  'rtriltri;'                        => "\x{29ce}",
  'RuleDelayed;'                     => "\x{29f4}",
  'ruluhar;'                         => "\x{2968}",
  'rx;'                              => "\x{211e}",
  'sacute;'                          => "\x{015b}",
  'Sacute;'                          => "\x{015a}",
  'sbquo;'                           => "\x{201a}",
  'sc;'                              => "\x{227b}",
  'Sc;'                              => "\x{2abc}",
  'scap;'                            => "\x{2ab8}",
  'scaron;'                          => "\x{0161}",
  'Scaron;'                          => "\x{0160}",
  'sccue;'                           => "\x{227d}",
  'sce;'                             => "\x{2ab0}",
  'scE;'                             => "\x{2ab4}",
  'scedil;'                          => "\x{015f}",
  'Scedil;'                          => "\x{015e}",
  'scirc;'                           => "\x{015d}",
  'Scirc;'                           => "\x{015c}",
  'scnap;'                           => "\x{2aba}",
  'scnE;'                            => "\x{2ab6}",
  'scnsim;'                          => "\x{22e9}",
  'scpolint;'                        => "\x{2a13}",
  'scsim;'                           => "\x{227f}",
  'scy;'                             => "\x{0441}",
  'Scy;'                             => "\x{0421}",
  'sdot;'                            => "\x{22c5}",
  'sdotb;'                           => "\x{22a1}",
  'sdote;'                           => "\x{2a66}",
  'searhk;'                          => "\x{2925}",
  'searr;'                           => "\x{2198}",
  'seArr;'                           => "\x{21d8}",
  'searrow;'                         => "\x{2198}",
  'sect'                             => "\x{00a7}",
  'sect;'                            => "\x{00a7}",
  'semi;'                            => "\x{003b}",
  'seswar;'                          => "\x{2929}",
  'setminus;'                        => "\x{2216}",
  'setmn;'                           => "\x{2216}",
  'sext;'                            => "\x{2736}",
  'sfgr;'                            => "\x{03c2}",
  'sfr;'                             => "\x{1d530}",
  'Sfr;'                             => "\x{1d516}",
  'sfrown;'                          => "\x{2322}",
  'sgr;'                             => "\x{03c3}",
  'Sgr;'                             => "\x{03a3}",
  'sharp;'                           => "\x{266f}",
  'shchcy;'                          => "\x{0449}",
  'SHCHcy;'                          => "\x{0429}",
  'shcy;'                            => "\x{0448}",
  'SHcy;'                            => "\x{0428}",
  'ShortDownArrow;'                  => "\x{2193}",
  'ShortLeftArrow;'                  => "\x{2190}",
  'shortmid;'                        => "\x{2223}",
  'shortparallel;'                   => "\x{2225}",
  'ShortRightArrow;'                 => "\x{2192}",
  'ShortUpArrow;'                    => "\x{2191}",
  'shy'                              => "\x{00ad}",
  'shy;'                             => "\x{00ad}",
  'sigma;'                           => "\x{03c3}",
  'Sigma;'                           => "\x{03a3}",
  'sigmaf;'                          => "\x{03c2}",
  'sigmav;'                          => "\x{03c2}",
  'sim;'                             => "\x{223c}",
  'simdot;'                          => "\x{2a6a}",
  'sime;'                            => "\x{2243}",
  'simeq;'                           => "\x{2243}",
  'simg;'                            => "\x{2a9e}",
  'simgE;'                           => "\x{2aa0}",
  'siml;'                            => "\x{2a9d}",
  'simlE;'                           => "\x{2a9f}",
  'simne;'                           => "\x{2246}",
  'simplus;'                         => "\x{2a24}",
  'simrarr;'                         => "\x{2972}",
  'slarr;'                           => "\x{2190}",
  'SmallCircle;'                     => "\x{2218}",
  'smallsetminus;'                   => "\x{2216}",
  'smashp;'                          => "\x{2a33}",
  'smeparsl;'                        => "\x{29e4}",
  'smid;'                            => "\x{2223}",
  'smile;'                           => "\x{2323}",
  'smt;'                             => "\x{2aaa}",
  'smte;'                            => "\x{2aac}",
  'smtes;'                           => "\x{2aac}",
  'softcy;'                          => "\x{044c}",
  'SOFTcy;'                          => "\x{042c}",
  'sol;'                             => "\x{002f}",
  'solb;'                            => "\x{29c4}",
  'solbar;'                          => "\x{233f}",
  'sopf;'                            => "\x{1d564}",
  'Sopf;'                            => "\x{1d54a}",
  'spades;'                          => "\x{2660}",
  'spadesuit;'                       => "\x{2660}",
  'spar;'                            => "\x{2225}",
  'sqcap;'                           => "\x{2293}",
  'sqcaps;'                          => "\x{2293}",
  'sqcup;'                           => "\x{2294}",
  'sqcups;'                          => "\x{2294}",
  'Sqrt;'                            => "\x{221a}",
  'sqsub;'                           => "\x{228f}",
  'sqsube;'                          => "\x{2291}",
  'sqsubset;'                        => "\x{228f}",
  'sqsubseteq;'                      => "\x{2291}",
  'sqsup;'                           => "\x{2290}",
  'sqsupe;'                          => "\x{2292}",
  'sqsupset;'                        => "\x{2290}",
  'sqsupseteq;'                      => "\x{2292}",
  'squ;'                             => "\x{25a1}",
  'square;'                          => "\x{25a1}",
  'Square;'                          => "\x{25a1}",
  'SquareIntersection;'              => "\x{2293}",
  'SquareSubset;'                    => "\x{228f}",
  'SquareSubsetEqual;'               => "\x{2291}",
  'SquareSuperset;'                  => "\x{2290}",
  'SquareSupersetEqual;'             => "\x{2292}",
  'SquareUnion;'                     => "\x{2294}",
  'squarf;'                          => "\x{25aa}",
  'squf;'                            => "\x{25aa}",
  'srarr;'                           => "\x{2192}",
  'sscr;'                            => "\x{1d4c8}",
  'Sscr;'                            => "\x{1d4ae}",
  'ssetmn;'                          => "\x{2216}",
  'ssmile;'                          => "\x{2323}",
  'sstarf;'                          => "\x{22c6}",
  'star;'                            => "\x{2606}",
  'Star;'                            => "\x{22c6}",
  'starf;'                           => "\x{2605}",
  'straightepsilon;'                 => "\x{03f5}",
  'straightphi;'                     => "\x{03d5}",
  'strns;'                           => "\x{00af}",
  'sub;'                             => "\x{2282}",
  'Sub;'                             => "\x{22d0}",
  'subdot;'                          => "\x{2abd}",
  'sube;'                            => "\x{2286}",
  'subE;'                            => "\x{2ac5}",
  'subedot;'                         => "\x{2ac3}",
  'submult;'                         => "\x{2ac1}",
  'subne;'                           => "\x{228a}",
  'subnE;'                           => "\x{2acb}",
  'subplus;'                         => "\x{2abf}",
  'subrarr;'                         => "\x{2979}",
  'subset;'                          => "\x{2282}",
  'Subset;'                          => "\x{22d0}",
  'subseteq;'                        => "\x{2286}",
  'subseteqq;'                       => "\x{2ac5}",
  'SubsetEqual;'                     => "\x{2286}",
  'subsetneq;'                       => "\x{228a}",
  'subsetneqq;'                      => "\x{2acb}",
  'subsim;'                          => "\x{2ac7}",
  'subsub;'                          => "\x{2ad5}",
  'subsup;'                          => "\x{2ad3}",
  'succ;'                            => "\x{227b}",
  'succapprox;'                      => "\x{2ab8}",
  'succcurlyeq;'                     => "\x{227d}",
  'Succeeds;'                        => "\x{227b}",
  'SucceedsEqual;'                   => "\x{2ab0}",
  'SucceedsSlantEqual;'              => "\x{227d}",
  'SucceedsTilde;'                   => "\x{227f}",
  'succeq;'                          => "\x{2ab0}",
  'succnapprox;'                     => "\x{2aba}",
  'succneqq;'                        => "\x{2ab6}",
  'succnsim;'                        => "\x{22e9}",
  'succsim;'                         => "\x{227f}",
  'SuchThat;'                        => "\x{220b}",
  'sum;'                             => "\x{2211}",
  'Sum;'                             => "\x{2211}",
  'sung;'                            => "\x{266a}",
  'sup;'                             => "\x{2283}",
  'Sup;'                             => "\x{22d1}",
  'sup1'                             => "\x{00b9}",
  'sup1;'                            => "\x{00b9}",
  'sup2'                             => "\x{00b2}",
  'sup2;'                            => "\x{00b2}",
  'sup3'                             => "\x{00b3}",
  'sup3;'                            => "\x{00b3}",
  'supdot;'                          => "\x{2abe}",
  'supdsub;'                         => "\x{2ad8}",
  'supe;'                            => "\x{2287}",
  'supE;'                            => "\x{2ac6}",
  'supedot;'                         => "\x{2ac4}",
  'Superset;'                        => "\x{2283}",
  'SupersetEqual;'                   => "\x{2287}",
  'suphsol;'                         => "\x{27c9}",
  'suphsub;'                         => "\x{2ad7}",
  'suplarr;'                         => "\x{297b}",
  'supmult;'                         => "\x{2ac2}",
  'supne;'                           => "\x{228b}",
  'supnE;'                           => "\x{2acc}",
  'supplus;'                         => "\x{2ac0}",
  'supset;'                          => "\x{2283}",
  'Supset;'                          => "\x{22d1}",
  'supseteq;'                        => "\x{2287}",
  'supseteqq;'                       => "\x{2ac6}",
  'supsetneq;'                       => "\x{228b}",
  'supsetneqq;'                      => "\x{2acc}",
  'supsim;'                          => "\x{2ac8}",
  'supsub;'                          => "\x{2ad4}",
  'supsup;'                          => "\x{2ad6}",
  'swarhk;'                          => "\x{2926}",
  'swarr;'                           => "\x{2199}",
  'swArr;'                           => "\x{21d9}",
  'swarrow;'                         => "\x{2199}",
  'swnwar;'                          => "\x{292a}",
  'szlig'                            => "\x{00df}",
  'szlig;'                           => "\x{00df}",
  'Tab;'                             => "\x{0009}",
  'target;'                          => "\x{2316}",
  'tau;'                             => "\x{03c4}",
  'Tau;'                             => "\x{03a4}",
  'tbrk;'                            => "\x{23b4}",
  'tcaron;'                          => "\x{0165}",
  'Tcaron;'                          => "\x{0164}",
  'tcedil;'                          => "\x{0163}",
  'Tcedil;'                          => "\x{0162}",
  'tcy;'                             => "\x{0442}",
  'Tcy;'                             => "\x{0422}",
  'tdot;'                            => "\x{20db}",
  'telrec;'                          => "\x{2315}",
  'tfr;'                             => "\x{1d531}",
  'Tfr;'                             => "\x{1d517}",
  'tgr;'                             => "\x{03c4}",
  'Tgr;'                             => "\x{03a4}",
  'there4;'                          => "\x{2234}",
  'therefore;'                       => "\x{2234}",
  'Therefore;'                       => "\x{2234}",
  'theta;'                           => "\x{03b8}",
  'Theta;'                           => "\x{0398}",
  'thetasym;'                        => "\x{03d1}",
  'thetav;'                          => "\x{03d1}",
  'thgr;'                            => "\x{03b8}",
  'THgr;'                            => "\x{0398}",
  'thickapprox;'                     => "\x{2248}",
  'thicksim;'                        => "\x{223c}",
  'ThickSpace;'                      => "\x{223c}",
  'thinsp;'                          => "\x{2009}",
  'ThinSpace;'                       => "\x{2009}",
  'thkap;'                           => "\x{2248}",
  'thksim;'                          => "\x{223c}",
  'thorn'                            => "\x{00fe}",
  'thorn;'                           => "\x{00fe}",
  'THORN'                            => "\x{00de}",
  'THORN;'                           => "\x{00de}",
  'tilde;'                           => "\x{02dc}",
  'Tilde;'                           => "\x{223c}",
  'TildeEqual;'                      => "\x{2243}",
  'TildeFullEqual;'                  => "\x{2245}",
  'TildeTilde;'                      => "\x{2248}",
  'times'                            => "\x{00d7}",
  'times;'                           => "\x{00d7}",
  'timesb;'                          => "\x{22a0}",
  'timesbar;'                        => "\x{2a31}",
  'timesd;'                          => "\x{2a30}",
  'tint;'                            => "\x{222d}",
  'toea;'                            => "\x{2928}",
  'top;'                             => "\x{22a4}",
  'topbot;'                          => "\x{2336}",
  'topcir;'                          => "\x{2af1}",
  'topf;'                            => "\x{1d565}",
  'Topf;'                            => "\x{1d54b}",
  'topfork;'                         => "\x{2ada}",
  'tosa;'                            => "\x{2929}",
  'tprime;'                          => "\x{2034}",
  'trade;'                           => "\x{2122}",
  'TRADE;'                           => "\x{2122}",
  'triangle;'                        => "\x{25b5}",
  'triangledown;'                    => "\x{25bf}",
  'triangleleft;'                    => "\x{25c3}",
  'trianglelefteq;'                  => "\x{22b4}",
  'triangleq;'                       => "\x{225c}",
  'triangleright;'                   => "\x{25b9}",
  'trianglerighteq;'                 => "\x{22b5}",
  'tridot;'                          => "\x{25ec}",
  'trie;'                            => "\x{225c}",
  'triminus;'                        => "\x{2a3a}",
  'TripleDot;'                       => "\x{20db}",
  'triplus;'                         => "\x{2a39}",
  'trisb;'                           => "\x{29cd}",
  'tritime;'                         => "\x{2a3b}",
  'trpezium;'                        => "\x{23e2}",
  'tscr;'                            => "\x{1d4c9}",
  'Tscr;'                            => "\x{1d4af}",
  'tscy;'                            => "\x{0446}",
  'TScy;'                            => "\x{0426}",
  'tshcy;'                           => "\x{045b}",
  'TSHcy;'                           => "\x{040b}",
  'tstrok;'                          => "\x{0167}",
  'Tstrok;'                          => "\x{0166}",
  'twixt;'                           => "\x{226c}",
  'twoheadleftarrow;'                => "\x{219e}",
  'twoheadrightarrow;'               => "\x{21a0}",
  'uacgr;'                           => "\x{03cd}",
  'Uacgr;'                           => "\x{038e}",
  'uacute'                           => "\x{00fa}",
  'uacute;'                          => "\x{00fa}",
  'Uacute'                           => "\x{00da}",
  'Uacute;'                          => "\x{00da}",
  'uarr;'                            => "\x{2191}",
  'uArr;'                            => "\x{21d1}",
  'Uarr;'                            => "\x{219f}",
  'Uarrocir;'                        => "\x{2949}",
  'ubrcy;'                           => "\x{045e}",
  'Ubrcy;'                           => "\x{040e}",
  'ubreve;'                          => "\x{016d}",
  'Ubreve;'                          => "\x{016c}",
  'ucirc'                            => "\x{00fb}",
  'ucirc;'                           => "\x{00fb}",
  'Ucirc'                            => "\x{00db}",
  'Ucirc;'                           => "\x{00db}",
  'ucy;'                             => "\x{0443}",
  'Ucy;'                             => "\x{0423}",
  'udarr;'                           => "\x{21c5}",
  'udblac;'                          => "\x{0171}",
  'Udblac;'                          => "\x{0170}",
  'udhar;'                           => "\x{296e}",
  'udiagr;'                          => "\x{03b0}",
  'udigr;'                           => "\x{03cb}",
  'Udigr;'                           => "\x{03ab}",
  'ufisht;'                          => "\x{297e}",
  'ufr;'                             => "\x{1d532}",
  'Ufr;'                             => "\x{1d518}",
  'ugr;'                             => "\x{03c5}",
  'Ugr;'                             => "\x{03a5}",
  'ugrave'                           => "\x{00f9}",
  'ugrave;'                          => "\x{00f9}",
  'Ugrave'                           => "\x{00d9}",
  'Ugrave;'                          => "\x{00d9}",
  'uHar;'                            => "\x{2963}",
  'uharl;'                           => "\x{21bf}",
  'uharr;'                           => "\x{21be}",
  'uhblk;'                           => "\x{2580}",
  'ulcorn;'                          => "\x{231c}",
  'ulcorner;'                        => "\x{231c}",
  'ulcrop;'                          => "\x{230f}",
  'ultri;'                           => "\x{25f8}",
  'umacr;'                           => "\x{016b}",
  'Umacr;'                           => "\x{016a}",
  'uml'                              => "\x{00a8}",
  'uml;'                             => "\x{00a8}",
  'UnderBar;'                        => "\x{005f}",
  'UnderBrace;'                      => "\x{23df}",
  'UnderBracket;'                    => "\x{23b5}",
  'UnderParenthesis;'                => "\x{23dd}",
  'Union;'                           => "\x{22c3}",
  'UnionPlus;'                       => "\x{228e}",
  'uogon;'                           => "\x{0173}",
  'Uogon;'                           => "\x{0172}",
  'uopf;'                            => "\x{1d566}",
  'Uopf;'                            => "\x{1d54c}",
  'uparrow;'                         => "\x{2191}",
  'Uparrow;'                         => "\x{21d1}",
  'UpArrow;'                         => "\x{2191}",
  'UpArrowBar;'                      => "\x{2912}",
  'UpArrowDownArrow;'                => "\x{21c5}",
  'updownarrow;'                     => "\x{2195}",
  'Updownarrow;'                     => "\x{21d5}",
  'UpDownArrow;'                     => "\x{2195}",
  'UpEquilibrium;'                   => "\x{296e}",
  'upharpoonleft;'                   => "\x{21bf}",
  'upharpoonright;'                  => "\x{21be}",
  'uplus;'                           => "\x{228e}",
  'UpperLeftArrow;'                  => "\x{2196}",
  'UpperRightArrow;'                 => "\x{2197}",
  'upsi;'                            => "\x{03c5}",
  'Upsi;'                            => "\x{03d2}",
  'upsih;'                           => "\x{03d2}",
  'upsilon;'                         => "\x{03c5}",
  'Upsilon;'                         => "\x{03a5}",
  'UpTee;'                           => "\x{22a5}",
  'UpTeeArrow;'                      => "\x{21a5}",
  'upuparrows;'                      => "\x{21c8}",
  'urcorn;'                          => "\x{231d}",
  'urcorner;'                        => "\x{231d}",
  'urcrop;'                          => "\x{230e}",
  'uring;'                           => "\x{016f}",
  'Uring;'                           => "\x{016e}",
  'urtri;'                           => "\x{25f9}",
  'uscr;'                            => "\x{1d4ca}",
  'Uscr;'                            => "\x{1d4b0}",
  'utdot;'                           => "\x{22f0}",
  'utilde;'                          => "\x{0169}",
  'Utilde;'                          => "\x{0168}",
  'utri;'                            => "\x{25b5}",
  'utrif;'                           => "\x{25b4}",
  'uuarr;'                           => "\x{21c8}",
  'uuml'                             => "\x{00fc}",
  'uuml;'                            => "\x{00fc}",
  'Uuml'                             => "\x{00dc}",
  'Uuml;'                            => "\x{00dc}",
  'uwangle;'                         => "\x{29a7}",
  'vangrt;'                          => "\x{299c}",
  'varepsilon;'                      => "\x{03f5}",
  'varkappa;'                        => "\x{03f0}",
  'varnothing;'                      => "\x{2205}",
  'varphi;'                          => "\x{03d5}",
  'varpi;'                           => "\x{03d6}",
  'varpropto;'                       => "\x{221d}",
  'varr;'                            => "\x{2195}",
  'vArr;'                            => "\x{21d5}",
  'varrho;'                          => "\x{03f1}",
  'varsigma;'                        => "\x{03c2}",
  'varsubsetneq;'                    => "\x{03c2}",
  'varsubsetneqq;'                   => "\x{03c2}",
  'varsupsetneq;'                    => "\x{03c2}",
  'varsupsetneqq;'                   => "\x{03c2}",
  'vartheta;'                        => "\x{03d1}",
  'vartriangleleft;'                 => "\x{22b2}",
  'vartriangleright;'                => "\x{22b3}",
  'vBar;'                            => "\x{2ae8}",
  'Vbar;'                            => "\x{2aeb}",
  'vBarv;'                           => "\x{2ae9}",
  'vcy;'                             => "\x{0432}",
  'Vcy;'                             => "\x{0412}",
  'vdash;'                           => "\x{22a2}",
  'vDash;'                           => "\x{22a8}",
  'Vdash;'                           => "\x{22a9}",
  'VDash;'                           => "\x{22ab}",
  'Vdashl;'                          => "\x{2ae6}",
  'vee;'                             => "\x{2228}",
  'Vee;'                             => "\x{22c1}",
  'veebar;'                          => "\x{22bb}",
  'veeeq;'                           => "\x{225a}",
  'vellip;'                          => "\x{22ee}",
  'verbar;'                          => "\x{007c}",
  'Verbar;'                          => "\x{2016}",
  'vert;'                            => "\x{007c}",
  'Vert;'                            => "\x{2016}",
  'VerticalBar;'                     => "\x{2223}",
  'VerticalLine;'                    => "\x{007c}",
  'VerticalSeparator;'               => "\x{2758}",
  'VerticalTilde;'                   => "\x{2240}",
  'VeryThinSpace;'                   => "\x{200a}",
  'vfr;'                             => "\x{1d533}",
  'Vfr;'                             => "\x{1d519}",
  'vltri;'                           => "\x{22b2}",
  'vnsub;'                           => "\x{22b2}",
  'vnsup;'                           => "\x{22b2}",
  'vopf;'                            => "\x{1d567}",
  'Vopf;'                            => "\x{1d54d}",
  'vprop;'                           => "\x{221d}",
  'vrtri;'                           => "\x{22b3}",
  'vscr;'                            => "\x{1d4cb}",
  'Vscr;'                            => "\x{1d4b1}",
  'vsubne;'                          => "\x{1d4b1}",
  'vsubnE;'                          => "\x{1d4b1}",
  'vsupne;'                          => "\x{1d4b1}",
  'vsupnE;'                          => "\x{1d4b1}",
  'Vvdash;'                          => "\x{22aa}",
  'vzigzag;'                         => "\x{299a}",
  'wcirc;'                           => "\x{0175}",
  'Wcirc;'                           => "\x{0174}",
  'wedbar;'                          => "\x{2a5f}",
  'wedge;'                           => "\x{2227}",
  'Wedge;'                           => "\x{22c0}",
  'wedgeq;'                          => "\x{2259}",
  'weierp;'                          => "\x{2118}",
  'wfr;'                             => "\x{1d534}",
  'Wfr;'                             => "\x{1d51a}",
  'wopf;'                            => "\x{1d568}",
  'Wopf;'                            => "\x{1d54e}",
  'wp;'                              => "\x{2118}",
  'wr;'                              => "\x{2240}",
  'wreath;'                          => "\x{2240}",
  'wscr;'                            => "\x{1d4cc}",
  'Wscr;'                            => "\x{1d4b2}",
  'xcap;'                            => "\x{22c2}",
  'xcirc;'                           => "\x{25ef}",
  'xcup;'                            => "\x{22c3}",
  'xdtri;'                           => "\x{25bd}",
  'xfr;'                             => "\x{1d535}",
  'Xfr;'                             => "\x{1d51b}",
  'xgr;'                             => "\x{03be}",
  'Xgr;'                             => "\x{039e}",
  'xharr;'                           => "\x{27f7}",
  'xhArr;'                           => "\x{27fa}",
  'xi;'                              => "\x{03be}",
  'Xi;'                              => "\x{039e}",
  'xlarr;'                           => "\x{27f5}",
  'xlArr;'                           => "\x{27f8}",
  'xmap;'                            => "\x{27fc}",
  'xnis;'                            => "\x{22fb}",
  'xodot;'                           => "\x{2a00}",
  'xopf;'                            => "\x{1d569}",
  'Xopf;'                            => "\x{1d54f}",
  'xoplus;'                          => "\x{2a01}",
  'xotime;'                          => "\x{2a02}",
  'xrarr;'                           => "\x{27f6}",
  'xrArr;'                           => "\x{27f9}",
  'xscr;'                            => "\x{1d4cd}",
  'Xscr;'                            => "\x{1d4b3}",
  'xsqcup;'                          => "\x{2a06}",
  'xuplus;'                          => "\x{2a04}",
  'xutri;'                           => "\x{25b3}",
  'xvee;'                            => "\x{22c1}",
  'xwedge;'                          => "\x{22c0}",
  'yacute'                           => "\x{00fd}",
  'yacute;'                          => "\x{00fd}",
  'Yacute'                           => "\x{00dd}",
  'Yacute;'                          => "\x{00dd}",
  'yacy;'                            => "\x{044f}",
  'YAcy;'                            => "\x{042f}",
  'ycirc;'                           => "\x{0177}",
  'Ycirc;'                           => "\x{0176}",
  'ycy;'                             => "\x{044b}",
  'Ycy;'                             => "\x{042b}",
  'yen'                              => "\x{00a5}",
  'yen;'                             => "\x{00a5}",
  'yfr;'                             => "\x{1d536}",
  'Yfr;'                             => "\x{1d51c}",
  'yicy;'                            => "\x{0457}",
  'YIcy;'                            => "\x{0407}",
  'yopf;'                            => "\x{1d56a}",
  'Yopf;'                            => "\x{1d550}",
  'yscr;'                            => "\x{1d4ce}",
  'Yscr;'                            => "\x{1d4b4}",
  'yucy;'                            => "\x{044e}",
  'YUcy;'                            => "\x{042e}",
  'yuml'                             => "\x{00ff}",
  'yuml;'                            => "\x{00ff}",
  'Yuml;'                            => "\x{0178}",
  'zacute;'                          => "\x{017a}",
  'Zacute;'                          => "\x{0179}",
  'zcaron;'                          => "\x{017e}",
  'Zcaron;'                          => "\x{017d}",
  'zcy;'                             => "\x{0437}",
  'Zcy;'                             => "\x{0417}",
  'zdot;'                            => "\x{017c}",
  'Zdot;'                            => "\x{017b}",
  'zeetrf;'                          => "\x{2128}",
  'ZeroWidthSpace;'                  => "\x{200b}",
  'zeta;'                            => "\x{03b6}",
  'Zeta;'                            => "\x{0396}",
  'zfr;'                             => "\x{1d537}",
  'Zfr;'                             => "\x{2128}",
  'zgr;'                             => "\x{03b6}",
  'Zgr;'                             => "\x{0396}",
  'zhcy;'                            => "\x{0436}",
  'ZHcy;'                            => "\x{0416}",
  'zigrarr;'                         => "\x{21dd}",
  'zopf;'                            => "\x{1d56b}",
  'Zopf;'                            => "\x{2124}",
  'zscr;'                            => "\x{1d4cf}",
  'Zscr;'                            => "\x{1d4b5}",
  'zwj;'                             => "\x{200d}",
  'zwnj;'                            => "\x{200c}"
);

# Reverse entities for html_escape
my %REVERSE;
$REVERSE{$ENTITIES{$_}} //= $_ for reverse sort keys %ENTITIES;

# "apos"
$ENTITIES{'apos;'} = "\x{0027}";

# Entities regex for html_unescape
my $ENTITIES_RE = qr/&(?:\#((?:\d{1,7}|x[0-9A-Fa-f]{1,6}));|([\w\.]+;?))/;

# Encode cache
my %ENCODE;

# "Bart, stop pestering Satan!"
our @EXPORT_OK = (
  qw/b64_decode b64_encode camelize decamelize decode encode get_line/,
  qw/hmac_md5_sum hmac_sha1_sum html_escape html_unescape md5_bytes md5_sum/,
  qw/punycode_decode punycode_encode qp_decode qp_encode quote/,
  qw/secure_compare sha1_bytes sha1_sum trim unquote url_escape/,
  qw/url_unescape xml_escape/
);

sub b64_decode { decode_base64(shift) }

sub b64_encode { encode_base64(shift, shift) }

sub camelize {
  my $string = shift;
  return $string if $string =~ /^[A-Z]/;

  # Camel case words
  return join '::', map {
    join '', map { ucfirst lc } split /_/, $_
  } split /-/, $string;
}

sub decamelize {
  my $string = shift;
  return $string if $string !~ /^[A-Z]/;

  # Module parts
  my @parts;
  for my $part (split /\:\:/, $string) {

    # Snake case words
    my @words;
    push @words, lc $1 while $part =~ s/([A-Z]{1}[^A-Z]*)//;
    push @parts, join '_', @words;
  }

  return join '-', @parts;
}

sub decode {
  my ($encoding, $bytes) = @_;

  # Try decoding
  return unless eval {

    # UTF-8
    if ($encoding eq 'UTF-8') { die unless utf8::decode $bytes }

    # Everything else
    else {
      $bytes
        = ($ENCODE{$encoding} ||= find_encoding($encoding))->decode($bytes, 1);
    }

    1;
  };

  return $bytes;
}

sub encode {
  my ($encoding, $chars) = @_;

  # UTF-8
  if ($encoding eq 'UTF-8') {
    utf8::encode $chars;
    return $chars;
  }

  # Everything else
  return ($ENCODE{$encoding} ||= find_encoding($encoding))->encode($chars);
}

sub get_line {
  my $stringref = shift;

  # Locate line ending
  return if (my $pos = index $$stringref, "\x0a") == -1;

  # Extract line and ending
  my $line = substr $$stringref, 0, $pos + 1, '';
  $line =~ s/\x0d?\x0a$//;

  return $line;
}

sub hmac_md5_sum  { _hmac(0, @_) }
sub hmac_sha1_sum { _hmac(1, @_) }

sub html_escape {
  my ($string, $pattern) = @_;
  $pattern ||= '^\n\r\t !\#\$%\(-;=?-~';
  return $string unless $string =~ /[^$pattern]/;
  $string =~ s/([$pattern])/_escape($1)/ge;
  return $string;
}

# "Daddy, I'm scared. Too scared to even wet my pants.
#  Just relax and it'll come, son."
sub html_unescape {
  my $string = shift;
  $string =~ s/$ENTITIES_RE/_unescape($1, $2)/ge;
  return $string;
}

sub md5_bytes { md5(@_) }
sub md5_sum   { md5_hex(@_) }

sub punycode_decode {
  my $input = shift;
  use integer;

  # Defaults
  my $n    = PC_INITIAL_N;
  my $i    = 0;
  my $bias = PC_INITIAL_BIAS;
  my @output;

  # Delimiter
  if ($input =~ s/(.*)$DELIMITER//s) { push @output, split //, $1 }

  # Decode (direct translation of RFC 3492)
  while (length $input) {
    my $oldi = $i;
    my $w    = 1;

    # Base to infinity in steps of base
    for (my $k = PC_BASE; 1; $k += PC_BASE) {

      # Digit
      my $digit = ord substr $input, 0, 1, '';
      $digit = $digit < 0x40 ? $digit + (26 - 0x30) : ($digit & 0x1f) - 1;
      $i += $digit * $w;
      my $t = $k - $bias;
      $t = $t < PC_TMIN ? PC_TMIN : $t > PC_TMAX ? PC_TMAX : $t;
      last if $digit < $t;

      $w *= (PC_BASE - $t);
    }

    # Bias
    $bias = _adapt($i - $oldi, @output + 1, $oldi == 0);
    $n += $i / (@output + 1);
    $i = $i % (@output + 1);

    # Insert
    splice @output, $i, 0, chr($n);
    $i++;
  }

  return join '', @output;
}

sub punycode_encode {
  use integer;

  # Defaults
  my $output = shift;
  my $len    = length $output;

  # Split input
  my @input = map ord, split //, $output;
  my @chars = sort grep { $_ >= PC_INITIAL_N } @input;

  # Remove non basic characters
  $output =~ s/[^\x00-\x7f]+//gs;

  # Non basic characters in input
  my $h = my $b = length $output;
  $output .= $DELIMITER if $b > 0;

  # Defaults
  my $n     = PC_INITIAL_N;
  my $delta = 0;
  my $bias  = PC_INITIAL_BIAS;

  # Encode (direct translation of RFC 3492)
  for my $m (@chars) {

    # Basic character
    next if $m < $n;

    # Delta
    $delta += ($m - $n) * ($h + 1);

    # Walk all code points in order
    $n = $m;
    for (my $i = 0; $i < $len; $i++) {
      my $c = $input[$i];

      # Basic character
      $delta++ if $c < $n;

      # Non basic character
      if ($c == $n) {
        my $q = $delta;

        # Base to infinity in steps of base
        for (my $k = PC_BASE; 1; $k += PC_BASE) {
          my $t = $k - $bias;
          $t = $t < PC_TMIN ? PC_TMIN : $t > PC_TMAX ? PC_TMAX : $t;
          last if $q < $t;

          # Code point for digit "t"
          my $o = $t + (($q - $t) % (PC_BASE - $t));
          $output .= chr $o + ($o < 26 ? 0x61 : 0x30 - 26);

          $q = ($q - $t) / (PC_BASE - $t);
        }

        # Code point for digit "q"
        $output .= chr $q + ($q < 26 ? 0x61 : 0x30 - 26);

        # Bias
        $bias = _adapt($delta, $h + 1, $h == $b);
        $delta = 0;
        $h++;
      }
    }

    $delta++;
    $n++;
  }

  return $output;
}

sub qp_decode { decode_qp(shift) }

sub qp_encode { encode_qp(shift) }

sub quote {
  my $string = shift;
  $string =~ s/(["\\])/\\$1/g;
  return qq/"$string"/;
}

sub secure_compare {
  my ($a, $b) = @_;
  return if length $a != length $b;
  my $r = 0;
  $r |= ord(substr $a, $_) ^ ord(substr $b, $_) for 0 .. length($a) - 1;
  return $r == 0 ? 1 : undef;
}

sub sha1_bytes { sha1(@_) }
sub sha1_sum   { sha1_hex(@_) }

sub trim {
  my $string = shift;
  for ($string) {
    s/^\s*//;
    s/\s*$//;
  }
  return $string;
}

sub unquote {
  my $string = shift;
  return $string unless $string =~ /^".*"$/g;

  # Unquote
  for ($string) {
    s/^"//g;
    s/"$//g;
    s/\\\\/\\/g;
    s/\\"/"/g;
  }

  return $string;
}

sub url_escape {
  my ($string, $pattern) = @_;
  $pattern ||= '^A-Za-z0-9\-\.\_\~';
  return $string unless $string =~ /[$pattern]/;
  $string =~ s/([$pattern])/sprintf('%%%02X',ord($1))/ge;
  return $string;
}

# "I've gone back in time to when dinosaurs weren't just confined to zoos."
sub url_unescape {
  my $string = shift;
  return $string if index($string, '%') == -1;
  $string =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
  return $string;
}

sub xml_escape {
  my $string = shift;
  for ($string) {
    s/&/&amp;/g;
    s/</&lt;/g;
    s/>/&gt;/g;
    s/"/&quot;/g;
    s/'/&#39;/g;
  }
  return $string;
}

# Helper for punycode
sub _adapt {
  my ($delta, $numpoints, $firsttime) = @_;

  use integer;
  $delta = $firsttime ? $delta / PC_DAMP : $delta / 2;
  $delta += $delta / $numpoints;
  my $k = 0;
  while ($delta > ((PC_BASE - PC_TMIN) * PC_TMAX) / 2) {
    $delta /= PC_BASE - PC_TMIN;
    $k += PC_BASE;
  }

  return $k + (((PC_BASE - PC_TMIN + 1) * $delta) / ($delta + PC_SKEW));
}

# Helper for html_escape
sub _escape {
  return "&$REVERSE{$_[0]}" if exists $REVERSE{$_[0]};
  return '&#' . ord($_[0]) . ';';
}

sub _hmac {
  my ($sha, $string, $secret) = @_;

  # Hash function
  my $hash = $sha ? sub { sha1(@_) } : sub { md5(@_) };

  # Secret
  $secret = $secret ? "$secret" : 'Very unsecure!';
  $secret = $hash->($secret) if length $secret > 64;

  # HMAC
  my $ipad = $secret ^ (chr(0x36) x 64);
  my $opad = $secret ^ (chr(0x5c) x 64);
  return unpack 'H*', $hash->($opad . $hash->($ipad . $string));
}

# Helper for html_unescape
sub _unescape {

  # Numeric
  return substr($_[0], 0, 1) eq 'x' ? chr(hex $_[0]) : chr($_[0]) unless $_[1];

  # Find entity name
  my $rest   = '';
  my $entity = $_[1];
  while (length $entity) {
    return "$ENTITIES{$entity}$rest" if exists $ENTITIES{$entity};
    $rest = chop($entity) . $rest;
  }
  return "&$_[1]";
}

1;
__END__

=head1 NAME

Mojo::Util - Portable utility functions

=head1 SYNOPSIS

  use Mojo::Util qw/url_escape url_unescape/;

  my $string = 'test=23';
  my $escaped = url_escape $string;
  say url_unescape $escaped;

=head1 DESCRIPTION

L<Mojo::Util> provides portable utility functions for L<Mojo>.

=head1 FUNCTIONS

L<Mojo::Util> implements the following functions.

=head2 C<b64_decode>

  my $string = b64_decode $b64;

Base64 decode string.

=head2 C<b64_encode>

  my $b64 = b64_encode $string;
  my $b64 = b64_encode $string, '';

Base64 encode string, the line ending defaults to a newline.

=head2 C<camelize>

  my $camelcase = camelize $snakecase;

Convert snake case string to camel case and replace C<-> with C<::>.

  # "FooBar"
  camelize 'foo_bar';

  # "FooBar::Baz"
  camelize 'foo_bar-baz';

  # "FooBar::Baz"
  camelize 'FooBar::Baz';

=head2 C<decamelize>

  my $snakecase = decamelize $camelcase;

Convert camel case string to snake case and replace C<::> with C<->.

  # "foo_bar"
  decamelize 'FooBar';

  # "foo_bar-baz"
  decamelize 'FooBar::Baz';

  # "foo_bar-baz"
  decamelize 'foo_bar-baz';

=head2 C<decode>

  my $chars = decode 'UTF-8', $bytes;

Decode bytes to characters.

=head2 C<encode>

  my $bytes = encode 'UTF-8', $chars;

Encode characters to bytes.

=head2 C<get_line>

  my $line = get_line \$string;

Extract whole line from string or return C<undef>. Lines are expected to end
with C<0x0d 0x0a> or C<0x0a>.

=head2 C<hmac_md5_sum>

  my $checksum = hmac_md5_sum $string, $secret;

Generate HMAC-MD5 checksum for string.

=head2 C<hmac_sha1_sum>

  my $checksum = hmac_sha1_sum $string, $secret;

Generate HMAC-SHA1 checksum for string.

=head2 C<html_escape>

  my $escaped = html_escape $string;
  my $escaped = html_escape $string, '^\n\r\t !\#\$%\(-;=?-~';

Escape unsafe characters in string with HTML5 entities, the pattern used
defaults to C<^\n\r\t !\#\$%\(-;=?-~>.

=head2 C<html_unescape>

  my $string = html_unescape $escaped;

Unescape all HTML5 entities in string.

=head2 C<md5_bytes>

  my $checksum = md5_bytes $string;

Generate binary MD5 checksum for string.

=head2 C<md5_sum>

  my $checksum = md5_sum $string;

Generate MD5 checksum for string.

=head2 C<punycode_decode>

  my $string = punycode_decode $punycode;

Punycode decode string.

=head2 C<punycode_encode>

  my $punycode = punycode_encode $string;

Punycode encode string.

=head2 C<quote>

  my $quoted = quote $string;

Quote string.

=head2 C<qp_decode>

  my $string = qp_decode $qp;

Quoted Printable decode string.

=head2 C<qp_encode>

  my $qp = qp_encode $string;

Quoted Printable encode string.

=head2 C<secure_compare>

  my $success = secure_compare $string1, $string2;

Constant time comparison algorithm to prevent timing attacks.

=head2 C<sha1_bytes>

  my $checksum = sha1_bytes $string;

Generate binary SHA1 checksum for string.

=head2 C<sha1_sum>

  my $checksum = sha1_sum $string;

Generate SHA1 checksum for string.

=head2 C<trim>

  my $trimmed = trim $string;

Trim whitespace characters from both ends of string.

=head2 C<unquote>

  my $string = unquote $quoted;

Unquote string.

=head2 C<url_escape>

  my $escaped = url_escape $string;
  my $escaped = url_escape $string, '^A-Za-z0-9\-\.\_\~';

URL escape string, the pattern used defaults to C<^A-Za-z0-9\-\.\_\~>.

=head2 C<url_unescape>

  my $string = url_unescape $escaped;

URL unescape string.

=head2 C<xml_escape>

  my $escaped = xml_escape $string;

Escape only the characters C<&>, C<E<lt>>, C<E<gt>>, C<"> and C<'> in string,
this is a much faster version of C<html_escape>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
