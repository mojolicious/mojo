# This Makefile is for the Mojo extension to perl.
#
# It was generated automatically by MakeMaker version
# 6.42 (Revision: 41145) from the contents of
# Makefile.PL. Don't edit this file, edit Makefile.PL instead.
#
#       ANY CHANGES MADE HERE WILL BE LOST!
#
#   MakeMaker ARGV: ()
#
#   MakeMaker Parameters:

#     AUTHOR => q[Sebastian Riedel <sri@cpan.org>]
#     EXE_FILES => [q[bin/mojo], q[bin/mojolicious]]
#     LICENSE => q[perl]
#     NAME => q[Mojo]
#     PREREQ_PM => { FindBin=>q[0], File::Spec=>q[0], Test::Builder::Module=>q[0], Encode=>q[0], POSIX=>q[0], Digest::MD5=>q[0], File::Path=>q[0], File::Spec::Functions=>q[0], Test::Harness=>q[0], File::Copy=>q[0], IO::File=>q[0], MIME::QuotedPrint=>q[0], Carp=>q[0], Test::More=>q[0], IO::Select=>q[0], IO::Socket=>q[0], MIME::Base64=>q[0], File::Temp=>q[0], File::Basename=>q[0], Cwd=>q[0] }
#     VERSION_FROM => q[lib/Mojo.pm]
#     test => { TESTS=>q[t/*.t t/*/*.t t/*/*/*.t] }

# --- MakeMaker post_initialize section:


# --- MakeMaker const_config section:

# These definitions are from config.sh (via /usr/local/lib/perl5/5.10.0/darwin-2level/Config.pm)

# They may have been overridden via Makefile.PL or on the command line
AR = ar
CC = cc
CCCDLFLAGS =  
CCDLFLAGS =  
DLEXT = bundle
DLSRC = dl_dlopen.xs
EXE_EXT = 
FULL_AR = /usr/bin/ar
LD = env MACOSX_DEPLOYMENT_TARGET=10.3 cc
LDDLFLAGS =  -bundle -undefined dynamic_lookup -L/usr/local/lib -L/opt/local/lib
LDFLAGS =  -L/usr/local/lib -L/opt/local/lib
LIBC = /usr/lib/libc.dylib
LIB_EXT = .a
OBJ_EXT = .o
OSNAME = darwin
OSVERS = 9.1.0
RANLIB = ranlib
SITELIBEXP = /usr/local/lib/perl5/site_perl/5.10.0
SITEARCHEXP = /usr/local/lib/perl5/site_perl/5.10.0/darwin-2level
SO = dylib
VENDORARCHEXP = 
VENDORLIBEXP = 


# --- MakeMaker constants section:
AR_STATIC_ARGS = cr
DIRFILESEP = /
DFSEP = $(DIRFILESEP)
NAME = Mojo
NAME_SYM = Mojo
VERSION = 0.8
VERSION_MACRO = VERSION
VERSION_SYM = 0_8
DEFINE_VERSION = -D$(VERSION_MACRO)=\"$(VERSION)\"
XS_VERSION = 0.8
XS_VERSION_MACRO = XS_VERSION
XS_DEFINE_VERSION = -D$(XS_VERSION_MACRO)=\"$(XS_VERSION)\"
INST_ARCHLIB = blib/arch
INST_SCRIPT = blib/script
INST_BIN = blib/bin
INST_LIB = blib/lib
INST_MAN1DIR = blib/man1
INST_MAN3DIR = blib/man3
MAN1EXT = 1
MAN3EXT = 3
INSTALLDIRS = site
DESTDIR = 
PREFIX = $(SITEPREFIX)
PERLPREFIX = /usr/local
SITEPREFIX = /usr/local
VENDORPREFIX = 
INSTALLPRIVLIB = /usr/local/lib/perl5/5.10.0
DESTINSTALLPRIVLIB = $(DESTDIR)$(INSTALLPRIVLIB)
INSTALLSITELIB = /usr/local/lib/perl5/site_perl/5.10.0
DESTINSTALLSITELIB = $(DESTDIR)$(INSTALLSITELIB)
INSTALLVENDORLIB = 
DESTINSTALLVENDORLIB = $(DESTDIR)$(INSTALLVENDORLIB)
INSTALLARCHLIB = /usr/local/lib/perl5/5.10.0/darwin-2level
DESTINSTALLARCHLIB = $(DESTDIR)$(INSTALLARCHLIB)
INSTALLSITEARCH = /usr/local/lib/perl5/site_perl/5.10.0/darwin-2level
DESTINSTALLSITEARCH = $(DESTDIR)$(INSTALLSITEARCH)
INSTALLVENDORARCH = 
DESTINSTALLVENDORARCH = $(DESTDIR)$(INSTALLVENDORARCH)
INSTALLBIN = /usr/local/bin
DESTINSTALLBIN = $(DESTDIR)$(INSTALLBIN)
INSTALLSITEBIN = /usr/local/bin
DESTINSTALLSITEBIN = $(DESTDIR)$(INSTALLSITEBIN)
INSTALLVENDORBIN = 
DESTINSTALLVENDORBIN = $(DESTDIR)$(INSTALLVENDORBIN)
INSTALLSCRIPT = /usr/local/bin
DESTINSTALLSCRIPT = $(DESTDIR)$(INSTALLSCRIPT)
INSTALLSITESCRIPT = /usr/local/bin
DESTINSTALLSITESCRIPT = $(DESTDIR)$(INSTALLSITESCRIPT)
INSTALLVENDORSCRIPT = 
DESTINSTALLVENDORSCRIPT = $(DESTDIR)$(INSTALLVENDORSCRIPT)
INSTALLMAN1DIR = /usr/local/man/man1
DESTINSTALLMAN1DIR = $(DESTDIR)$(INSTALLMAN1DIR)
INSTALLSITEMAN1DIR = /usr/local/man/man1
DESTINSTALLSITEMAN1DIR = $(DESTDIR)$(INSTALLSITEMAN1DIR)
INSTALLVENDORMAN1DIR = 
DESTINSTALLVENDORMAN1DIR = $(DESTDIR)$(INSTALLVENDORMAN1DIR)
INSTALLMAN3DIR = /usr/local/man/man3
DESTINSTALLMAN3DIR = $(DESTDIR)$(INSTALLMAN3DIR)
INSTALLSITEMAN3DIR = /usr/local/man/man3
DESTINSTALLSITEMAN3DIR = $(DESTDIR)$(INSTALLSITEMAN3DIR)
INSTALLVENDORMAN3DIR = 
DESTINSTALLVENDORMAN3DIR = $(DESTDIR)$(INSTALLVENDORMAN3DIR)
PERL_LIB = /usr/local/lib/perl5/5.10.0
PERL_ARCHLIB = /usr/local/lib/perl5/5.10.0/darwin-2level
LIBPERL_A = libperl.a
FIRST_MAKEFILE = Makefile
MAKEFILE_OLD = Makefile.old
MAKE_APERL_FILE = Makefile.aperl
PERLMAINCC = $(CC)
PERL_INC = /usr/local/lib/perl5/5.10.0/darwin-2level/CORE
PERL = /usr/bin/perl
FULLPERL = /usr/bin/perl
ABSPERL = $(PERL)
PERLRUN = $(PERL)
FULLPERLRUN = $(FULLPERL)
ABSPERLRUN = $(ABSPERL)
PERLRUNINST = $(PERLRUN) "-I$(INST_ARCHLIB)" "-I$(INST_LIB)"
FULLPERLRUNINST = $(FULLPERLRUN) "-I$(INST_ARCHLIB)" "-I$(INST_LIB)"
ABSPERLRUNINST = $(ABSPERLRUN) "-I$(INST_ARCHLIB)" "-I$(INST_LIB)"
PERL_CORE = 0
PERM_RW = 644
PERM_RWX = 755

MAKEMAKER   = /usr/local/lib/perl5/5.10.0/ExtUtils/MakeMaker.pm
MM_VERSION  = 6.42
MM_REVISION = 41145

# FULLEXT = Pathname for extension directory (eg Foo/Bar/Oracle).
# BASEEXT = Basename part of FULLEXT. May be just equal FULLEXT. (eg Oracle)
# PARENT_NAME = NAME without BASEEXT and no trailing :: (eg Foo::Bar)
# DLBASE  = Basename part of dynamic library. May be just equal BASEEXT.
MAKE = make
FULLEXT = Mojo
BASEEXT = Mojo
PARENT_NAME = 
DLBASE = $(BASEEXT)
VERSION_FROM = lib/Mojo.pm
OBJECT = 
LDFROM = $(OBJECT)
LINKTYPE = dynamic
BOOTDEP = 

