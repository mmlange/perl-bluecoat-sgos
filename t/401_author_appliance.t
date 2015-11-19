#!perl -T
#
#
#
use strict;
use BlueCoat::SGOS;
use Test::More;

# If we don't have environment variables, we can't test with a live box
my $env_available =
       $ENV{'TEST_AUTHOR'}
    && $ENV{'BC_HOST'}
    && $ENV{'BC_PORT'}
    && $ENV{'BC_CONNECTMODE'}
    && $ENV{'BC_USER'}
    && $ENV{'BC_PASS'};

if (!defined($env_available)) {
    plan skip_all => 'Author tests only.  Set the proper environment variables to test.';
    exit;
}
else {
    plan tests => 10;

    if ($ENV{'BC_DEBUG'}) {
        diag("Connecting to Blue Coat appliance at $ENV{'BC_HOST'}:$ENV{'BC_PORT'} using $ENV{'BC_CONNECTMODE'}");
    }

    # test 3 can create an object
    my $bc = BlueCoat::SGOS->new(
        'appliancehost'        => $ENV{'BC_HOST'},
        'applianceport'        => $ENV{'BC_PORT'},
        'applianceconnectmode' => $ENV{'BC_CONNECTMODE'},
        'applianceusername'    => $ENV{'BC_USER'},
        'appliancepassword'    => $ENV{'BC_PASS'},
        'debuglevel'           => $ENV{'BC_DEBUG'} || 1,
    );
    isa_ok($bc, 'BlueCoat::SGOS');

    # test 4 get sysinfo
    my $get_sysinfo_return = $bc->get_sysinfo_from_appliance();
    ok($get_sysinfo_return, 'get sysinfo from appliance');
    if ($get_sysinfo_return == 0) {
        if ($ENV{'BC_DEBUG'}) {
            diag("Can't connect to appliance at $ENV{'BC_HOST'}");
        }
        BAIL_OUT("Can't connect to appliance at $ENV{'BC_HOST'}");
    } ## end if ($get_sysinfo_return...)

    # test 5 parse sysinfo
    ok($bc->parse_sysinfo(), 'parse sysinfo');

    # test 6 sysinfo size gt 10
    ok(length($bc->{'sgos_sysinfo'}) > 10, "length of sysinfo=" . length($bc->{'sgos_sysinfo'}));

    if ($ENV{'BC_DEBUG'}) {
        diag("length of sysinfo=" . length($bc->{'sgos_sysinfo'}));
    }

    # Test 7 sgosversion looks normal
    like($bc->{'sgosversion'}, qr/\d+\.\d+\.\d+\.\d+/, "sgosversion=$bc->{'sgosversion'}");
    if ($ENV{'BC_DEBUG'}) {
        diag("sgosversion=$bc->{'sgosversion'}");
    }

    # Test 8 sgosreleaseid looks normal
    like($bc->{'sgosreleaseid'}, qr/\d+/, "sgosreleaseid=$bc->{'sgosreleaseid'}");
    if ($ENV{'BC_DEBUG'}) {
        diag("sgosreleaseid=$bc->{'sgosreleaseid'}");
    }

    # test 9 serialnumber looks normal
    like($bc->{'serialnumber'}, qr/\d+/, "serialnumber=$bc->{'serialnumber'}");
    if ($ENV{'BC_DEBUG'}) {
        diag("serialnumber=$bc->{'serialnumber'}");
    }

    # model number exists (could be one of 200-10, 9000-5, VA-5, etc.)
    ok($bc->{'modelnumber'}, "modelnumber=$bc->{'modelnumber'}");
    if ($ENV{'BC_DEBUG'}) {
        diag("modelnumber=$bc->{'modelnumber'}");
    }

    # is model supported
    ok(exists($bc->{'supported_configuration'}), "supported_configuration=$bc->{'supported_configuration'}");
    if ($ENV{'BC_DEBUG'}) {
        diag("supported_configuration=$bc->{'supported_configuration'}");
    }

    # appliance-name exists
    ok($bc->{'appliance-name'}, "appliance-name=$bc->{'appliance-name'}");
    if ($ENV{'BC_DEBUG'}) {
        diag("appliance-name=$bc->{'appliance-name'}");
    }
} ## end else [ if (!defined($env_available...))]

