
#-------------------------------------------------------------------------------
#- wrapping class --------------------------------------------------------------
#-------------------------------------------------------------------------------

# the idea of this class is to wrap up the original PathFind::Data command
# class and replace the various _make_* methods, which are tested in separate
# test scripts, with dummy "around" modifiers. That will allow us to test the
# run method without actually calling the concrete methods.

package Bio::Path::Find::App::TestFind;

use Moose;
use namespace::autoclean;
use MooseX::StrictConstructor;

extends 'Bio::Path::Find::App::PathFind::Data';

around '_make_symlinks' => sub {
  print STDERR 'called _make_symlinks';
};

around '_make_tar' => sub {
  print STDERR 'called _make_tar';
};

around '_make_zip' => sub {
  print STDERR 'called _make_zip';
};

around '_make_stats' => sub {
  print STDERR 'called _make_stats';
};

#-------------------------------------------------------------------------------
#- main test script ------------------------------------------------------------
#-------------------------------------------------------------------------------

package main;

use strict;
use warnings;

use Test::More tests => 8;
use Test::Exception;
use Test::Output;
use Path::Class;
use File::Temp;
use Cwd;

# set up the "linked" directory for the test suite
use lib 't';

use Test::Setup;

unless ( -d dir( qw( t data linked ) ) ) {
  diag 'creating symlink directory';
  Test::Setup::make_symlinks;
}

use Bio::Path::Find::Finder;

# don't initialise l4p here because we want to test that command line logging
# is correctly set up by the AppRole

use_ok('Bio::Path::Find::App::TestFind');

# set up a temp dir where we can write files
my $temp_dir = File::Temp->newdir;
dir( $temp_dir, 't' )->mkpath;
my $orig_cwd = getcwd;
symlink dir( $orig_cwd, qw( t data ) ), dir( $temp_dir, qw( t data ) )
  or die "ERROR: couldn't link data directory into temp directory";
chdir $temp_dir;

# the basic params. These will stay unchanged for all of the subsequent runs
my %params = (
  config => file(qw( t data 15_pf_data test.conf )),
  id     => '10018_1',
  type   => 'lane',
);

my $tf;
lives_ok { $tf = Bio::Path::Find::App::TestFind->new(%params) }
  'got a new testfind app object';

# print paths
my $file_list = join '', <DATA>;
stdout_is { $tf->run }
  $file_list,
  'printed correct paths';

# make symlinks

# no need to pass in config; it will come from HasConfig Role
delete $params{config};

$params{symlink} = 'my_links_dir';
$tf = Bio::Path::Find::App::TestFind->new(%params);
stderr_is { $tf->run } 'called _make_symlinks', 'correctly called _make_symlinks';

# make tar
delete $params{symlink};
$params{archive} = 'my_archive';
$tf = Bio::Path::Find::App::TestFind->new(%params);
stderr_is { $tf->run } 'called _make_tar', 'correctly called _make_tar';

# make tar
delete $params{archive};
$params{zip} = 'my_zip';
$tf = Bio::Path::Find::App::TestFind->new(%params);
stderr_is { $tf->run } 'called _make_zip', 'correctly called _make_zip';

# make stats
delete $params{zip};
$params{stats} = 'my_stats';
$tf = Bio::Path::Find::App::TestFind->new(%params);
stderr_is { $tf->run } 'called _make_stats', 'correctly called _make_stats';

# multiple flags
$params{archive} = 'my_tar';
$params{stats}   = 'my_stats';
$params{zip}     = 'my_zip';
$tf = Bio::Path::Find::App::TestFind->new(%params);
stderr_like { $tf->run }
  qr/called _make_tar.*?_make_zip.*?_make_stats/,
  'correctly called multiple _make_* methods';

#-------------------------------------------------------------------------------

# done_testing;

chdir $orig_cwd;

__DATA__
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N2_OP1/SLX/APP_N2_OP1_7492530/10018_1#1
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_2/SLX/APP_IN_2_7492527/10018_1#2
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T1_OP2/SLX/APP_T1_OP2_7492533/10018_1#3
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_4/SLX/APP_IN_4_7492537/10018_1#4
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N1_OP2/SLX/APP_N1_OP2_7492529/10018_1#5
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N1_OP1/SLX/APP_N1_OP1_7492528/10018_1#6
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T1_OP1/SLX/APP_T1_OP1_7492532/10018_1#7
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_3/SLX/APP_IN_3_7492536/10018_1#8
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N2_OP2/SLX/APP_N2_OP2_7492531/10018_1#9
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_1/SLX/APP_IN_1_7492526/10018_1#10
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T2_OP1/SLX/APP_T2_OP1_7492534/10018_1#11
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T2_OP2/SLX/APP_T2_OP2_7492535/10018_1#12
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_5/SLX/APP_IN_5_7492538/10018_1#13
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N3_OP1/SLX/APP_N3_OP1_7492539/10018_1#14
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N3_OP2/SLX/APP_N3_OP2_7492540/10018_1#15
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N4_OP1/SLX/APP_N4_OP1_7492541/10018_1#16
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N4_OP2/SLX/APP_N4_OP2_7492542/10018_1#17
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N5_OP1/SLX/APP_N5_OP1_7492543/10018_1#18
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N5_OP2/SLX/APP_N5_OP2_7492544/10018_1#19
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T3_OP1/SLX/APP_T3_OP1_7492545/10018_1#20
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T3_OP2/SLX/APP_T3_OP2_7492546/10018_1#21
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T4_OP1/SLX/APP_T4_OP1_7492547/10018_1#22
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T4_OP2/SLX/APP_T4_OP2_7492548/10018_1#23
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T5_OP1/SLX/APP_T5_OP1_7492549/10018_1#24
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T5_OP2/SLX/APP_T5_OP2_7492550/10018_1#25
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_1/SLX/APP_IN_1_7492551/10018_1#27
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_2/SLX/APP_IN_2_7492552/10018_1#28
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N1_OP1/SLX/APP_N1_OP1_7492553/10018_1#29
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N1_OP2/SLX/APP_N1_OP2_7492554/10018_1#30
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N2_OP1/SLX/APP_N2_OP1_7492555/10018_1#31
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N2_OP2/SLX/APP_N2_OP2_7492556/10018_1#32
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T1_OP1/SLX/APP_T1_OP1_7492557/10018_1#33
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T1_OP2/SLX/APP_T1_OP2_7492558/10018_1#34
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T2_OP1/SLX/APP_T2_OP1_7492559/10018_1#35
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T2_OP2/SLX/APP_T2_OP2_7492560/10018_1#36
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_3/SLX/APP_IN_3_7492561/10018_1#37
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_4/SLX/APP_IN_4_7492562/10018_1#38
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_IN_5/SLX/APP_IN_5_7492563/10018_1#39
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N3_OP1/SLX/APP_N3_OP1_7492564/10018_1#40
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N3_OP2/SLX/APP_N3_OP2_7492565/10018_1#41
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_N4_OP1/SLX/APP_N4_OP1_7492566/10018_1#42
t/data/linked/prokaryotes/seq-pipelines/Actinobacillus/pleuropneumoniae/TRACKING/607/APP_T5_OP2/SLX/APP_T5_OP2_7492575/10018_1#51