# Handy lists of source code files:
XS_FILES = 
C_FILES  = 
O_FILES  = 
H_FILES  = 
MAN1PODS = 
MAN3PODS = lib/Mojo.pm \
	lib/Mojo/Base.pm \
	lib/Mojo/Buffer.pm \
	lib/Mojo/ByteStream.pm \
	lib/Mojo/Client.pm \
	lib/Mojo/Content.pm \
	lib/Mojo/Content/MultiPart.pm \
	lib/Mojo/Cookie.pm \
	lib/Mojo/Cookie/Request.pm \
	lib/Mojo/Cookie/Response.pm \
	lib/Mojo/Date.pm \
	lib/Mojo/File.pm \
	lib/Mojo/File/Memory.pm \
	lib/Mojo/Filter.pm \
	lib/Mojo/Filter/Chunked.pm \
	lib/Mojo/Headers.pm \
	lib/Mojo/HelloWorld.pm \
	lib/Mojo/Home.pm \
	lib/Mojo/Loader.pm \
	lib/Mojo/Manual.pod \
	lib/Mojo/Manual/CodingGuidelines.pod \
	lib/Mojo/Manual/Cookbook.pod \
	lib/Mojo/Manual/FrameworkBuilding.pod \
	lib/Mojo/Manual/GettingStarted.pod \
	lib/Mojo/Manual/HTTPGuide.pod \
	lib/Mojo/Manual/Mojolicious.pod \
	lib/Mojo/Message.pm \
	lib/Mojo/Message/Request.pm \
	lib/Mojo/Message/Response.pm \
	lib/Mojo/Parameters.pm \
	lib/Mojo/Path.pm \
	lib/Mojo/Script.pm \
	lib/Mojo/Script/Cgi.pm \
	lib/Mojo/Script/Daemon.pm \
	lib/Mojo/Script/DaemonPrefork.pm \
	lib/Mojo/Script/Fastcgi.pm \
	lib/Mojo/Script/Generate.pm \
	lib/Mojo/Script/Generate/App.pm \
	lib/Mojo/Script/Test.pm \
	lib/Mojo/Scripts.pm \
	lib/Mojo/Server.pm \
	lib/Mojo/Server/CGI.pm \
	lib/Mojo/Server/Daemon.pm \
	lib/Mojo/Server/Daemon/Prefork.pm \
	lib/Mojo/Server/FastCGI.pm \
	lib/Mojo/Stateful.pm \
	lib/Mojo/Template.pm \
	lib/Mojo/Transaction.pm \
	lib/Mojo/URL.pm \
	lib/Mojo/Upload.pm \
	lib/MojoX/Dispatcher/Routes.pm \
	lib/MojoX/Dispatcher/Routes/Context.pm \
	lib/MojoX/Dispatcher/Routes/Controller.pm \
	lib/MojoX/Dispatcher/Static.pm \
	lib/MojoX/Renderer.pm \
	lib/MojoX/Routes.pm \
	lib/MojoX/Routes/Match.pm \
	lib/MojoX/Routes/Pattern.pm \
	lib/MojoX/Types.pm \
	lib/Mojolicious.pm \
	lib/Mojolicious/Context.pm \
	lib/Mojolicious/Controller.pm \
	lib/Mojolicious/Dispatcher.pm \
	lib/Mojolicious/Renderer.pm \
	lib/Mojolicious/Script/Daemon.pm \
	lib/Mojolicious/Script/Generate.pm \
	lib/Mojolicious/Script/Generate/App.pm \
	lib/Mojolicious/Script/Mojo.pm \
	lib/Mojolicious/Script/Test.pm \
	lib/Mojolicious/Scripts.pm \
	lib/Test/Mojo/Server.pm

# Where is the Config information that we are using/depend on
CONFIGDEP = $(PERL_ARCHLIB)$(DFSEP)Config.pm $(PERL_INC)$(DFSEP)config.h

# Where to build things
INST_LIBDIR      = $(INST_LIB)
INST_ARCHLIBDIR  = $(INST_ARCHLIB)

INST_AUTODIR     = $(INST_LIB)/auto/$(FULLEXT)
INST_ARCHAUTODIR = $(INST_ARCHLIB)/auto/$(FULLEXT)

INST_STATIC      = 
INST_DYNAMIC     = 
INST_BOOT        = 

# Extra linker info
EXPORT_LIST        = 
PERL_ARCHIVE       = 
PERL_ARCHIVE_AFTER = 


TO_INST_PM = lib/Mojo.pm \
	lib/Mojo/Base.pm \
	lib/Mojo/Buffer.pm \
	lib/Mojo/ByteStream.pm \
	lib/Mojo/Client.pm \
	lib/Mojo/Content.pm \
	lib/Mojo/Content/MultiPart.pm \
	lib/Mojo/Cookie.pm \
	lib/Mojo/Cookie/Request.pm \
	lib/Mojo/Cookie/Response.pm \
	lib/Mojo/Date.pm \
	lib/Mojo/File.pm \
	lib/Mojo/File/Memory.pm \
	lib/Mojo/Filter.pm \
	lib/Mojo/Filter/Chunked.pm \
	lib/Mojo/Headers.pm \
	lib/Mojo/HelloWorld.pm \
	lib/Mojo/Home.pm \
	lib/Mojo/Loader.pm \
	lib/Mojo/Manual.pod \
	lib/Mojo/Manual/CodingGuidelines.pod \
	lib/Mojo/Manual/Cookbook.pod \
	lib/Mojo/Manual/FrameworkBuilding.pod \
	lib/Mojo/Manual/GettingStarted.pod \
	lib/Mojo/Manual/HTTPGuide.pod \
	lib/Mojo/Manual/Mojolicious.pod \
	lib/Mojo/Message.pm \
	lib/Mojo/Message/Request.pm \
	lib/Mojo/Message/Response.pm \
	lib/Mojo/Parameters.pm \
	lib/Mojo/Path.pm \
	lib/Mojo/Script.pm \
	lib/Mojo/Script/Cgi.pm \
	lib/Mojo/Script/Daemon.pm \
	lib/Mojo/Script/DaemonPrefork.pm \
	lib/Mojo/Script/Fastcgi.pm \
	lib/Mojo/Script/Generate.pm \
	lib/Mojo/Script/Generate/App.pm \
	lib/Mojo/Script/Test.pm \
	lib/Mojo/Scripts.pm \
	lib/Mojo/Server.pm \
	lib/Mojo/Server/CGI.pm \
	lib/Mojo/Server/Daemon.pm \
	lib/Mojo/Server/Daemon/Prefork.pm \
	lib/Mojo/Server/FastCGI.pm \
	lib/Mojo/Stateful.pm \
	lib/Mojo/Template.pm \
	lib/Mojo/Transaction.pm \
	lib/Mojo/URL.pm \
	lib/Mojo/Upload.pm \
	lib/MojoX/Dispatcher/Routes.pm \
	lib/MojoX/Dispatcher/Routes/Context.pm \
	lib/MojoX/Dispatcher/Routes/Controller.pm \
	lib/MojoX/Dispatcher/Static.pm \
	lib/MojoX/Renderer.pm \
	lib/MojoX/Routes.pm \
	lib/MojoX/Routes/Match.pm \
	lib/MojoX/Routes/Pattern.pm \
	lib/MojoX/Types.pm \
	lib/Mojolicious.pm \
	lib/Mojolicious/Context.pm \
	lib/Mojolicious/Controller.pm \
	lib/Mojolicious/Dispatcher.pm \
	lib/Mojolicious/Renderer.pm \
	lib/Mojolicious/Script/Daemon.pm \
	lib/Mojolicious/Script/Generate.pm \
	lib/Mojolicious/Script/Generate/App.pm \
	lib/Mojolicious/Script/Mojo.pm \
	lib/Mojolicious/Script/Test.pm \
	lib/Mojolicious/Scripts.pm \
	lib/Test/Mojo/Server.pm

