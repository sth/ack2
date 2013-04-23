#!perl

use strict;
use warnings;

use lib 't';
use Util;

use Cwd qw(getcwd realpath);
use File::Spec;
use File::Temp;
use Test::Builder;
use Test::More;

use App::Ack::ConfigFinder;

unless ( File::Temp->can('newdir') ) {
    plan skip_all => q{You need File::Temp->newdir to be able to run this test};
}

my $tmpdir = $ENV{'TMPDIR'};
my $home   = $ENV{'HOME'};

chop $tmpdir if $tmpdir && $tmpdir =~ m{/$};
chop $home   if $home   =~ m{/$};

if ( $tmpdir && $tmpdir =~ /^$home/ ) {
    plan tests => 1;

    fail "Your \$TMPDIR ($tmpdir) is set to a descendant directory of ~; this test is known to fail with such a setting. Please set your TMPDIR to something else to get this test to pass.";
    exit;
}

plan tests => 26;

# Set HOME to a known value, so we get predictable results:
$ENV{'HOME'} = realpath('t/home');

sub touch_ackrc {
    my $filename = shift || '.ackrc';
    write_file( $filename, () );

    return;
}

sub no_home (&) { ## no critic (ProhibitSubroutinePrototypes)
    my ( $fn ) = @_;

    my $home = delete $ENV{'HOME'}; # localized delete isn't supported in
                                    # earlier perls
    $fn->();
    $ENV{'HOME'} = $home; # XXX this won't work on exceptions...

    return;
}

my $finder;

sub expect_ackrcs {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $expected = shift;
    my $name     = shift;

    my @got      = map { realpath($_) } $finder->find_config_files;
    my @expected = map { realpath($_) } @{$expected};
    is_deeply( \@got, \@expected, $name ) or diag(explain(\@got));

    return;
}

my @global_files;

if ( $^O eq 'MSWin32') {
    require Win32;

    @global_files = map { File::Spec->catfile($_, 'ackrc') } (
        Win32::GetFolderPath(Win32::CSIDL_COMMON_APPDATA()),
        Win32::GetFolderPath(Win32::CSIDL_APPDATA()),
    );
}
else {
    @global_files = (
        '/etc/ackrc',
    );
}

my @std_files = (@global_files, File::Spec->catfile($ENV{'HOME'}, '.ackrc'));

my $wd      = getcwd;
my $tempdir = File::Temp->newdir;
chdir $tempdir->dirname;

$finder = App::Ack::ConfigFinder->new;
expect_ackrcs \@std_files, 'having no project file should return only the top level files';

no_home {
    expect_ackrcs \@global_files, 'only system-wide ackrc is returned if HOME is not defined with no project files';
};

mkdir 'foo';
mkdir File::Spec->catdir('foo', 'bar');
mkdir File::Spec->catdir('foo', 'bar', 'baz');

chdir File::Spec->catdir('foo', 'bar', 'baz');

touch_ackrc;
expect_ackrcs [ @std_files, File::Spec->rel2abs('.ackrc')], 'a project file in the same directory should be detected';
no_home {
    expect_ackrcs [ @global_files, File::Spec->rel2abs('.ackrc')], 'a project file in the same directory should be detected';
};

unlink '.ackrc';

my $project_file = File::Spec->catfile($tempdir->dirname, 'foo', 'bar', '.ackrc');
touch_ackrc $project_file;
expect_ackrcs [ @std_files, $project_file ], 'a project file in the parent directory should be detected';
no_home {
    expect_ackrcs [ @global_files, $project_file ], 'a project file in the parent directory should be detected';
};
unlink $project_file;

$project_file = File::Spec->catfile($tempdir->dirname, 'foo', '.ackrc');
touch_ackrc $project_file;
expect_ackrcs [ @std_files, $project_file ], 'a project file in the grandparent directory should be detected';
no_home {
    expect_ackrcs [ @global_files, $project_file ], 'a project file in the grandparent directory should be detected';
};

touch_ackrc;

expect_ackrcs [ @std_files, File::Spec->rel2abs('.ackrc')], 'a project file in the same directory should be detected, even with another one above it';
no_home {
    expect_ackrcs [ @global_files, File::Spec->rel2abs('.ackrc')], 'a project file in the same directory should be detected, even with another one above it';
};

unlink '.ackrc';
unlink $project_file;

touch_ackrc '_ackrc';
expect_ackrcs [ @std_files, File::Spec->rel2abs('_ackrc')], 'a project file in the same directory should be detected';
no_home {
    expect_ackrcs [ @global_files, File::Spec->rel2abs('_ackrc')], 'a project file in the same directory should be detected';
};

unlink '_ackrc';

$project_file = File::Spec->catfile($tempdir->dirname, 'foo', '_ackrc');
touch_ackrc $project_file;
expect_ackrcs [ @std_files, $project_file ], 'a project file in the grandparent directory should be detected';
no_home {
    expect_ackrcs [ @global_files, $project_file ], 'a project file in the grandparent directory should be detected';
};

touch_ackrc '_ackrc';
expect_ackrcs [ @std_files, File::Spec->rel2abs('_ackrc')], 'a project file in the same directory should be detected, even with another one above it';
no_home {
    expect_ackrcs [ @global_files, File::Spec->rel2abs('_ackrc')], 'a project file in the same directory should be detected, even with another one above it';
};

unlink $project_file;
touch_ackrc;
my $ok = eval { $finder->find_config_files };
my $err = $@;
ok( !$ok, '.ackrc + _ackrc is error' );
like( $err, qr/contains both \.ackrc and _ackrc/, 'Got the expected error' );

no_home {
  $ok = eval { $finder->find_config_files };
  $err = $@;
  ok( !$ok, '.ackrc + _ackrc is error' );
  like( $err, qr/contains both \.ackrc and _ackrc/, 'Got the expected error' );
};

unlink '.ackrc';
$project_file = File::Spec->catfile($tempdir->dirname, 'foo', '.ackrc');
touch_ackrc $project_file;
expect_ackrcs [ @std_files, File::Spec->rel2abs('_ackrc')], 'a lower-level _ackrc should be preferred to a higher-level .ackrc';
no_home {
    expect_ackrcs [ @global_files, File::Spec->rel2abs('_ackrc')], 'a lower-level _ackrc should be preferred to a higher-level .ackrc';
};

unlink '_ackrc';

do {
    local $ENV{'HOME'} = File::Spec->catdir($tempdir->dirname, 'foo');

    my $user_file = File::Spec->catfile($tempdir->dirname, 'foo', '.ackrc');
    touch_ackrc $user_file;

    expect_ackrcs [ @global_files, $user_file ], q{don't load the same ackrc file twice};
    unlink($user_file);
};

do {
    chdir $tempdir->dirname;
    local $ENV{'HOME'} = File::Spec->catfile($tempdir->dirname, 'foo');

    my $user_file = File::Spec->catfile($ENV{'HOME'}, '.ackrc');
    touch_ackrc $user_file;

    my $ackrc = File::Temp->new;
    close $ackrc;
    local $ENV{'ACKRC'} = $ackrc->filename;

    expect_ackrcs [ @global_files, $ackrc->filename ], q{ACKRC overrides user's HOME ackrc};
    unlink $ackrc->filename;

    expect_ackrcs [ @global_files, $user_file ], q{ACKRC doesn't override if it doesn't exist};

    touch_ackrc $ackrc->filename;
    chdir 'foo';
    expect_ackrcs [ @global_files, $ackrc->filename, $user_file ], q{~/.ackrc should still be found as a project ackrc};
    unlink $ackrc->filename;
};

chdir $wd;
