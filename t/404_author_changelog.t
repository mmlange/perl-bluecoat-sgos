#!perl
#
use Test::More;

if ($ENV{'TEST_AUTHOR'}) {
    my $min_ver = 0.23;
    eval "use Test::CPAN::Changes $min_ver";
    if ($@) {
        plan skip_all =>"Test::CPAN::Changes $min_ver not available";
        }
    else {
     changes_ok();
    }

    }
    else {
    plan skip_all =>
    'Author tests only.  Set the TEST_AUTHOR environment variable to test.';
}

