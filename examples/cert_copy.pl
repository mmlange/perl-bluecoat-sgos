#!/usr/bin/perl
#
#
#
use strict;
use lib qw#../lib #;
use BlueCoat::SGOS 1.04;
use Getopt::Long;
use Data::Dumper;

my $bc = BlueCoat::SGOS->new(
    'appliancehost'     => 'prxord0101001.lange.bluecoat.com',
    'applianceport'     => 8082,
    'applianceuser'     => 'admin',
    'appliancepassword' => 'heynow',
    'debuglevel'        => 0
);

my $cmd = qq|exit
show ssl keyring
|;

my @k = split(/\n/, $bc->send_command($cmd));

my $keyring_id;
my %keys;
foreach my $line (@k) {
    if ($line =~ m/^Keyring ID:/) {
        ($keyring_id) = $line =~ m/^Keyring ID:\s+(.*)/;
        next;
    }
    my ($k, $v) = $line =~ m/^(.+)\:\s+(.+)$/;
    if (defined($k) && defined($v)) {
        $keys{$keyring_id}{$k} = $v;
    }

} ## end foreach my $line (@k)

foreach $keyring_id (sort keys %keys) {

    # is the private key showable?
    my $private_key_showability = $keys{$keyring_id}{'Private key showability'};
    if ($private_key_showability !~ m/no-show/i) {
        my $cmd           = qq|show ssl keypair "$keyring_id"|;
        my $output        = $bc->send_command($cmd);
        my ($private_key) = $output =~ m/(^-----.*-----$)/ism;
        $keys{$keyring_id}{'private_key'} = $private_key;
    } ## end if ($private_key_showability...)
    my $public_certificate_present = $keys{$keyring_id}{'Certificate'};
    if ($public_certificate_present !~ m/absent/i) {
        my $cmd    = qq|exit\nshow ssl certificate "$keyring_id"|;
        my $output = $bc->send_command($cmd);

        #print "output=$output\n\n";
        my ($public_certificate) = $output =~ m/(^-----.*-----$)/ism;
        $keys{$keyring_id}{'public_certificate'} = $public_certificate;
    } ## end if ($public_certificate_present...)

} ## end foreach $keyring_id (sort keys...)

$cmd = qq|conf t
ssl
|;
foreach $keyring_id (sort keys %keys) {

    # conf t
    # ssl
    # inline keyring "$keyring_id" show "" ZZZ
    # data here
    # ZZZ
    if (
        defined($keys{$keyring_id}{'public_certificate'})
            &&
        defined($keys{$keyring_id}{'private_key'})
     ){

        #print "OK, got a public_cert\n";
        $cmd .= qq|
inline keyring show "$keyring_id" "" ZZZ
$keys{$keyring_id}{'private_key'}
ZZZ

inline certificate "$keyring_id" ZZZ
$keys{$keyring_id}{'public_certificate'}
ZZZ

    |;

    } ## end if (defined($keys{$keyring_id...}))
} ## end foreach $keyring_id (sort keys...)

print "$cmd\n\n";
#print Dumper(%keys);