PM_TO_BLIB = lib/MojoX/Routes/Pattern.pm \
	blib/lib/MojoX/Routes/Pattern.pm \
	lib/Mojo/Template.pm \
	blib/lib/Mojo/Template.pm \
	lib/Mojolicious/Script/Generate/App.pm \
	blib/lib/Mojolicious/Script/Generate/App.pm \
	lib/Mojo/ByteStream.pm \
	blib/lib/Mojo/ByteStream.pm \
	lib/Mojo/Script/Fastcgi.pm \
	blib/lib/Mojo/Script/Fastcgi.pm \
	lib/Mojo/Manual/HTTPGuide.pod \
	blib/lib/Mojo/Manual/HTTPGuide.pod \
	lib/Mojo/Stateful.pm \
	blib/lib/Mojo/Stateful.pm \
	lib/Mojolicious/Script/Mojo.pm \
	blib/lib/Mojolicious/Script/Mojo.pm \
	lib/Mojo/Transaction.pm \
	blib/lib/Mojo/Transaction.pm \
	lib/Mojo/Filter.pm \
	blib/lib/Mojo/Filter.pm \
	lib/Mojo/Manual/CodingGuidelines.pod \
	blib/lib/Mojo/Manual/CodingGuidelines.pod \
	lib/Mojo/Cookie/Response.pm \
	blib/lib/Mojo/Cookie/Response.pm \
	lib/Mojo/Manual/Cookbook.pod \
	blib/lib/Mojo/Manual/Cookbook.pod \
	lib/MojoX/Routes.pm \
	blib/lib/MojoX/Routes.pm \
	lib/MojoX/Routes/Match.pm \
	blib/lib/MojoX/Routes/Match.pm \
	lib/Mojo/Cookie.pm \
	blib/lib/Mojo/Cookie.pm \
	lib/MojoX/Dispatcher/Routes/Context.pm \
	blib/lib/MojoX/Dispatcher/Routes/Context.pm \
	lib/Test/Mojo/Server.pm \
	blib/lib/Test/Mojo/Server.pm \
	lib/Mojo/Server.pm \
	blib/lib/Mojo/Server.pm \
	lib/Mojo/Path.pm \
	blib/lib/Mojo/Path.pm \
	lib/Mojolicious/Script/Daemon.pm \
	blib/lib/Mojolicious/Script/Daemon.pm \
	lib/Mojo/Date.pm \
	blib/lib/Mojo/Date.pm \
	lib/Mojo/File.pm \
	blib/lib/Mojo/File.pm \
	lib/Mojo/Upload.pm \
	blib/lib/Mojo/Upload.pm \
	lib/Mojo/Buffer.pm \
	blib/lib/Mojo/Buffer.pm \
	lib/Mojo/Scripts.pm \
	blib/lib/Mojo/Scripts.pm \
	lib/Mojo/HelloWorld.pm \
	blib/lib/Mojo/HelloWorld.pm \
	lib/Mojo/Script/Generate/App.pm \
	blib/lib/Mojo/Script/Generate/App.pm \
	lib/Mojo/Script/Daemon.pm \
	blib/lib/Mojo/Script/Daemon.pm \
	lib/Mojo/Server/CGI.pm \
	blib/lib/Mojo/Server/CGI.pm \
	lib/MojoX/Types.pm \
	blib/lib/MojoX/Types.pm \
	lib/MojoX/Renderer.pm \
	blib/lib/MojoX/Renderer.pm \
	lib/Mojo/Message.pm \
	blib/lib/Mojo/Message.pm \
	lib/Mojolicious/Renderer.pm \
	blib/lib/Mojolicious/Renderer.pm \
	lib/Mojolicious/Context.pm \
	blib/lib/Mojolicious/Context.pm \
	lib/Mojo/File/Memory.pm \
	blib/lib/Mojo/File/Memory.pm \
	lib/MojoX/Dispatcher/Routes.pm \
	blib/lib/MojoX/Dispatcher/Routes.pm \
	lib/Mojo/Server/FastCGI.pm \
	blib/lib/Mojo/Server/FastCGI.pm \
	lib/Mojolicious/Dispatcher.pm \
	blib/lib/Mojolicious/Dispatcher.pm \
	lib/Mojo/Script/Test.pm \
	blib/lib/Mojo/Script/Test.pm \
	lib/Mojo/Base.pm \
	blib/lib/Mojo/Base.pm \
	lib/Mojo/Cookie/Request.pm \
	blib/lib/Mojo/Cookie/Request.pm \
	lib/Mojo/Script.pm \
	blib/lib/Mojo/Script.pm \
	lib/Mojo/Content.pm \
	blib/lib/Mojo/Content.pm \
	lib/Mojo/Loader.pm \
	blib/lib/Mojo/Loader.pm \
	lib/Mojo/Content/MultiPart.pm \
	blib/lib/Mojo/Content/MultiPart.pm \
	lib/Mojo/Manual.pod \
	blib/lib/Mojo/Manual.pod \
	lib/Mojo/Manual/FrameworkBuilding.pod \
	blib/lib/Mojo/Manual/FrameworkBuilding.pod \
	lib/Mojo/Message/Response.pm \
	blib/lib/Mojo/Message/Response.pm \
	lib/Mojolicious.pm \
	blib/lib/Mojolicious.pm \
	lib/Mojo/Filter/Chunked.pm \
	blib/lib/Mojo/Filter/Chunked.pm \
	lib/Mojo/Home.pm \
	blib/lib/Mojo/Home.pm \
	lib/Mojo/Script/DaemonPrefork.pm \
	blib/lib/Mojo/Script/DaemonPrefork.pm \
	lib/Mojolicious/Controller.pm \
	blib/lib/Mojolicious/Controller.pm \
	lib/Mojolicious/Scripts.pm \
	blib/lib/Mojolicious/Scripts.pm \
	lib/Mojo/Server/Daemon.pm \
	blib/lib/Mojo/Server/Daemon.pm \
	lib/Mojo/Script/Cgi.pm \
	blib/lib/Mojo/Script/Cgi.pm \
	lib/Mojo/URL.pm \
	blib/lib/Mojo/URL.pm \
	lib/Mojolicious/Script/Test.pm \
	blib/lib/Mojolicious/Script/Test.pm \
	lib/Mojo.pm \
	blib/lib/Mojo.pm \
	lib/MojoX/Dispatcher/Routes/Controller.pm \
	blib/lib/MojoX/Dispatcher/Routes/Controller.pm \
	lib/Mojo/Message/Request.pm \
	blib/lib/Mojo/Message/Request.pm \
	lib/Mojo/Script/Generate.pm \
	blib/lib/Mojo/Script/Generate.pm \
	lib/Mojo/Server/Daemon/Prefork.pm \
	blib/lib/Mojo/Server/Daemon/Prefork.pm \
	lib/Mojo/Headers.pm \
	blib/lib/Mojo/Headers.pm \
	lib/Mojo/Client.pm \
	blib/lib/Mojo/Client.pm \
	lib/Mojolicious/Script/Generate.pm \
	blib/lib/Mojolicious/Script/Generate.pm \
	lib/Mojo/Manual/Mojolicious.pod \
	blib/lib/Mojo/Manual/Mojolicious.pod \
	lib/MojoX/Dispatcher/Static.pm \
	blib/lib/MojoX/Dispatcher/Static.pm \
	lib/Mojo/Manual/GettingStarted.pod \
	blib/lib/Mojo/Manual/GettingStarted.pod \
	lib/Mojo/Parameters.pm \
	blib/lib/Mojo/Parameters.pm


# --- MakeMaker platform_constants section:
MM_Unix_VERSION = 6.42
PERL_MALLOC_DEF = -DPERL_EXTMALLOC_DEF -Dmalloc=Perl_malloc -Dfree=Perl_mfree -Drealloc=Perl_realloc -Dcalloc=Perl_calloc


# --- MakeMaker tool_autosplit section:
# Usage: $(AUTOSPLITFILE) FileToSplit AutoDirToSplitInto
AUTOSPLITFILE = $(ABSPERLRUN)  -e 'use AutoSplit;  autosplit($$ARGV[0], $$ARGV[1], 0, 1, 1)' --



# --- MakeMaker tool_xsubpp section:


# --- MakeMaker tools_other section:
SHELL = /bin/sh
CHMOD = chmod
CP = cp
MV = mv
NOOP = $(SHELL) -c true
NOECHO = @
RM_F = rm -f
RM_RF = rm -rf
TEST_F = test -f
TOUCH = touch
UMASK_NULL = umask 0
DEV_NULL = > /dev/null 2>&1
MKPATH = $(ABSPERLRUN) "-MExtUtils::Command" -e mkpath
EQUALIZE_TIMESTAMP = $(ABSPERLRUN) "-MExtUtils::Command" -e eqtime
ECHO = echo
ECHO_N = echo -n
UNINST = 0
VERBINST = 0
MOD_INSTALL = $(ABSPERLRUN) -MExtUtils::Install -e 'install({@ARGV}, '\''$(VERBINST)'\'', 0, '\''$(UNINST)'\'');' --
DOC_INSTALL = $(ABSPERLRUN) "-MExtUtils::Command::MM" -e perllocal_install
UNINSTALL = $(ABSPERLRUN) "-MExtUtils::Command::MM" -e uninstall
WARN_IF_OLD_PACKLIST = $(ABSPERLRUN) "-MExtUtils::Command::MM" -e warn_if_old_packlist
MACROSTART = 
MACROEND = 
USEMAKEFILE = -f
FIXIN = $(PERLRUN) "-MExtUtils::MY" -e "MY->fixin(shift)"


# --- MakeMaker makemakerdflt section:
makemakerdflt : all
	$(NOECHO) $(NOOP)


# --- MakeMaker dist section:
TAR = tar
TARFLAGS = cvf
ZIP = zip
ZIPFLAGS = -r
COMPRESS = gzip --best
SUFFIX = .gz
SHAR = shar
PREOP = $(NOECHO) $(NOOP)
POSTOP = $(NOECHO) $(NOOP)
TO_UNIX = $(NOECHO) $(NOOP)
CI = ci -u
RCS_LABEL = rcs -Nv$(VERSION_SYM): -q
DIST_CP = best
DIST_DEFAULT = tardist
DISTNAME = Mojo
DISTVNAME = Mojo-0.8


# --- MakeMaker macro section:


# --- MakeMaker depend section:


# --- MakeMaker cflags section:


# --- MakeMaker const_loadlibs section:


# --- MakeMaker const_cccmd section:


# --- MakeMaker post_constants section:


# --- MakeMaker pasthru section:

PASTHRU = LIBPERL_A="$(LIBPERL_A)"\
	LINKTYPE="$(LINKTYPE)"\
	PREFIX="$(PREFIX)"


# --- MakeMaker special_targets section:
.SUFFIXES : .xs .c .C .cpp .i .s .cxx .cc $(OBJ_EXT)

.PHONY: all config static dynamic test linkext manifest blibdirs clean realclean disttest distdir



# --- MakeMaker c_o section:


# --- MakeMaker xs_c section:


# --- MakeMaker xs_o section:


# --- MakeMaker top_targets section:
all :: pure_all manifypods
	$(NOECHO) $(NOOP)


pure_all :: config pm_to_blib subdirs linkext
	$(NOECHO) $(NOOP)

subdirs :: $(MYEXTLIB)
	$(NOECHO) $(NOOP)

config :: $(FIRST_MAKEFILE) blibdirs
	$(NOECHO) $(NOOP)

