#!perl -T
#
#
#
use strict;
use Test::More;

if ($ENV{'TEST_AUTHOR'}) {
	my $min_tpc = 1.08;
	eval "use Test::Pod::Coverage $min_tpc";
	if ($@) {
		plan skip_all =>"Test::Pod::Coverage $min_tpc required for testing POD coverage.";
        exit;
	}

	my $min_pc = 0.18;
	eval "use Pod::Coverage $min_pc";
	if ($@) {
		plan skip_all => "Pod::Coverage $min_pc required for testing POD coverage.";
        exit;
	}

	# ok, Test::Pod::Coverage and Pod::Coverage check out ok
	my @modules           = all_modules('lib');
	my $number_of_modules = $#modules + 1;
	plan tests => $number_of_modules;
	foreach my $module (@modules) {
		note("begin $module");
		pod_coverage_ok($module);
		note("end $module");
	}
} ## end if ($ENV{'TEST_AUTHOR'...})
else {
	plan skip_all =>'Author tests only.  Set the TEST_AUTHOR environment variable to test.';
}

