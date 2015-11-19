#!perl
# -T doesn't work with Test::Kwalitee
#
use strict;

if ($ENV{'TEST_AUTHOR'}) {
    eval {
        TODO: {
            require Test::Kwalitee::Extra;
            # disable metacpan lookups
            Test::Kwalitee::Extra->import(qw/!prereq_matches_use/);
        } ## end TODO:
    };
    if ($@) {
        use Test::More;
        plan skip_all => "Test::Kwalitee::Extra not found.";
        exit;
    }
} ## end if ($ENV{'TEST_AUTHOR'...})
else {
    use Test::More;
    plan skip_all => 'Author tests only.  Set the TEST_AUTHOR environment variable to test.';
}