help :
	perldoc ExtUtils::MakeMaker


# --- MakeMaker blibdirs section:
blibdirs : $(INST_LIBDIR)$(DFSEP).exists $(INST_ARCHLIB)$(DFSEP).exists $(INST_AUTODIR)$(DFSEP).exists $(INST_ARCHAUTODIR)$(DFSEP).exists $(INST_BIN)$(DFSEP).exists $(INST_SCRIPT)$(DFSEP).exists $(INST_MAN1DIR)$(DFSEP).exists $(INST_MAN3DIR)$(DFSEP).exists
	$(NOECHO) $(NOOP)

# Backwards compat with 6.18 through 6.25
blibdirs.ts : blibdirs
	$(NOECHO) $(NOOP)

$(INST_LIBDIR)$(DFSEP).exists :: Makefile.PL
	$(NOECHO) $(MKPATH) $(INST_LIBDIR)
	$(NOECHO) $(CHMOD) 755 $(INST_LIBDIR)
	$(NOECHO) $(TOUCH) $(INST_LIBDIR)$(DFSEP).exists

$(INST_ARCHLIB)$(DFSEP).exists :: Makefile.PL
	$(NOECHO) $(MKPATH) $(INST_ARCHLIB)
	$(NOECHO) $(CHMOD) 755 $(INST_ARCHLIB)
	$(NOECHO) $(TOUCH) $(INST_ARCHLIB)$(DFSEP).exists

$(INST_AUTODIR)$(DFSEP).exists :: Makefile.PL
	$(NOECHO) $(MKPATH) $(INST_AUTODIR)
	$(NOECHO) $(CHMOD) 755 $(INST_AUTODIR)
	$(NOECHO) $(TOUCH) $(INST_AUTODIR)$(DFSEP).exists

$(INST_ARCHAUTODIR)$(DFSEP).exists :: Makefile.PL
	$(NOECHO) $(MKPATH) $(INST_ARCHAUTODIR)
	$(NOECHO) $(CHMOD) 755 $(INST_ARCHAUTODIR)
	$(NOECHO) $(TOUCH) $(INST_ARCHAUTODIR)$(DFSEP).exists

$(INST_BIN)$(DFSEP).exists :: Makefile.PL
	$(NOECHO) $(MKPATH) $(INST_BIN)
	$(NOECHO) $(CHMOD) 755 $(INST_BIN)
	$(NOECHO) $(TOUCH) $(INST_BIN)$(DFSEP).exists

$(INST_SCRIPT)$(DFSEP).exists :: Makefile.PL
	$(NOECHO) $(MKPATH) $(INST_SCRIPT)
	$(NOECHO) $(CHMOD) 755 $(INST_SCRIPT)
	$(NOECHO) $(TOUCH) $(INST_SCRIPT)$(DFSEP).exists

$(INST_MAN1DIR)$(DFSEP).exists :: Makefile.PL
	$(NOECHO) $(MKPATH) $(INST_MAN1DIR)
	$(NOECHO) $(CHMOD) 755 $(INST_MAN1DIR)
	$(NOECHO) $(TOUCH) $(INST_MAN1DIR)$(DFSEP).exists

$(INST_MAN3DIR)$(DFSEP).exists :: Makefile.PL
	$(NOECHO) $(MKPATH) $(INST_MAN3DIR)
	$(NOECHO) $(CHMOD) 755 $(INST_MAN3DIR)
	$(NOECHO) $(TOUCH) $(INST_MAN3DIR)$(DFSEP).exists



# --- MakeMaker linkext section:

linkext :: $(LINKTYPE)
	$(NOECHO) $(NOOP)


# --- MakeMaker dlsyms section:


# --- MakeMaker dynamic section:

dynamic :: $(FIRST_MAKEFILE) $(INST_DYNAMIC) $(INST_BOOT)
	$(NOECHO) $(NOOP)


# --- MakeMaker dynamic_bs section:

BOOTSTRAP =


# --- MakeMaker dynamic_lib section:


# --- MakeMaker static section:

## $(INST_PM) has been moved to the all: target.
## It remains here for awhile to allow for old usage: "make static"
static :: $(FIRST_MAKEFILE) $(INST_STATIC)
	$(NOECHO) $(NOOP)


# --- MakeMaker static_lib section:


# --- MakeMaker manifypods section:

POD2MAN_EXE = $(PERLRUN) "-MExtUtils::Command::MM" -e pod2man "--"
POD2MAN = $(POD2MAN_EXE)


