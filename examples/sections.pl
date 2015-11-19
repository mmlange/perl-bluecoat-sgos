#!/usr/bin/perl

use lib qw#../lib #;
use Data::Dumper;
use BlueCoat::SGOS;

my $bc = BlueCoat::SGOS->new(
	'debuglevel' => 0,
);

my $file =
	$ARGV[0] || '../t/sysinfos/ProxySG-4006060000--20090307-165730UTC.sysinfo';

$bc->get_sysinfo_from_file($file);
$bc->parse_sysinfo();

my @s = $bc->get_section_list();
foreach my $l (@s) {
	print "		$l\n";
}

print "SSL Statistics\n";
my $data = $bc->get_section('SSL Statistics');
print "$data\n";

