#!perl -T
#
#
#
use strict;
use Test::More;

if ($ENV{'TEST_AUTHOR'}) {
	my $min_tp = 1.22;
	eval "use Test::Pod $min_tp";
	if ($@) {
		plan skip_all =>"Skipping tests.  Test::Pod $min_tp required for testing POD.";
        exit;
	}
	my @files           = all_pod_files('lib');
	my $number_of_files = $#files + 1;
	plan tests => $number_of_files;
	foreach my $file (@files) {
		note("begin $file");
		pod_file_ok($file);
		note("end $file");
	}
} ## end if ($ENV{'TEST_AUTHOR'...})
else {
	plan skip_all => 'Author tests only.  Set the TEST_AUTHOR environment variable to test.';
}