manifypods : pure_all  \
	lib/MojoX/Routes/Pattern.pm \
	lib/Mojo/Template.pm \
	lib/Mojolicious/Script/Generate/App.pm \
	lib/Mojo/ByteStream.pm \
	lib/Mojo/Script/Fastcgi.pm \
	lib/Mojo/Manual/HTTPGuide.pod \
	lib/Mojo/Stateful.pm \
	lib/Mojolicious/Script/Mojo.pm \
	lib/Mojo/Transaction.pm \
	lib/Mojo/Filter.pm \
	lib/Mojo/Manual/CodingGuidelines.pod \
	lib/Mojo/Cookie/Response.pm \
	lib/Mojo/Manual/Cookbook.pod \
	lib/MojoX/Routes.pm \
	lib/MojoX/Routes/Match.pm \
	lib/Mojo/Cookie.pm \
	lib/MojoX/Dispatcher/Routes/Context.pm \
	lib/Test/Mojo/Server.pm \
	lib/Mojo/Server.pm \
	lib/Mojo/Path.pm \
	lib/Mojolicious/Script/Daemon.pm \
	lib/Mojo/Date.pm \
	lib/Mojo/File.pm \
	lib/Mojo/Upload.pm \
	lib/Mojo/Buffer.pm \
	lib/Mojo/Scripts.pm \
	lib/Mojo/HelloWorld.pm \
	lib/Mojo/Script/Generate/App.pm \
	lib/Mojo/Script/Daemon.pm \
	lib/Mojo/Server/CGI.pm \
	lib/MojoX/Types.pm \
	lib/MojoX/Renderer.pm \
	lib/Mojo/Message.pm \
	lib/Mojolicious/Renderer.pm \
	lib/Mojolicious/Context.pm \
	lib/Mojo/File/Memory.pm \
	lib/MojoX/Dispatcher/Routes.pm \
	lib/Mojo/Server/FastCGI.pm \
	lib/Mojolicious/Dispatcher.pm \
	lib/Mojo/Script/Test.pm \
	lib/Mojo/Base.pm \
	lib/Mojo/Cookie/Request.pm \
	lib/Mojo/Script.pm \
	lib/Mojo/Content.pm \
	lib/Mojo/Loader.pm \
	lib/Mojo/Content/MultiPart.pm \
	lib/Mojo/Manual.pod \
	lib/Mojo/Manual/FrameworkBuilding.pod \
	lib/Mojo/Message/Response.pm \
	lib/Mojolicious.pm \
	lib/Mojo/Filter/Chunked.pm \
	lib/Mojo/Home.pm \
	lib/Mojo/Script/DaemonPrefork.pm \
	lib/Mojolicious/Controller.pm \
	lib/Mojolicious/Scripts.pm \
	lib/Mojo/Server/Daemon.pm \
	lib/Mojo/Script/Cgi.pm \
	lib/Mojo/URL.pm \
	lib/Mojolicious/Script/Test.pm \
	lib/Mojo.pm \
	lib/MojoX/Dispatcher/Routes/Controller.pm \
	lib/Mojo/Message/Request.pm \
	lib/Mojo/Script/Generate.pm \
	lib/Mojo/Server/Daemon/Prefork.pm \
	lib/Mojo/Headers.pm \
	lib/Mojo/Client.pm \
	lib/Mojolicious/Script/Generate.pm \
	lib/Mojo/Manual/Mojolicious.pod \
	lib/MojoX/Dispatcher/Static.pm \
	lib/Mojo/Manual/GettingStarted.pod \
	lib/Mojo/Parameters.pm
	$(NOECHO) $(POD2MAN) --section=3 --perm_rw=$(PERM_RW) \
	  lib/MojoX/Routes/Pattern.pm $(INST_MAN3DIR)/MojoX::Routes::Pattern.$(MAN3EXT) \
	  lib/Mojo/Template.pm $(INST_MAN3DIR)/Mojo::Template.$(MAN3EXT) \
	  lib/Mojolicious/Script/Generate/App.pm $(INST_MAN3DIR)/Mojolicious::Script::Generate::App.$(MAN3EXT) \
	  lib/Mojo/ByteStream.pm $(INST_MAN3DIR)/Mojo::ByteStream.$(MAN3EXT) \
	  lib/Mojo/Script/Fastcgi.pm $(INST_MAN3DIR)/Mojo::Script::Fastcgi.$(MAN3EXT) \
	  lib/Mojo/Manual/HTTPGuide.pod $(INST_MAN3DIR)/Mojo::Manual::HTTPGuide.$(MAN3EXT) \
	  lib/Mojo/Stateful.pm $(INST_MAN3DIR)/Mojo::Stateful.$(MAN3EXT) \
	  lib/Mojolicious/Script/Mojo.pm $(INST_MAN3DIR)/Mojolicious::Script::Mojo.$(MAN3EXT) \
	  lib/Mojo/Transaction.pm $(INST_MAN3DIR)/Mojo::Transaction.$(MAN3EXT) \
	  lib/Mojo/Filter.pm $(INST_MAN3DIR)/Mojo::Filter.$(MAN3EXT) \
	  lib/Mojo/Manual/CodingGuidelines.pod $(INST_MAN3DIR)/Mojo::Manual::CodingGuidelines.$(MAN3EXT) \
	  lib/Mojo/Cookie/Response.pm $(INST_MAN3DIR)/Mojo::Cookie::Response.$(MAN3EXT) \
	  lib/Mojo/Manual/Cookbook.pod $(INST_MAN3DIR)/Mojo::Manual::Cookbook.$(MAN3EXT) \
	  lib/MojoX/Routes.pm $(INST_MAN3DIR)/MojoX::Routes.$(MAN3EXT) \
	  lib/MojoX/Routes/Match.pm $(INST_MAN3DIR)/MojoX::Routes::Match.$(MAN3EXT) \
	  lib/Mojo/Cookie.pm $(INST_MAN3DIR)/Mojo::Cookie.$(MAN3EXT) \
	  lib/MojoX/Dispatcher/Routes/Context.pm $(INST_MAN3DIR)/MojoX::Dispatcher::Routes::Context.$(MAN3EXT) \
	  lib/Test/Mojo/Server.pm $(INST_MAN3DIR)/Test::Mojo::Server.$(MAN3EXT) \
	  lib/Mojo/Server.pm $(INST_MAN3DIR)/Mojo::Server.$(MAN3EXT) \
	  lib/Mojo/Path.pm $(INST_MAN3DIR)/Mojo::Path.$(MAN3EXT) \
	  lib/Mojolicious/Script/Daemon.pm $(INST_MAN3DIR)/Mojolicious::Script::Daemon.$(MAN3EXT) \
	  lib/Mojo/Date.pm $(INST_MAN3DIR)/Mojo::Date.$(MAN3EXT) \
	  lib/Mojo/File.pm $(INST_MAN3DIR)/Mojo::File.$(MAN3EXT) \
	  lib/Mojo/Upload.pm $(INST_MAN3DIR)/Mojo::Upload.$(MAN3EXT) \
	  lib/Mojo/Buffer.pm $(INST_MAN3DIR)/Mojo::Buffer.$(MAN3EXT) \
	  lib/Mojo/Scripts.pm $(INST_MAN3DIR)/Mojo::Scripts.$(MAN3EXT) \
	  lib/Mojo/HelloWorld.pm $(INST_MAN3DIR)/Mojo::HelloWorld.$(MAN3EXT) \
	  lib/Mojo/Script/Generate/App.pm $(INST_MAN3DIR)/Mojo::Script::Generate::App.$(MAN3EXT) \
	  lib/Mojo/Script/Daemon.pm $(INST_MAN3DIR)/Mojo::Script::Daemon.$(MAN3EXT) \
	  lib/Mojo/Server/CGI.pm $(INST_MAN3DIR)/Mojo::Server::CGI.$(MAN3EXT) \
	  lib/MojoX/Types.pm $(INST_MAN3DIR)/MojoX::Types.$(MAN3EXT) \
	  lib/MojoX/Renderer.pm $(INST_MAN3DIR)/MojoX::Renderer.$(MAN3EXT) \
	  lib/Mojo/Message.pm $(INST_MAN3DIR)/Mojo::Message.$(MAN3EXT) \
	  lib/Mojolicious/Renderer.pm $(INST_MAN3DIR)/Mojolicious::Renderer.$(MAN3EXT) \
	  lib/Mojolicious/Context.pm $(INST_MAN3DIR)/Mojolicious::Context.$(MAN3EXT) \
	  lib/Mojo/File/Memory.pm $(INST_MAN3DIR)/Mojo::File::Memory.$(MAN3EXT) \
	  lib/MojoX/Dispatcher/Routes.pm $(INST_MAN3DIR)/MojoX::Dispatcher::Routes.$(MAN3EXT) \
	  lib/Mojo/Server/FastCGI.pm $(INST_MAN3DIR)/Mojo::Server::FastCGI.$(MAN3EXT) \
	  lib/Mojolicious/Dispatcher.pm $(INST_MAN3DIR)/Mojolicious::Dispatcher.$(MAN3EXT) \
	  lib/Mojo/Script/Test.pm $(INST_MAN3DIR)/Mojo::Script::Test.$(MAN3EXT) \
	  lib/Mojo/Base.pm $(INST_MAN3DIR)/Mojo::Base.$(MAN3EXT) \
	  lib/Mojo/Cookie/Request.pm $(INST_MAN3DIR)/Mojo::Cookie::Request.$(MAN3EXT) \
	  lib/Mojo/Script.pm $(INST_MAN3DIR)/Mojo::Script.$(MAN3EXT) \
	  lib/Mojo/Content.pm $(INST_MAN3DIR)/Mojo::Content.$(MAN3EXT) \
	  lib/Mojo/Loader.pm $(INST_MAN3DIR)/Mojo::Loader.$(MAN3EXT) \
	  lib/Mojo/Content/MultiPart.pm $(INST_MAN3DIR)/Mojo::Content::MultiPart.$(MAN3EXT) \
	  lib/Mojo/Manual.pod $(INST_MAN3DIR)/Mojo::Manual.$(MAN3EXT) \
	  lib/Mojo/Manual/FrameworkBuilding.pod $(INST_MAN3DIR)/Mojo::Manual::FrameworkBuilding.$(MAN3EXT) \
	  lib/Mojo/Message/Response.pm $(INST_MAN3DIR)/Mojo::Message::Response.$(MAN3EXT) \
	  lib/Mojolicious.pm $(INST_MAN3DIR)/Mojolicious.$(MAN3EXT) \
	  lib/Mojo/Filter/Chunked.pm $(INST_MAN3DIR)/Mojo::Filter::Chunked.$(MAN3EXT) \
	  lib/Mojo/Home.pm $(INST_MAN3DIR)/Mojo::Home.$(MAN3EXT) \
	  lib/Mojo/Script/DaemonPrefork.pm $(INST_MAN3DIR)/Mojo::Script::DaemonPrefork.$(MAN3EXT) \
	  lib/Mojolicious/Controller.pm $(INST_MAN3DIR)/Mojolicious::Controller.$(MAN3EXT) \
	  lib/Mojolicious/Scripts.pm $(INST_MAN3DIR)/Mojolicious::Scripts.$(MAN3EXT) \
	  lib/Mojo/Server/Daemon.pm $(INST_MAN3DIR)/Mojo::Server::Daemon.$(MAN3EXT) \
	  lib/Mojo/Script/Cgi.pm $(INST_MAN3DIR)/Mojo::Script::Cgi.$(MAN3EXT) \
	  lib/Mojo/URL.pm $(INST_MAN3DIR)/Mojo::URL.$(MAN3EXT) \
	  lib/Mojolicious/Script/Test.pm $(INST_MAN3DIR)/Mojolicious::Script::Test.$(MAN3EXT) \
	  lib/Mojo.pm $(INST_MAN3DIR)/Mojo.$(MAN3EXT) \
	  lib/MojoX/Dispatcher/Routes/Controller.pm $(INST_MAN3DIR)/MojoX::Dispatcher::Routes::Controller.$(MAN3EXT) \
	  lib/Mojo/Message/Request.pm $(INST_MAN3DIR)/Mojo::Message::Request.$(MAN3EXT) \
	  lib/Mojo/Script/Generate.pm $(INST_MAN3DIR)/Mojo::Script::Generate.$(MAN3EXT) \
	  lib/Mojo/Server/Daemon/Prefork.pm $(INST_MAN3DIR)/Mojo::Server::Daemon::Prefork.$(MAN3EXT) \
	  lib/Mojo/Headers.pm $(INST_MAN3DIR)/Mojo::Headers.$(MAN3EXT) \
	  lib/Mojo/Client.pm $(INST_MAN3DIR)/Mojo::Client.$(MAN3EXT) \
	  lib/Mojolicious/Script/Generate.pm $(INST_MAN3DIR)/Mojolicious::Script::Generate.$(MAN3EXT) \
	  lib/Mojo/Manual/Mojolicious.pod $(INST_MAN3DIR)/Mojo::Manual::Mojolicious.$(MAN3EXT) \
	  lib/MojoX/Dispatcher/Static.pm $(INST_MAN3DIR)/MojoX::Dispatcher::Static.$(MAN3EXT) \
	  lib/Mojo/Manual/GettingStarted.pod $(INST_MAN3DIR)/Mojo::Manual::GettingStarted.$(MAN3EXT) \
	  lib/Mojo/Parameters.pm $(INST_MAN3DIR)/Mojo::Parameters.$(MAN3EXT) 




# --- MakeMaker processPL section:


# --- MakeMaker installbin section:

EXE_FILES = bin/mojo bin/mojolicious

pure_all :: $(INST_SCRIPT)/mojo $(INST_SCRIPT)/mojolicious
	$(NOECHO) $(NOOP)

realclean ::
	$(RM_F) \
	  $(INST_SCRIPT)/mojo $(INST_SCRIPT)/mojolicious 

$(INST_SCRIPT)/mojo : bin/mojo $(FIRST_MAKEFILE) $(INST_SCRIPT)$(DFSEP).exists $(INST_BIN)$(DFSEP).exists
	$(NOECHO) $(RM_F) $(INST_SCRIPT)/mojo
	$(CP) bin/mojo $(INST_SCRIPT)/mojo
	$(FIXIN) $(INST_SCRIPT)/mojo
	-$(NOECHO) $(CHMOD) $(PERM_RWX) $(INST_SCRIPT)/mojo

