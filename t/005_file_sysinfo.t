#!perl -T
#
#
#
use strict;
use BlueCoat::SGOS;
use File::Slurp;
use Test::More;

BEGIN {chdir 't' if -d 't'}

my @directories;
my %testparams;
my $regex = $ARGV[0];

if (defined($ENV{'TEST_AUTHOR'})) {
    opendir(D, 'sysinfos/');
    @directories = readdir(D);
    closedir D;
}
else {
    @directories = qw/sysinfos.public/;
}

foreach my $directory (@directories) {
    opendir(D, "sysinfos/$directory");
    my @files = readdir(D);
    closedir D;

    foreach my $file (@files) {
        if ($file =~ m/\.parameters$/) {
            my @lines = read_file("sysinfos/$directory/$file");
            chomp @lines;
            foreach my $line (@lines) {
                my @s = split(/;/, $line);
                if ($#s < 1) {next}
                if ($regex) {
                    if ($s[0] !~ /$regex/) {next}
                }
                $testparams{"sysinfos/$directory/$s[0]"}{$s[1]} = $s[2];
            } ## end foreach my $line (@lines)
            close F;
        } ## end if ($file =~ m/\.parameters$/)
    } ## end foreach my $file (@files)
} ## end foreach my $directory (@directories)

my $totaltests = (keys %testparams);
plan tests => $totaltests;

foreach my $filename (keys %testparams) {
    my %data     = %{$testparams{$filename}};
    my $subtests = keys %data;
    $subtests = $subtests + 4;
    note("subtests=$subtests");
    subtest "For $filename" => sub {
        plan tests => $subtests;
        note("Begin $filename");
        my $bc = BlueCoat::SGOS->new('debuglevel' => 0);

        # test 1 - do we have an object
        ok($bc, 'have an object');

        # test 2 - can we get a sysinfo from file
        ok($bc->get_sysinfo_from_file($filename), "file=$filename, got sysinfo");

        # test 3 - parse sysinfo (returns 1 if ok)
        ok($bc->parse_sysinfo(), "file=$filename, parse_sysinfo");

        # test 4 - is the size of the sysinfo greater than 10
        ok(length($bc->{'sgos_sysinfo'}) > 10, "file=$filename, sysinfo size gt 10");

        foreach (sort keys %data) {
            my $k     = $_;
            my $value = $data{$k};

            if ($k =~ m/int-/) {
                my ($interface, $configitem) = $k =~ m/int-(.+)-(.+)/;
                if (!defined($value) && !defined($bc->{'interface'}{$interface}{$configitem})) {
                    pass("file=$filename, expected $interface $configitem undefined, got undefined)");
                }
                elsif ($value) {
                    ok($bc->{'interface'}{$interface}{$configitem} eq $value, "file=$filename, expected $interface $configitem ($value), got ($bc->{'interface'}{$interface}{$configitem})");
                }
                else {
                    fail("file=$filename, expected $interface $configitem ($value), got ($bc->{'in    terface'}{$interface}{$configitem})");
                }
            } ## end if ($k =~ m/int-/)
            elsif ($k =~ m/length-/) {
                my ($var) = $k =~ m/length-(.+)/;
                my $length = length($bc->{$var}) || 0;
                if (!defined($value)) {
                    $value = 0;
                }
                ok($length == $value, "file=$filename, length($var), expected ($value), got ($length)");
            } ## end elsif ($k =~ m/length-/)
            else {
                if (!defined($value) && !defined($bc->{$k})) {
                    pass("file=$filename, $k: expected blank, got blank");
                }
                else {
                    ok($bc->{$k} eq $value, "file=$filename, $k: expected ($value), got ($bc->{$k})");
                }
            } ## end else [ if ($k =~ m/int-/) ]
        } ## end foreach (sort keys %data)
        note("End $filename");
        }
} ## end foreach my $filename (keys ...)
