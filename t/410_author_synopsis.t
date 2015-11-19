#!perl
#
#
#
use strict;
use Test::More;

if ($ENV{'TEST_AUTHOR'}) {
    my $min_ver = 0.06;
	eval "use Test::Synopsis $min_ver";
	if ($@) {
        plan skip_all => "Test::Synopsis version $min_ver not found.";
        exit;
	}
	plan tests               => 1;
	subtest 'Synopsis Tests' => sub {
		all_synopsis_ok();
	}
} ## end if ($ENV{'TEST_AUTHOR'...})
else {
	plan skip_all => 'Author tests only.  Set the TEST_AUTHOR environment variable to test.';
}