$(INST_SCRIPT)/mojolicious : bin/mojolicious $(FIRST_MAKEFILE) $(INST_SCRIPT)$(DFSEP).exists $(INST_BIN)$(DFSEP).exists
	$(NOECHO) $(RM_F) $(INST_SCRIPT)/mojolicious
	$(CP) bin/mojolicious $(INST_SCRIPT)/mojolicious
	$(FIXIN) $(INST_SCRIPT)/mojolicious
	-$(NOECHO) $(CHMOD) $(PERM_RWX) $(INST_SCRIPT)/mojolicious



# --- MakeMaker subdirs section:

# none

# --- MakeMaker clean_subdirs section:
clean_subdirs :
	$(NOECHO) $(NOOP)


# --- MakeMaker clean section:

# Delete temporary files but do not touch installed files. We don't delete
# the Makefile here so a later make realclean still has a makefile to use.

clean :: clean_subdirs
	- $(RM_F) \
	  *$(LIB_EXT) core \
	  core.[0-9] $(INST_ARCHAUTODIR)/extralibs.all \
	  core.[0-9][0-9] $(BASEEXT).bso \
	  pm_to_blib.ts core.[0-9][0-9][0-9][0-9] \
	  $(BASEEXT).x $(BOOTSTRAP) \
	  perl$(EXE_EXT) tmon.out \
	  *$(OBJ_EXT) pm_to_blib \
	  $(INST_ARCHAUTODIR)/extralibs.ld blibdirs.ts \
	  core.[0-9][0-9][0-9][0-9][0-9] *perl.core \
	  core.*perl.*.? $(MAKE_APERL_FILE) \
	  perl $(BASEEXT).def \
	  core.[0-9][0-9][0-9] mon.out \
	  lib$(BASEEXT).def perlmain.c \
	  perl.exe so_locations \
	  $(BASEEXT).exp 
	- $(RM_RF) \
	  blib 
	- $(MV) $(FIRST_MAKEFILE) $(MAKEFILE_OLD) $(DEV_NULL)


# --- MakeMaker realclean_subdirs section:
realclean_subdirs :
	$(NOECHO) $(NOOP)


# --- MakeMaker realclean section:
# Delete temporary files (via clean) and also delete dist files
realclean purge ::  clean realclean_subdirs
	- $(RM_F) \
	  $(MAKEFILE_OLD) $(FIRST_MAKEFILE) 
	- $(RM_RF) \
	  $(DISTVNAME) 


# --- MakeMaker metafile section:
metafile : create_distdir
	$(NOECHO) $(ECHO) Generating META.yml
	$(NOECHO) $(ECHO) '--- #YAML:1.0' > META_new.yml
	$(NOECHO) $(ECHO) 'name:                Mojo' >> META_new.yml
	$(NOECHO) $(ECHO) 'version:             0.8' >> META_new.yml
	$(NOECHO) $(ECHO) 'abstract:            ~' >> META_new.yml
	$(NOECHO) $(ECHO) 'license:             perl' >> META_new.yml
	$(NOECHO) $(ECHO) 'author:              ' >> META_new.yml
	$(NOECHO) $(ECHO) '    - Sebastian Riedel <sri@cpan.org>' >> META_new.yml
	$(NOECHO) $(ECHO) 'generated_by:        ExtUtils::MakeMaker version 6.42' >> META_new.yml
	$(NOECHO) $(ECHO) 'distribution_type:   module' >> META_new.yml
	$(NOECHO) $(ECHO) 'requires:     ' >> META_new.yml
	$(NOECHO) $(ECHO) '    Carp:                          0' >> META_new.yml
	$(NOECHO) $(ECHO) '    Cwd:                           0' >> META_new.yml
	$(NOECHO) $(ECHO) '    Digest::MD5:                   0' >> META_new.yml
	$(NOECHO) $(ECHO) '    Encode:                        0' >> META_new.yml
	$(NOECHO) $(ECHO) '    File::Basename:                0' >> META_new.yml
	$(NOECHO) $(ECHO) '    File::Copy:                    0' >> META_new.yml
	$(NOECHO) $(ECHO) '    File::Path:                    0' >> META_new.yml
	$(NOECHO) $(ECHO) '    File::Spec:                    0' >> META_new.yml
	$(NOECHO) $(ECHO) '    File::Spec::Functions:         0' >> META_new.yml
	$(NOECHO) $(ECHO) '    File::Temp:                    0' >> META_new.yml
	$(NOECHO) $(ECHO) '    FindBin:                       0' >> META_new.yml
	$(NOECHO) $(ECHO) '    IO::File:                      0' >> META_new.yml
	$(NOECHO) $(ECHO) '    IO::Select:                    0' >> META_new.yml
	$(NOECHO) $(ECHO) '    IO::Socket:                    0' >> META_new.yml
	$(NOECHO) $(ECHO) '    MIME::Base64:                  0' >> META_new.yml
	$(NOECHO) $(ECHO) '    MIME::QuotedPrint:             0' >> META_new.yml
	$(NOECHO) $(ECHO) '    POSIX:                         0' >> META_new.yml
	$(NOECHO) $(ECHO) '    Test::Builder::Module:         0' >> META_new.yml
	$(NOECHO) $(ECHO) '    Test::Harness:                 0' >> META_new.yml
	$(NOECHO) $(ECHO) '    Test::More:                    0' >> META_new.yml
	$(NOECHO) $(ECHO) 'meta-spec:' >> META_new.yml
	$(NOECHO) $(ECHO) '    url:     http://module-build.sourceforge.net/META-spec-v1.3.html' >> META_new.yml
	$(NOECHO) $(ECHO) '    version: 1.3' >> META_new.yml
	-$(NOECHO) $(MV) META_new.yml $(DISTVNAME)/META.yml


# --- MakeMaker signature section:
signature :
	cpansign -s


# --- MakeMaker dist_basics section:
distclean :: realclean distcheck
	$(NOECHO) $(NOOP)

distcheck :
	$(PERLRUN) "-MExtUtils::Manifest=fullcheck" -e fullcheck

skipcheck :
	$(PERLRUN) "-MExtUtils::Manifest=skipcheck" -e skipcheck

manifest :
	$(PERLRUN) "-MExtUtils::Manifest=mkmanifest" -e mkmanifest

veryclean : realclean
	$(RM_F) *~ */*~ *.orig */*.orig *.bak */*.bak *.old */*.old 



# --- MakeMaker dist_core section:

dist : $(DIST_DEFAULT) $(FIRST_MAKEFILE)
	$(NOECHO) $(ABSPERLRUN) -l -e 'print '\''Warning: Makefile possibly out of date with $(VERSION_FROM)'\''' \
	  -e '    if -e '\''$(VERSION_FROM)'\'' and -M '\''$(VERSION_FROM)'\'' < -M '\''$(FIRST_MAKEFILE)'\'';' --

tardist : $(DISTVNAME).tar$(SUFFIX)
	$(NOECHO) $(NOOP)

uutardist : $(DISTVNAME).tar$(SUFFIX)
	uuencode $(DISTVNAME).tar$(SUFFIX) $(DISTVNAME).tar$(SUFFIX) > $(DISTVNAME).tar$(SUFFIX)_uu

$(DISTVNAME).tar$(SUFFIX) : distdir
	$(PREOP)
	$(TO_UNIX)
	$(TAR) $(TARFLAGS) $(DISTVNAME).tar $(DISTVNAME)
	$(RM_RF) $(DISTVNAME)
	$(COMPRESS) $(DISTVNAME).tar
	$(POSTOP)

zipdist : $(DISTVNAME).zip
	$(NOECHO) $(NOOP)

$(DISTVNAME).zip : distdir
	$(PREOP)
	$(ZIP) $(ZIPFLAGS) $(DISTVNAME).zip $(DISTVNAME)
	$(RM_RF) $(DISTVNAME)
	$(POSTOP)

shdist : distdir
	$(PREOP)
	$(SHAR) $(DISTVNAME) > $(DISTVNAME).shar
	$(RM_RF) $(DISTVNAME)
	$(POSTOP)


# --- MakeMaker distdir section:
create_distdir :
	$(RM_RF) $(DISTVNAME)
	$(PERLRUN) "-MExtUtils::Manifest=manicopy,maniread" \
		-e "manicopy(maniread(),'$(DISTVNAME)', '$(DIST_CP)');"

distdir : create_distdir distmeta 
	$(NOECHO) $(NOOP)



# --- MakeMaker dist_test section:
disttest : distdir
	cd $(DISTVNAME) && $(ABSPERLRUN) Makefile.PL 
	cd $(DISTVNAME) && $(MAKE) $(PASTHRU)
	cd $(DISTVNAME) && $(MAKE) test $(PASTHRU)



# --- MakeMaker dist_ci section:

ci :
	$(PERLRUN) "-MExtUtils::Manifest=maniread" \
	  -e "@all = keys %{ maniread() };" \
	  -e "print(qq{Executing $(CI) @all\n}); system(qq{$(CI) @all});" \
	  -e "print(qq{Executing $(RCS_LABEL) ...\n}); system(qq{$(RCS_LABEL) @all});"


