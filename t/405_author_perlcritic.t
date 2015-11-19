#!perl -w
#
#
#
use strict;
use Test::More;

if ($ENV{'TEST_AUTHOR'}) {
    my $min_tpc_ver = 1.02;
    my $min_pcu_ver = 1.118;
    eval "use Test::Perl::Critic $min_tpc_ver (
		-profile=>'t/perlcriticrc',
		-verbose=>8);";
    if ($@) {
        plan skip_all => "Test::Perl::Critic version $min_tpc_ver is not installed.";
    }
    eval "use Perl::Critic::Utils $min_pcu_ver;";
    if ($@) {
        plan skip_all => "Perl::Critic::Utils version $min_pcu_ver is not installed.";
    }
    my @files           = all_perl_files('lib');
    my $number_of_files = $#files + 1;

TODO: {
        local $TODO = "soft fail on Perl::Critic";
        plan tests => $number_of_files;
        foreach my $file (@files) {
            note("begin $file");
            critic_ok($file);
            note("end $file");
        }

    } ## end TODO:
} ## end if ($ENV{'TEST_AUTHOR'...})
else {
    plan skip_all => 'Author tests only.  Set the TEST_AUTHOR environment variable to test.';
}