# --- MakeMaker distmeta section:
distmeta : create_distdir metafile
	$(NOECHO) cd $(DISTVNAME) && $(ABSPERLRUN) -MExtUtils::Manifest=maniadd -e 'eval { maniadd({q{META.yml} => q{Module meta-data (added by MakeMaker)}}) } ' \
	  -e '    or print "Could not add META.yml to MANIFEST: $${'\''@'\''}\n"' --



# --- MakeMaker distsignature section:
distsignature : create_distdir
	$(NOECHO) cd $(DISTVNAME) && $(ABSPERLRUN) -MExtUtils::Manifest=maniadd -e 'eval { maniadd({q{SIGNATURE} => q{Public-key signature (added by MakeMaker)}}) } ' \
	  -e '    or print "Could not add SIGNATURE to MANIFEST: $${'\''@'\''}\n"' --
	$(NOECHO) cd $(DISTVNAME) && $(TOUCH) SIGNATURE
	cd $(DISTVNAME) && cpansign -s



# --- MakeMaker install section:

install :: all pure_install doc_install
	$(NOECHO) $(NOOP)

install_perl :: all pure_perl_install doc_perl_install
	$(NOECHO) $(NOOP)

install_site :: all pure_site_install doc_site_install
	$(NOECHO) $(NOOP)

install_vendor :: all pure_vendor_install doc_vendor_install
	$(NOECHO) $(NOOP)

pure_install :: pure_$(INSTALLDIRS)_install
	$(NOECHO) $(NOOP)

doc_install :: doc_$(INSTALLDIRS)_install
	$(NOECHO) $(NOOP)

pure__install : pure_site_install
	$(NOECHO) $(ECHO) INSTALLDIRS not defined, defaulting to INSTALLDIRS=site

doc__install : doc_site_install
	$(NOECHO) $(ECHO) INSTALLDIRS not defined, defaulting to INSTALLDIRS=site

pure_perl_install ::
	$(NOECHO) $(MOD_INSTALL) \
		read $(PERL_ARCHLIB)/auto/$(FULLEXT)/.packlist \
		write $(DESTINSTALLARCHLIB)/auto/$(FULLEXT)/.packlist \
		$(INST_LIB) $(DESTINSTALLPRIVLIB) \
		$(INST_ARCHLIB) $(DESTINSTALLARCHLIB) \
		$(INST_BIN) $(DESTINSTALLBIN) \
		$(INST_SCRIPT) $(DESTINSTALLSCRIPT) \
		$(INST_MAN1DIR) $(DESTINSTALLMAN1DIR) \
		$(INST_MAN3DIR) $(DESTINSTALLMAN3DIR)
	$(NOECHO) $(WARN_IF_OLD_PACKLIST) \
		$(SITEARCHEXP)/auto/$(FULLEXT)


pure_site_install ::
	$(NOECHO) $(MOD_INSTALL) \
		read $(SITEARCHEXP)/auto/$(FULLEXT)/.packlist \
		write $(DESTINSTALLSITEARCH)/auto/$(FULLEXT)/.packlist \
		$(INST_LIB) $(DESTINSTALLSITELIB) \
		$(INST_ARCHLIB) $(DESTINSTALLSITEARCH) \
		$(INST_BIN) $(DESTINSTALLSITEBIN) \
		$(INST_SCRIPT) $(DESTINSTALLSITESCRIPT) \
		$(INST_MAN1DIR) $(DESTINSTALLSITEMAN1DIR) \
		$(INST_MAN3DIR) $(DESTINSTALLSITEMAN3DIR)
	$(NOECHO) $(WARN_IF_OLD_PACKLIST) \
		$(PERL_ARCHLIB)/auto/$(FULLEXT)

pure_vendor_install ::
	$(NOECHO) $(MOD_INSTALL) \
		read $(VENDORARCHEXP)/auto/$(FULLEXT)/.packlist \
		write $(DESTINSTALLVENDORARCH)/auto/$(FULLEXT)/.packlist \
		$(INST_LIB) $(DESTINSTALLVENDORLIB) \
		$(INST_ARCHLIB) $(DESTINSTALLVENDORARCH) \
		$(INST_BIN) $(DESTINSTALLVENDORBIN) \
		$(INST_SCRIPT) $(DESTINSTALLVENDORSCRIPT) \
		$(INST_MAN1DIR) $(DESTINSTALLVENDORMAN1DIR) \
		$(INST_MAN3DIR) $(DESTINSTALLVENDORMAN3DIR)

doc_perl_install ::
	$(NOECHO) $(ECHO) Appending installation info to $(DESTINSTALLARCHLIB)/perllocal.pod
	-$(NOECHO) $(MKPATH) $(DESTINSTALLARCHLIB)
	-$(NOECHO) $(DOC_INSTALL) \
		"Module" "$(NAME)" \
		"installed into" "$(INSTALLPRIVLIB)" \
		LINKTYPE "$(LINKTYPE)" \
		VERSION "$(VERSION)" \
		EXE_FILES "$(EXE_FILES)" \
		>> $(DESTINSTALLARCHLIB)/perllocal.pod

doc_site_install ::
	$(NOECHO) $(ECHO) Appending installation info to $(DESTINSTALLARCHLIB)/perllocal.pod
	-$(NOECHO) $(MKPATH) $(DESTINSTALLARCHLIB)
	-$(NOECHO) $(DOC_INSTALL) \
		"Module" "$(NAME)" \
		"installed into" "$(INSTALLSITELIB)" \
		LINKTYPE "$(LINKTYPE)" \
		VERSION "$(VERSION)" \
		EXE_FILES "$(EXE_FILES)" \
		>> $(DESTINSTALLARCHLIB)/perllocal.pod

doc_vendor_install ::
	$(NOECHO) $(ECHO) Appending installation info to $(DESTINSTALLARCHLIB)/perllocal.pod
	-$(NOECHO) $(MKPATH) $(DESTINSTALLARCHLIB)
	-$(NOECHO) $(DOC_INSTALL) \
		"Module" "$(NAME)" \
		"installed into" "$(INSTALLVENDORLIB)" \
		LINKTYPE "$(LINKTYPE)" \
		VERSION "$(VERSION)" \
		EXE_FILES "$(EXE_FILES)" \
		>> $(DESTINSTALLARCHLIB)/perllocal.pod


uninstall :: uninstall_from_$(INSTALLDIRS)dirs
	$(NOECHO) $(NOOP)

uninstall_from_perldirs ::
	$(NOECHO) $(UNINSTALL) $(PERL_ARCHLIB)/auto/$(FULLEXT)/.packlist

uninstall_from_sitedirs ::
	$(NOECHO) $(UNINSTALL) $(SITEARCHEXP)/auto/$(FULLEXT)/.packlist

uninstall_from_vendordirs ::
	$(NOECHO) $(UNINSTALL) $(VENDORARCHEXP)/auto/$(FULLEXT)/.packlist


# --- MakeMaker force section:
# Phony target to force checking subdirectories.
FORCE :
	$(NOECHO) $(NOOP)


# --- MakeMaker perldepend section:


# --- MakeMaker makefile section:
# We take a very conservative approach here, but it's worth it.
# We move Makefile to Makefile.old here to avoid gnu make looping.
$(FIRST_MAKEFILE) : Makefile.PL $(CONFIGDEP)
	$(NOECHO) $(ECHO) "Makefile out-of-date with respect to $?"
	$(NOECHO) $(ECHO) "Cleaning current config before rebuilding Makefile..."
	-$(NOECHO) $(RM_F) $(MAKEFILE_OLD)
	-$(NOECHO) $(MV)   $(FIRST_MAKEFILE) $(MAKEFILE_OLD)
	- $(MAKE) $(USEMAKEFILE) $(MAKEFILE_OLD) clean $(DEV_NULL)
	$(PERLRUN) Makefile.PL 
	$(NOECHO) $(ECHO) "==> Your Makefile has been rebuilt. <=="
	$(NOECHO) $(ECHO) "==> Please rerun the $(MAKE) command.  <=="
	false



# --- MakeMaker staticmake section:

# --- MakeMaker makeaperl section ---
MAP_TARGET    = perl
FULLPERL      = /usr/bin/perl

$(MAP_TARGET) :: static $(MAKE_APERL_FILE)
	$(MAKE) $(USEMAKEFILE) $(MAKE_APERL_FILE) $@

$(MAKE_APERL_FILE) : $(FIRST_MAKEFILE) pm_to_blib
	$(NOECHO) $(ECHO) Writing \"$(MAKE_APERL_FILE)\" for this $(MAP_TARGET)
	$(NOECHO) $(PERLRUNINST) \
		Makefile.PL DIR= \
		MAKEFILE=$(MAKE_APERL_FILE) LINKTYPE=static \
		MAKEAPERL=1 NORECURS=1 CCCDLFLAGS=


# --- MakeMaker test section:

TEST_VERBOSE=0
TEST_TYPE=test_$(LINKTYPE)
TEST_FILE = test.pl
TEST_FILES = t/*.t t/*/*.t t/*/*/*.t
TESTDB_SW = -d

testdb :: testdb_$(LINKTYPE)

test :: $(TEST_TYPE) subdirs-test

subdirs-test ::
	$(NOECHO) $(NOOP)


test_dynamic :: pure_all
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) "-MExtUtils::Command::MM" "-e" "test_harness($(TEST_VERBOSE), '$(INST_LIB)', '$(INST_ARCHLIB)')" $(TEST_FILES)

testdb_dynamic :: pure_all
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) $(TESTDB_SW) "-I$(INST_LIB)" "-I$(INST_ARCHLIB)" $(TEST_FILE)

test_ : test_dynamic

test_static :: test_dynamic
testdb_static :: testdb_dynamic


# --- MakeMaker ppd section:
# Creates a PPD (Perl Package Description) for a binary distribution.
ppd :
	$(NOECHO) $(ECHO) '<SOFTPKG NAME="$(DISTNAME)" VERSION="0,8,0,0">' > $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '    <TITLE>$(DISTNAME)</TITLE>' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '    <ABSTRACT></ABSTRACT>' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '    <AUTHOR>Sebastian Riedel &lt;sri@cpan.org&gt;</AUTHOR>' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '    <IMPLEMENTATION>' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="Carp" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="Cwd" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="Digest-MD5" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="Encode" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="File-Basename" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="File-Copy" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="File-Path" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="File-Spec" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="File-Spec-Functions" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="File-Temp" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="FindBin" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="IO-File" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="IO-Select" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="IO-Socket" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="MIME-Base64" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="MIME-QuotedPrint" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="POSIX" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="Test-Builder-Module" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="Test-Harness" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <DEPENDENCY NAME="Test-More" VERSION="0,0,0,0" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <OS NAME="$(OSNAME)" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <ARCHITECTURE NAME="darwin-2level-5.1" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '        <CODEBASE HREF="" />' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '    </IMPLEMENTATION>' >> $(DISTNAME).ppd
	$(NOECHO) $(ECHO) '</SOFTPKG>' >> $(DISTNAME).ppd


# --- MakeMaker pm_to_blib section:

pm_to_blib : $(TO_INST_PM)
	$(NOECHO) $(ABSPERLRUN) -MExtUtils::Install -e 'pm_to_blib({@ARGV}, '\''$(INST_LIB)/auto'\'', '\''$(PM_FILTER)'\'')' -- \
	  lib/MojoX/Routes/Pattern.pm blib/lib/MojoX/Routes/Pattern.pm \
	  lib/Mojo/Template.pm blib/lib/Mojo/Template.pm \
	  lib/Mojolicious/Script/Generate/App.pm blib/lib/Mojolicious/Script/Generate/App.pm \
	  lib/Mojo/ByteStream.pm blib/lib/Mojo/ByteStream.pm \
	  lib/Mojo/Script/Fastcgi.pm blib/lib/Mojo/Script/Fastcgi.pm \
	  lib/Mojo/Manual/HTTPGuide.pod blib/lib/Mojo/Manual/HTTPGuide.pod \
	  lib/Mojo/Stateful.pm blib/lib/Mojo/Stateful.pm \
	  lib/Mojolicious/Script/Mojo.pm blib/lib/Mojolicious/Script/Mojo.pm \
	  lib/Mojo/Transaction.pm blib/lib/Mojo/Transaction.pm \
	  lib/Mojo/Filter.pm blib/lib/Mojo/Filter.pm \
	  lib/Mojo/Manual/CodingGuidelines.pod blib/lib/Mojo/Manual/CodingGuidelines.pod \
	  lib/Mojo/Cookie/Response.pm blib/lib/Mojo/Cookie/Response.pm \
	  lib/Mojo/Manual/Cookbook.pod blib/lib/Mojo/Manual/Cookbook.pod \
	  lib/MojoX/Routes.pm blib/lib/MojoX/Routes.pm \
	  lib/MojoX/Routes/Match.pm blib/lib/MojoX/Routes/Match.pm \
	  lib/Mojo/Cookie.pm blib/lib/Mojo/Cookie.pm \
	  lib/MojoX/Dispatcher/Routes/Context.pm blib/lib/MojoX/Dispatcher/Routes/Context.pm \
	  lib/Test/Mojo/Server.pm blib/lib/Test/Mojo/Server.pm \
	  lib/Mojo/Server.pm blib/lib/Mojo/Server.pm \
	  lib/Mojo/Path.pm blib/lib/Mojo/Path.pm \
	  lib/Mojolicious/Script/Daemon.pm blib/lib/Mojolicious/Script/Daemon.pm \
	  lib/Mojo/Date.pm blib/lib/Mojo/Date.pm \
	  lib/Mojo/File.pm blib/lib/Mojo/File.pm \
	  lib/Mojo/Upload.pm blib/lib/Mojo/Upload.pm \
	  lib/Mojo/Buffer.pm blib/lib/Mojo/Buffer.pm \
	  lib/Mojo/Scripts.pm blib/lib/Mojo/Scripts.pm \
	  lib/Mojo/HelloWorld.pm blib/lib/Mojo/HelloWorld.pm \
	  lib/Mojo/Script/Generate/App.pm blib/lib/Mojo/Script/Generate/App.pm \
	  lib/Mojo/Script/Daemon.pm blib/lib/Mojo/Script/Daemon.pm \
	  lib/Mojo/Server/CGI.pm blib/lib/Mojo/Server/CGI.pm \
	  lib/MojoX/Types.pm blib/lib/MojoX/Types.pm \
	  lib/MojoX/Renderer.pm blib/lib/MojoX/Renderer.pm \
	  lib/Mojo/Message.pm blib/lib/Mojo/Message.pm \
	  lib/Mojolicious/Renderer.pm blib/lib/Mojolicious/Renderer.pm \
	  lib/Mojolicious/Context.pm blib/lib/Mojolicious/Context.pm \
	  lib/Mojo/File/Memory.pm blib/lib/Mojo/File/Memory.pm \
	  lib/MojoX/Dispatcher/Routes.pm blib/lib/MojoX/Dispatcher/Routes.pm \
	  lib/Mojo/Server/FastCGI.pm blib/lib/Mojo/Server/FastCGI.pm \
	  lib/Mojolicious/Dispatcher.pm blib/lib/Mojolicious/Dispatcher.pm \
	  lib/Mojo/Script/Test.pm blib/lib/Mojo/Script/Test.pm \
	  lib/Mojo/Base.pm blib/lib/Mojo/Base.pm \
	  lib/Mojo/Cookie/Request.pm blib/lib/Mojo/Cookie/Request.pm \
	  lib/Mojo/Script.pm blib/lib/Mojo/Script.pm \
	  lib/Mojo/Content.pm blib/lib/Mojo/Content.pm \
	  lib/Mojo/Loader.pm blib/lib/Mojo/Loader.pm \
	  lib/Mojo/Content/MultiPart.pm blib/lib/Mojo/Content/MultiPart.pm \
	  lib/Mojo/Manual.pod blib/lib/Mojo/Manual.pod \
	  lib/Mojo/Manual/FrameworkBuilding.pod blib/lib/Mojo/Manual/FrameworkBuilding.pod \
	  lib/Mojo/Message/Response.pm blib/lib/Mojo/Message/Response.pm \
	  lib/Mojolicious.pm blib/lib/Mojolicious.pm \
	  lib/Mojo/Filter/Chunked.pm blib/lib/Mojo/Filter/Chunked.pm \
	  lib/Mojo/Home.pm blib/lib/Mojo/Home.pm \
	  lib/Mojo/Script/DaemonPrefork.pm blib/lib/Mojo/Script/DaemonPrefork.pm \
	  lib/Mojolicious/Controller.pm blib/lib/Mojolicious/Controller.pm \
	  lib/Mojolicious/Scripts.pm blib/lib/Mojolicious/Scripts.pm \
	  lib/Mojo/Server/Daemon.pm blib/lib/Mojo/Server/Daemon.pm \
	  lib/Mojo/Script/Cgi.pm blib/lib/Mojo/Script/Cgi.pm \
	  lib/Mojo/URL.pm blib/lib/Mojo/URL.pm \
	  lib/Mojolicious/Script/Test.pm blib/lib/Mojolicious/Script/Test.pm \
	  lib/Mojo.pm blib/lib/Mojo.pm \
	  lib/MojoX/Dispatcher/Routes/Controller.pm blib/lib/MojoX/Dispatcher/Routes/Controller.pm \
	  lib/Mojo/Message/Request.pm blib/lib/Mojo/Message/Request.pm \
	  lib/Mojo/Script/Generate.pm blib/lib/Mojo/Script/Generate.pm \
	  lib/Mojo/Server/Daemon/Prefork.pm blib/lib/Mojo/Server/Daemon/Prefork.pm \
	  lib/Mojo/Headers.pm blib/lib/Mojo/Headers.pm \
	  lib/Mojo/Client.pm blib/lib/Mojo/Client.pm \
	  lib/Mojolicious/Script/Generate.pm blib/lib/Mojolicious/Script/Generate.pm \
	  lib/Mojo/Manual/Mojolicious.pod blib/lib/Mojo/Manual/Mojolicious.pod \
	  lib/MojoX/Dispatcher/Static.pm blib/lib/MojoX/Dispatcher/Static.pm \
	  lib/Mojo/Manual/GettingStarted.pod blib/lib/Mojo/Manual/GettingStarted.pod \
	  lib/Mojo/Parameters.pm blib/lib/Mojo/Parameters.pm 
	$(NOECHO) $(TOUCH) pm_to_blib


# --- MakeMaker selfdocument section:


# --- MakeMaker postamble section:


# End.
