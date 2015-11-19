package BlueCoat::SGOS;
use strict;
use Carp;
use Crypt::OpenSSL::X509;
use Date::Parse;
use DateTime;
use English qw/-no_match_vars/;
use File::Map qw/map_file map_handle/;
use HTTP::Request;
use HTTP::Request::Common qw/POST/;
use LWP::UserAgent;
use LWP::Protocol::https;
use Readonly;
use warnings;

# MakeMaker trickery to allow Makefile.PL to grab version from variable below
our $VERSION = '1.06';
Readonly::Scalar $VERSION => '1.06';

Readonly::Hash our %_URL => (
    'sysinfo'      => '/sysinfo',
    'send_command' => '/Secure/Local/console/install_upload_action/cli_post_setup.txt',
);

Readonly::Hash our %REGEX => ('ipaddress' => '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}');
Readonly::Scalar our $SYSINFO_SIZE_CUTOFF => 10;
Readonly::Scalar our $HOURS_PER_DAY       => 24;
Readonly::Scalar our $SECONDS_PER_HOUR    => 3600;

=for test_synopsis
no strict 'vars';
no warnings;


=head1 NAME

BlueCoat::SGOS - A module to interact with Blue Coat SGOS-based devices.

=cut

=head1 SYNOPSIS


    use strict; #always!
    use BlueCoat::SGOS;
    my $bc = BlueCoat::SGOS->new(
        'appliancehost'     => 'swg.example.com',
        'applianceport'     => 8082,
        'applianceuser'     => 'admin',
        'appliancepassword' => 'password'
    );
    $bc->get_sysinfo_from_appliance();
    $bc->parse_sysinfo();

    # or from a file
    use strict; #always!
    use BlueCoat::SGOS;
    my $bc = BlueCoat::SGOS->new();
    $bc->get_sysinfo_from_file('/path/to/file.sysinfo');
    $bc->parse_sysinfo();

    # or from a data structure
    # in this case, $sysinfodata already contains sysinfo data
    use strict; #always!
    use BlueCoat::SGOS;
    my $sysinfodata = 'already contains sysinfo data...';
    my $bc = BlueCoat::SGOS->new();
    $bc->get_sysinfo_from_data($sysinfodata);
    $bc->parse_sysinfo();

    my $sysinfodata = $bc->{'sgos_sysinfo'};
    my $sgosversion = $bc->{'sgosversion'};
    my $sgosreleaseid = $bc->{'sgosreleaseid'};
    my $serialnumber = $bc->{'serialnumber'};
    my $modelnumber = $bc->{'modelnumber'};
    my $sysinfotime = $bc->{'sysinfotime'};

    # Hardware section of the sysinfo file
    my $hwinfo = $bc->{'sgos_sysinfo_section'}{'Hardware Information'};

    # Software configuration (i.e. show configuration)
    my $swconfig = $bc->{'sgos_sysinfo_section'}{'Software Configuration'};


=head1 DESCRIPTION

This module provides a standard way to programmatically interact with Blue Coat
SGOS-based devices.  

The main features of this module are:

=over 1

=item *
Parsing of sysinfo data from one of the following data sources:

=over 2

=item *

direct connection to appliance

=item * 

from sysinfo data stored on the filesystem

=item *

from sysinfo data already stored in a scalar

=back

=item *

Some other goodness here.

=back



=head1 SUBROUTINES/METHODS

Below are methods for BlueCoat::SGOS.

=cut

=head2 new

Creates a new BlueCoat::SGOS object.  Can be passed one of the following:

    appliancehost
    applianceport
    applianceusername
    appliancepassword
    applianceconnectmode (one of http or https)
    debuglevel

=cut

sub new {
    my @n     = @_;
    my $class = shift @n;
    my $self  = {};
    bless($self, $class);

    my %args = (
        'appliancehost'        => 'proxy',
        'applianceport'        => 8082,
        'applianceusername'    => 'admin',
        'appliancepassword'    => 'password',
        'applianceconnectmode' => 'https',
        'debuglevel'           => 0,
        @n,
    );

    $self->{'_appliancehost'}        = $args{'appliancehost'};
    $self->{'_applianceport'}        = $args{'applianceport'};
    $self->{'_applianceusername'}    = $args{'applianceusername'};
    $self->{'_appliancepassword'}    = $args{'appliancepassword'};
    $self->{'_applianceconnectmode'} = $args{'applianceconnectmode'};
    $self->{'_debuglevel'}           = $args{'debuglevel'};
    if (   $self->{'_appliancehost'}
        && $self->{'_applianceport'}
        && $self->{'_applianceconnectmode'}
        && $self->{'_applianceusername'}
        && $self->{'_appliancepassword'}) {

        if ($self->{'_applianceconnectmode'} eq 'https') {
            $self->{'_applianceurlbase'} =
                q#https://# . $self->{'_appliancehost'} . q#:# . $self->{'_applianceport'};
        }
        elsif ($self->{'_applianceconnectmode'} eq 'http') {
            $self->{'_applianceurlbase'} =
                q#http://# . $self->{'_appliancehost'} . q#:# . $self->{'_applianceport'};
        }
    } ## end if ($self->{'_appliancehost'...})
    $self->{'sgos_sysinfo'} = undef;

    return $self;
} ## end sub new

sub _create_ua {
    my $self = shift;
    $self->{'_lwpua'} = LWP::UserAgent->new();
    $self->{'_lwpua'}->agent("BlueCoat-SGOS/$VERSION");
    $self->{'_lwpua'}->ssl_opts(
        'SSL_verify_mode' => 0,
        'verify_hostname' => 0,
    );
    return undef;
} ## end sub _create_ua

=head2 get_sysinfo_from_appliance

Takes no parameters, but instead fetches the sysinfo from the
appliance specified in the constructor.

    $bc->get_sysinfo_from_appliance();

=cut

sub get_sysinfo_from_appliance {
    my $self = shift;

    if ($self->{'_debuglevel'} > 0) {
        print 'urlbase=' . $self->{'_applianceurlbase'} . "\n";
        print 'Getting ' . $self->{'_applianceurlbase'} . $_URL{'sysinfo'} . "\n";
    }
    if (!defined($self->{'_lwpua'})) {
        $self->_create_ua();
    }
    my $request =
        HTTP::Request->new('GET', $self->{'_applianceurlbase'} . $_URL{'sysinfo'});
    $request->authorization_basic($self->{'_applianceusername'}, $self->{'_appliancepassword'});
    my $response = $self->{'_lwpua'}->request($request);

    if ($response->is_error) {
        return 0;
    }
    else {
        $self->{'sgos_sysinfo'} = $response->content;
        $self->{'sgos_sysinfo'} =~ s/\r\n/\n/gi;
        if ($self->{'_debuglevel'} > 0) {
            print 'status=' . $response->status_line . "\n";
            print 'length of sysinfo=' . length($self->{'sgos_sysinfo'}) . "\n";
        }
    } ## end else [ if ($response->is_error)]
    if ($self->{'sgos_sysinfo'}) {
        return 1;
    }
    else {
        return 0;
    }
} ## end sub get_sysinfo_from_appliance

=head2 get_sysinfo_from_file

Takes one parameter: the filename of a sysinfo file on the disk.  Use this
instead of logging in over the network.

    $bc->get_sysinfo_from_file('sysinfo.filename.here');

=cut

sub get_sysinfo_from_file {
    my $self     = shift;
    my $filename = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "sub:get_sysinfo_from_file, filename=$filename\n";
    }

    if (-f $filename) {
        map_file $self->{'sgos_sysinfo'}, $filename, '+<';
        $self->{'sgos_sysinfo'} =~ s/\r\n/\n/gi;
        if ($self->{'sgos_sysinfo'}) {
            $self->parse_sysinfo();
        }
        if ($self->{'_sgos_sysinfo_split_count'} > 0) {
            return 1;
        }
        else {
            return 0;
        }
    } ## end if (-f $filename)
    else {

        # no filename specified
        return 0;
    }
} ## end sub get_sysinfo_from_file

=head2 get_sysinfo_from_data

Takes one parameter: a scalar that contains sysinfo data.
Use this instead of logging in over the network.

    $bc->get_sysinfo_from_data($sysinfodata);

=cut

sub get_sysinfo_from_data {
    my $self = shift;
    my $data = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "sub:get_sysinfo_from_data\n";
    }
    $self->{'sgos_sysinfo'} = $data;
    $self->{'sgos_sysinfo'} =~ s/\r\n/\n/gi;
    if ($self->{'sgos_sysinfo'}) {
        return 1;
    }
    else {
        return 0;
    }
} ## end sub get_sysinfo_from_data

=head2 parse_sysinfo

Takes no parameters.  Tells the object to parse the sysinfo
data and populate the object variables.

=cut

sub parse_sysinfo {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "parse_sysinfo\n";
    }
    if (!defined($self->{'sgos_sysinfo'})) {
        return 0;
    }
    elsif (length($self->{'sgos_sysinfo'}) < $SYSINFO_SIZE_CUTOFF) {
        return 0;
    }

    my @split_sysinfo = split(/_{74}/, $self->{'sgos_sysinfo'});
    $self->{'_sgos_sysinfo_split_count'} = $#split_sysinfo;

    if ($self->{'_debuglevel'} > 0) {
        print "split_sysinfo = $#split_sysinfo\n";
    }

    # init the % var
    $self->{'sgos_sysinfo_section'}{'_ReportInfo'} = $split_sysinfo[0];

    # Populate the sysinfo version
    # As of 6.2.2011, these are the known versions:
    # Version 4.6
    # Version 5.0
    # Version 6.0
    # Version 6.1
    # Version 7.0
    ($self->{'_sysinfoversion'}) =
        $self->{'sgos_sysinfo_section'}{'_ReportInfo'} =~ m/Version (\d+\.\d+)/;
    if ($self->{'_sysinfoversion'} && $self->{'_debuglevel'} > 0) {
        print "_sysinfoversion = $self->{'_sysinfoversion'}\n";
    }

    # Loop through each section of the split sysinfo
    foreach (1 .. $#split_sysinfo) {
        my $chunk = $split_sysinfo[$_];
        if ($self->{'_debuglevel'} > 0) {
            print "_chunk number $_\n";
        }
        my @section = split(/\n/, $chunk);
        chomp @section;

        # the first 2 lines are junk
        shift @section;
        shift @section;
        my $sectionname = shift @section;

        if ($sectionname eq 'Software Configuration') {

            # get rid of 3 lines from top and 1 from bottom
            shift @section;
            shift @section;
            shift @section;
            pop @section;
        } ## end if ($sectionname eq 'Software Configuration')
        if ($sectionname eq 'TCP/IP Routing Table') {
            shift @section;
            shift @section;
            shift @section;
            shift @section;
            shift @section;
        } ## end if ($sectionname eq 'TCP/IP Routing Table')

        # throw away the next line, it contains the URL for the source data
        shift @section;
        my $data = join("\n", @section);
        $self->{'sgos_sysinfo_section'}{$sectionname} = $data;
    } ## end foreach (1 .. $#split_sysinfo)

    # parse version
    $self->_parse_sgos_version();

    # parse releaseid
    $self->_parse_sgos_releaseid();

    # parse serial number
    $self->_parse_serial_number();

    # parse sysinfo time
    $self->_parse_sysinfo_time();

    # parse last reboot time
    $self->_parse_reboot_time();

    # parse model
    $self->_parse_model_number();

    # parse the configuration
    if ($self->{'sgos_sysinfo_section'}{'Software Configuration'}) {

        #$self->_parse_swconfig;
        $self->{'sysinfo_type'} = 'sysinfo';
    }
    else {
        $self->{'sysinfo_type'} = 'sysinfo_snapshot';
    }

    # parse VPM-CPL and VPM-XML
    $self->_parse_content_filter_status();

    # parse VPM-CPL and VPM-XML
    $self->_parse_policy();

    # parse the static bypass list
    $self->_parse_static_bypass();

    # parse the appliance name
    $self->_parse_appliance_name();

    # parse the network information
    $self->_parse_network();

    # parse the ssl accelerator info
    $self->_parse_ssl_accelerator();

    # parse the ca certificates
    $self->_parse_ssl_ca_certificates();

    # parse the default gateway
    $self->_parse_default_gateway();

    # parse the route table
    $self->_parse_route_table();

    # parse the licensing section
    $self->_parse_licensing();

    # parse pac file
    $self->_parse_pac_file();

    # parse wccp configuration
    $self->_parse_wccp_config();

    return 1;
} ## end sub parse_sysinfo

# Find appliance-name
# located in the Software Configuration
# looks like:
# appliance-name "ProxySG 210 4609077777"
# limited to 127 characters
# e.g.: % String exceeds allowed length (127)
#
sub _parse_appliance_name {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_appliance_name\n";
    }
    if (defined($self->{'sgos_sysinfo_section'}{'Software Configuration'})) {
        (undef, $self->{'appliance-name'}) = $self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/(appliance-name|hostname) (.+)$/im;
        if (defined($self->{'appliance-name'})) {
            $self->{'appliance-name'} =~ s/^\"//;
            $self->{'appliance-name'} =~ s/\"$//;

            if ($self->{'_debuglevel'} > 0) {
                print "appliancename=$self->{'appliance-name'}\n";
            }
        } ## end if (defined($self->{'appliance-name'...}))
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_appliance_name

sub _parse_timezone {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_timezone\n";
    }
    if (defined($self->{'sgos_sysinfo_section'}{'Software Configuration'})) {
        ($self->{'appliance-timezone'}) = $self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/timezone set (.+)$/im;

        # If timezone is missing from the configuration,
        # it is not overridden and is by default in UTC
        if (!defined($self->{'appliance-timezone'})) {
            $self->{'appliance-timezone'} = 'UTC';
        }

        my $dt = DateTime->from_epoch(epoch => $self->{'sysinfotime_epoch'});
        $dt->set_time_zone($self->{'appliance-timezone'});
        $self->{'appliance-timezone-offset-seconds'} = $dt->offset();
        $self->{'appliance-timezone-offset-hm'}      = $dt->strftime('%z');

        if ($self->{'_debuglevel'} > 0) {
            print "timezone=$self->{'appliance-timezone'}\n";
        }

    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_timezone

sub _parse_licensing {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_licensing\n";
    }
    if (defined($self->{'sgos_sysinfo_section'}{'Licensing Statistics'})) {
        my @license_blocks =
            split(/\n\n/, $self->{'sgos_sysinfo_section'}{'Licensing Statistics'});
        foreach my $license_block (@license_blocks) {
            if ($license_block =~ m/Component name.*Valid.*Serial number.*Product Description.*Part Number/ism) {
                my $o_license;
                my @license_lines = split(/\n/, $license_block);
                foreach my $license_line (@license_lines) {
                    my ($k, $v) = $license_line =~ m/(.*?):\s+(.*)/;
                    if ($k) {
                        $k =~ s/\s+/_/g;
                        $k = lc($k);
                        $o_license->{$k} = $v;
                    }
                } ## end foreach my $license_line (@license_lines)
                push @{$self->{'licensing'}{'components'}}, $o_license;
            } ## end if ($license_block =~ ...)
        } ## end foreach my $license_block (...)
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_licensing

# model
# Model: 200-B
sub _parse_model_number {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_model_number\n";
    }

    #210-5 (unsupported configuration)
    #
    if (defined($self->{'sgos_sysinfo_section'}{'Hardware Information'})) {
        ($self->{'modelnumber'}) = $self->{'sgos_sysinfo_section'}{'Hardware Information'} =~ m/Model:\s(.+)/im;
        if ($self->{'modelnumber'} =~ m/unsupported configuration/i) {
            $self->{'modelnumber'} =~ s/\s*\(unsupported configuration\)\s*//ig;
            $self->{'supported_configuration'} = 0;
        }
        else {
            $self->{'supported_configuration'} = 1;
        }
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_model_number

# get network
# Network:
#   Interface 0:0: Bypass 10/100     with no link  (MAC 00:d0:83:04:ae:fc)
#   Interface 0:1: Bypass 10/100     running at 100 Mbps full duplex (MAC 00:d0:83:04:ae:fd)
sub _parse_network {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_network\n";
    }
    if (defined($self->{'sgos_sysinfo_section'}{'Hardware Information'})) {
        my ($netinfo) = $self->{'sgos_sysinfo_section'}{'Hardware Information'} =~ m/Network:(.+)Accelerators/ism;
        my @s = split(/\n/, $netinfo);
        chomp @s;
        foreach (@s) {
            my $line        = $_;
            my ($interface) = $line =~ m/Interface\s+(.+)\:\s/im;
            my ($mac)       = $line =~ m/\(MAC\s(.+)\)/im;
            my ($running)   = $line =~ m/running\sat\s(.+)\s\(MAC/im;
            my $capabilities;

            #Interface 0:0: Intel Gigabit     running at 1 Gbps full duplex (MAC 00:e0:81:79:a5:1a)
            #Interface 2:0: Bypass 10/100/1000 with no link  (MAC 00:e0:ed:0b:67:e6)
            if ($line =~ m/running at/) {
                ($capabilities) = $line =~ m/Interface\s$interface\:\s\w+(.+)\s+running at/;
            }
            if ($line =~ m/with no link/) {
                ($capabilities) = $line =~ m/Interface\s$interface\:\s\w+(.+)\s+with no link/;
            }
            if ($capabilities) {
                $capabilities =~ s/\s+//ig;
            }
            if ($interface && $capabilities) {
                $self->{'interface'}{$interface}{'capabilities'} =
                    $capabilities;
            }

            #print "Running=$running\n";
            if ($interface && $mac) {
                $self->{'interface'}{$interface}{'mac'} = $mac;
            }
            if ($interface && $running) {
                $self->{'interface'}{$interface}{'linkstatus'} = $running;
            }
            if ($interface && !$running) {
                $self->{'interface'}{$interface}{'linkstatus'} = 'no link';
            }

            #print "interface=$interface, mac=$mac\n";
        } ## end foreach (@s)
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))

    # supplement from swconfig/networking
    #print "getting supplemental networking info\n";
    my @t;

    if (defined($self->{'sgos_sysinfo_section'}{'Software Configuration'})) {
        @t =
            split(/\n/, $self->{'sgos_sysinfo_section'}{'Software Configuration'});
    }

    #}

    my $interface;
    my ($ip, $netmask);
    foreach (@t) {
        my $line = $_;

        if ($line =~ m/^interface (.+)\;/i) {
            ($interface) = $line =~ m/^interface (\d+\:?\d*\.*\d*)/i;
        }

        # sgos5, ip address and subnet mask are on SAME line
        if ($line =~ m/^ip-address/) {
            ($ip, $netmask) = $line =~ m/^ip-address\s*($REGEX{'ipaddress'}) *($REGEX{'ipaddress'})*/io;
            if (defined($ip)) {
                $ip =~ s/\s+//gi;
            }
            if (defined($netmask)) {
                $netmask =~ s/\s+//gi;
            }
        } ## end if ($line =~ m/^ip-address/)
        if ($line =~ m/^subnet-mask/) {
            ($netmask) = $line =~ m/^subnet-mask *(.{1,3}\..{1,3}\..{1,3}\..{1,3})/i;
            $netmask =~ s/\s+//gi;
        }

        if (defined($interface)) {
            if (length($interface) > 1 && $ip && $netmask) {
                $self->{'interface'}{$interface}{'ip'}      = $ip;
                $self->{'interface'}{$interface}{'netmask'} = $netmask;
                $interface                                  = undef;
                $ip                                         = undef;
            } ## end if (length($interface)...)
        } ## end if (defined($interface...))

    } ## end foreach (@t)
    return undef;
} ## end sub _parse_network

sub _parse_static_bypass {
    my $self = shift;
    if (defined($self->{'sgos_sysinfo_section'}{'Software Configuration'})) {
        my @lines =
            split(/\n/, $self->{'sgos_sysinfo_section'}{'Software Configuration'});
        my $have_static_bypass;
        foreach my $line (@lines) {
            if ($line =~ m/^static-bypass/) {
                $have_static_bypass = 1;
            }
            elsif ($have_static_bypass) {
                if ($line =~ m/^exit/) {
                    last;
                }
                else {
                    $line =~ s/^add //i;
                    if (defined($self->{'static-bypass'})) {
                        $self->{'static-bypass'} = $self->{'static-bypass'} . $line . "\n";
                    }
                    else {
                        $self->{'static-bypass'} = $line . "\n";
                    }
                } ## end else [ if ($line =~ m/^exit/)]
            } ## end elsif ($have_static_bypass)
        } ## end foreach my $line (@lines)
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_static_bypass

sub _parse_policy {
    my $self = shift;
    if (defined($self->{'sgos_sysinfo_section'}{'Policy'})) {
        $self->{'vpm-cpl'} = $self->{'sgos_sysinfo_section'}{'Policy'};
    }

    if (defined($self->{'sgos_sysinfo_section'}{'Software Configuration'})) {
        ($self->{'vpm-xml'}) = $self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/(\<\?xml.+\<(?:vpmapp|empty)\>.+\<\/(?:vpmapp|empty)\>)/ism;
        if ($self->{'vpm-xml'}) {
            $self->{'vpm-xml'} =~ tr/\x00-\x08\x0B\x0C\x0E-\x1F//d;
        }

        # remove characters not in xml spec
        #http://stackoverflow.com/questions/1016910/how-can-i-strip-invalid-xml-characters-from-strings-in-perl/3025663#3025663

        #
        #<?xml version = "1.0" ?>
        #<Empty>
        #<Title> Empty source file. </Title>
        #<Notice>; Settings reset by administrator, Wed, 10 May 2006 18:22:45 UTC</Notice>
        #</Empty>
        #
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))

    if ($self->{'vpm-cpl'} && $self->{'vpm-xml'}) {
        return 1;
    }
    else {
        return undef;
    }
} ## end sub _parse_policy

=head2 get_section_list

Returns an array of sections found in the current sysinfo file.

For example: C<my @section_list = $bc-E<gt>get_section_list();>

=cut

sub get_section_list {
    my $self = shift;
    my @s    = keys %{$self->{'sgos_sysinfo_section'}};
    @s = sort @s;
    return @s;
} ## end sub get_section_list

=head2 get_section

Returns a section of the sysinfo.

=cut

sub get_section {
    my $self    = shift;
    my $section = shift;
    return $self->{'sgos_sysinfo_section'}{$section};
}

=head2 vpmcpl

Displays the VPM-CPL data.  Note that this does not currently return the
local, central, or forwarding policies.

=cut

sub vpmcpl {
    my $self = shift;
    return $self->{'vpm-cpl'};
}

=head2 vpmxml

Displays the VPM-XML data.

=cut

sub vpmxml {
    my $self = shift;
    return $self->{'vpm-xml'};
}

sub _parse_content_filter_status {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_content_filter_status\n";
    }
    my $cfs;

    # Provider:                               Blue Coat
    # Status:                                 Ready
    # Lookup mode:                            Always
    # Download URL:                           https://list.bluecoat.com/bcwf/activity/download/bcwf.db
    # Download Username:                      BCWF-JAN0112
    # Automatic download:                     Enabled
    # Check for updates:                      All day
    # Category review message:                Enabled
    # Dynamic Categorization:
    # Service:                              Enabled
    # Mode:                                 Real-time
    # Secure:                               Disabled
    # Forward Target:
    # SOCKS Gateway Target:
    # Send request info:                    Enabled
    # Send malware info:                    Enabled
    #
    #
    # Memory Allocation:                      Normal
    #
    # CPU Throttle:                           Enabled
    #
    # Regex URL Extraction Result Counts:
    #   Match:                                2579
    #   No Match:                             210214
    #   Null:                                 0
    #   Bad Option:                           0
    #   Bad Magic:                            0
    #   Unknown Node:                         0
    #   No Memory:                            0
    #   Stack Overflow:                       0
    #   Other:
    if (exists($self->{'sgos_sysinfo_section'}{'Content Filter Status'})) {
        my $chunk;
        ($chunk) = $self->{'sgos_sysinfo_section'}{'Content Filter Status'} =~ m/(Provider:.+)Download log:/sm;
        if (!defined($chunk)) {
            return undef;
        }
        ($cfs->{'provider'})                                       = $chunk =~ m/^Provider:\s+(.*)$/m;
        ($cfs->{'status'})                                         = $chunk =~ m/^Status:\s+(.*)$/m;
        ($cfs->{'lookup_mode'})                                    = $chunk =~ m/^Lookup mode:\s+(.*)$/m;
        ($cfs->{'download_url'})                                   = $chunk =~ m/^Download URL:\s+(.*)$/m;
        ($cfs->{'download_username'})                              = $chunk =~ m/^Download Username:\s+(.*)$/m;
        ($cfs->{'automatic_download'})                             = $chunk =~ m/^Automatic download:\s+(.*)$/m;
        ($cfs->{'check_for_updates'})                              = $chunk =~ m/^Check for updates:\s+(.*)$/m;
        ($cfs->{'category_review_message'})                        = $chunk =~ m/^Category review message:\s+(.*)$/m;
        ($cfs->{'dynamic_categorization'}{'service'})              = $chunk =~ m/^Dynamic Categorization:.*\s+Service:\s+(.*?)$/ims;
        ($cfs->{'dynamic_categorization'}{'mode'})                 = $chunk =~ m/^Dynamic Categorization:.+\s+Mode:\s+(.*?)$/ims;
        ($cfs->{'dynamic_categorization'}{'secure'})               = $chunk =~ m/^Dynamic Categorization:.+\s+Secure:\s+(.*?)$/ims;
        ($cfs->{'dynamic_categorization'}{'forward_target'})       = $chunk =~ m/^Dynamic Categorization:.+\s+Forward Target:\s+(.*?)$/ims;
        ($cfs->{'dynamic_categorization'}{'socks_gateway_target'}) = $chunk =~ m/^Dynamic Categorization:.+\s+SOCKS Gateway Target:\s+(.*?)$/ims;
        ($cfs->{'dynamic_categorization'}{'send_request_info'})    = $chunk =~ m/^Dynamic Categorization:.+\s+Send request info:\s+(.*?)$/ims;
        ($cfs->{'dynamic_categorization'}{'send_malware_info'})    = $chunk =~ m/^Dynamic Categorization:.+\s+Send malware info:\s+(.*?)$/ims;
        $self->{'content_filtering'} = $cfs;
    } ## end if (exists($self->{'sgos_sysinfo_section'...}))

    return undef;
} ## end sub _parse_content_filter_status

sub _parse_default_gateway {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
    }

    my @s;
    if (defined($self->{'sgos_sysinfo_section'}{'Software Configuration'})) {
        @s =
            split(/\n/, $self->{'sgos_sysinfo_section'}{'Software Configuration'});
    }
    if ($#s > 0) {
        foreach my $line (@s) {
            if ($line =~ m/^\s*ip-default-gateway/) {
                ($self->{'ip-default-gateway'}) = $line =~ m/^\s*ip-default-gateway +(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/;
            }
        }
    } ## end if ($#s > 0)
    return undef;
} ## end sub _parse_default_gateway

sub _parse_route_table {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_route_table: begin\n";
    }

    #inline static-route-table "end-398382495-inline"
    #; IP-Address Subnet Mask Gateway
    #172.16.0.0 255.240.0.0 172.20.144.1
    #end-398382495-inline
    if (defined($self->{'sgos_sysinfo_section'}{'TCP/IP Routing Table'})) {
        my @r;
        if ($self->{'sgos_sysinfo_section'}{'TCP/IP Routing Table'}) {
            $self->{'routetable'} =
                $self->{'sgos_sysinfo_section'}{'TCP/IP Routing Table'};
        }
        else {
            @r =
                split(/\n/, $self->{'sgos_sysinfo_section'}{'Software Configuration'});
        }
        my $marker;
        foreach my $line (@r) {
            if ($line =~ m/inline static-route-table \"end-\d+-inline\"/i) {
                ($marker) = $line =~ m/inline static-route-table \"end-(\d+)-inline\"/i;
            }
            if ($self->{'_debuglevel'} > 0) {
                print "_parse_route_table: marker=$marker\n";
            }
            if (defined($marker)) {
                if ($line =~ m/^end-$marker-inline/o) {
                    $marker = undef;
                }
            }
            if ($marker && $line !~ /$marker/i) {
                if ($line =~ m/^\s*?\;/) {
                    next;
                }
                if ($line =~ m/\s*($REGEX{'ipaddress'})\s*($REGEX{'ipaddress'})\s*($REGEX{'ipaddress'})/) {
                    if (defined($self->{'static-route-table'})) {
                        $self->{'static-route-table'} = $self->{'static-route-table'} . $line . "\n";
                    }
                    else {
                        $self->{'static-route-table'} = $line . "\n";
                    }

                } ## end if ($line =~ m/\s*($REGEX{'ipaddress'})\s*($REGEX{'ipaddress'})\s*($REGEX{'ipaddress'})/)
            } ## end if ($marker && $line !~...)
        } ## end foreach my $line (@r)
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_route_table

sub _parse_serial_number {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_sgos_serial_number\n";
    }
    if (defined($self->{'sgos_sysinfo_section'}{'Version Information'})) {
        ($self->{'serialnumber'}) = $self->{'sgos_sysinfo_section'}{'Version Information'} =~ m/^Serial number is (\d{10})/im;
    }
    return undef;
} ## end sub _parse_serial_number

sub _parse_ssl_accelerator {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_ssl_accelerator\n";
    }

    # SSL Accelerators
    # looks like:
    # Accelerators: none
    # or
    # Accelerators:
    #  Internal: Cavium CN1010 Security Processor
    #  Internal: Cavium CN501 Security Processor
    #  Internal: Broadcom 5825 Security Processor
    #
    if (defined($self->{'sgos_sysinfo_section'}{'Hardware Information'})) {
        my ($acceleratorinfo) = $self->{'sgos_sysinfo_section'}{'Hardware Information'} =~ m/(Accelerators\:.+)/ism;
        my @a = split(/\n/, $acceleratorinfo);

        #print "There are $#a lines\n";
        # if 1 line, then no SSL accelerator
        if ($#a == 0) {
            $self->{'ssl-accelerator'} = 'none';
        }
        if ($#a > 0) {
            ($self->{'ssl-accelerator'}) = $a[1] =~ m/\s+(.+)/;
        }
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))

    #   print "DEBUG: acceleratorinfo=$acceleratorinfo\n";
    #print "DEBUG: ssl-accelerator=$self->{'ssl-accelerator'}\n";
    return undef;
} ## end sub _parse_ssl_accelerator

sub _parse_ssl_ca_certificates {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_ssl_ca_certificates\n";
    }
    if ($self->{'ssl'}->{'ca'}) {
        return undef;
    }

    # ssl ;mode
    # inline ca-certificate test-east-24 "end-446158970-inline"
    # -----BEGIN CERTIFICATE-----
    # MIIE9jCCA96gAwIBAgIKYeSKxgAAAAAACzANBgkqhkiG9w0BAQUFADBlMRMwEQYK
    # ........
    # end-446158970-inline

    if (exists($self->{'sgos_sysinfo_section'}{'Software Configuration'})) {
        my (@ca_certificate_sections) = $self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/inline ca-certificate (.+) "(.+-inline)"/img;
        my $ca_certificate_section_count = $#ca_certificate_sections / 2;
        if ($ca_certificate_section_count > 0) {
            foreach my $ca_certificate_section_number (0 .. $ca_certificate_section_count) {
                my $certificate_name   = $ca_certificate_sections[$ca_certificate_section_number * 2];
                my $certificate_marker = $ca_certificate_sections[$ca_certificate_section_number * 2 + 1];
                my ($certificate)      = $self->{'sgos_sysinfo_section'}{'Software Configuration'} =~
                    m/$certificate_name.*?$certificate_marker.*?(-{5}BEGIN\sCERTIFICATE-{5}.*?-{5}END\sCERTIFICATE-{5}).*?$certificate_marker/imsg;
                if (defined($certificate)) {
                    $self->{'ssl'}{'ca'}{$certificate_name}{'certificate'} = $certificate;
                }

            } ## end foreach my $ca_certificate_section_number...
        } ## end if ($ca_certificate_section_count...)
    } ## end if (exists($self->{'sgos_sysinfo_section'...}))

    # now parse each of the certs
    #

    if (exists($self->{'ssl'}->{'ca'})) {
        my @certificate_names = keys(%{$self->{'ssl'}->{'ca'}});
        foreach my $certificate_name (@certificate_names) {
            my $x509 = Crypt::OpenSSL::X509->new_from_string($self->{'ssl'}{'ca'}{$certificate_name}{'certificate'});
            my @accessors =
                qw|is_selfsigned fingerprint_md5 fingerprint_sha1 pubkey bit_length subject issuer serial hash notBefore notAfter email version sig_alg_name key_alg_name |;
            foreach my $accessor (@accessors) {
                $self->{'ssl'}{'ca'}{$certificate_name}{$accessor} = $x509->$accessor;
            }

        } ## end foreach my $certificate_name...
    } ## end if (exists($self->{'ssl'...}))

    return undef;
} ## end sub _parse_ssl_ca_certificates

# sysinfo time
# time on this file
# The current time is Mon Nov 23, 2009 18:48:38 GMT (SystemTime 438547718)
# The current time is Sat Mar 7, 2009 16:57:30 GMT (SystemTime 415990650)
sub _parse_sysinfo_time {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_sysinfo_time\n";
    }
    if (defined($self->{'sgos_sysinfo_section'}{'Version Information'})) {
        ($self->{'sysinfotime'}) = $self->{'sgos_sysinfo_section'}{'Version Information'} =~ m/^The current time is (.+) \(/im;
        $self->{'sysinfotime_epoch'} = str2time($self->{'sysinfotime'});

        # get timezone of appliance from configuration
        $self->_parse_timezone();

    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_sysinfo_time

sub _parse_reboot_time {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_reboot_time\n";
    }

    # Calculate hardware reboot time
    # The ProxySG Appliance was last hardware rebooted 1 days, 5 hours, 55 minutes, and 0 seconds ago.
    if (defined($self->{'sgos_sysinfo_section'}{'Version Information'})) {
        ($self->{'hardware_reboot'}) = $self->{'sgos_sysinfo_section'}{'Version Information'} =~ m/The ProxySG Appliance was last hardware rebooted (.*)$/m;
        ($self->{'hardware_reboot_day'}) =
            $self->{'hardware_reboot'} =~ m/(\d+) day/;
        if (!defined($self->{'hardware_reboot_day'})) {
            $self->{'hardware_reboot_day'} = 0;
        }
        ($self->{'hardware_reboot_hour'}) =
            $self->{'hardware_reboot'} =~ m/(\d+) hour/;
        if (!defined($self->{'hardware_reboot_hour'})) {
            $self->{'hardware_reboot_hour'} = 0;
        }
        ($self->{'hardware_reboot_minute'}) =
            $self->{'hardware_reboot'} =~ m/(\d+) minute/;
        if (!defined($self->{'hardware_reboot_minute'})) {
            $self->{'hardware_reboot_minute'} = 0;
        }
        ($self->{'hardware_reboot_second'}) =
            $self->{'hardware_reboot'} =~ m/(\d+) second/;
        if (!defined($self->{'hardware_reboot_second'})) {
            $self->{'hardware_reboot_second'} = 0;
        }
        $self->{'hardware_reboot_seconds_total'} =
            ($self->{'hardware_reboot_day'} * $HOURS_PER_DAY * $SECONDS_PER_HOUR) +
            ($self->{'hardware_reboot_hour'} * $SECONDS_PER_HOUR) +
            ($self->{'hardware_reboot_minute'} * 60) +
            $self->{'hardware_reboot_second'};

        # The ProxySG Appliance was last software rebooted 1 days, 5 hours, 55 minutes, and 1 seconds ago.

        ($self->{'software_reboot'}) = $self->{'sgos_sysinfo_section'}{'Version Information'} =~ m/The ProxySG Appliance was last software rebooted (.*)$/m;
        ($self->{'software_reboot_day'}) =
            $self->{'software_reboot'} =~ m/(\d+) day/;
        if (!defined($self->{'software_reboot_day'})) {
            $self->{'software_reboot_day'} = 0;
        }
        ($self->{'software_reboot_hour'}) =
            $self->{'software_reboot'} =~ m/(\d+) hour/;
        if (!defined($self->{'software_reboot_hour'})) {
            $self->{'software_reboot_hour'} = 0;
        }
        ($self->{'software_reboot_minute'}) =
            $self->{'software_reboot'} =~ m/(\d+) minute/;
        if (!defined($self->{'software_reboot_minute'})) {
            $self->{'software_reboot_minute'} = 0;
        }
        ($self->{'software_reboot_second'}) =
            $self->{'software_reboot'} =~ m/(\d+) second/;
        if (!defined($self->{'software_reboot_second'})) {
            $self->{'software_reboot_second'} = 0;
        }
        $self->{'software_reboot_seconds_total'} =
            ($self->{'software_reboot_day'} * $HOURS_PER_DAY * $SECONDS_PER_HOUR) +
            ($self->{'software_reboot_hour'} * $SECONDS_PER_HOUR) +
            ($self->{'software_reboot_minute'} * 60) +
            $self->{'software_reboot_second'};
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_reboot_time

sub _parse_sgos_releaseid {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_sgos_releaseid\n";
    }

    # parse  SGOS version, SGOS releaseid, and serial number
    # SGOS release ID
    # Release id: 41580
    if (defined($self->{'sgos_sysinfo_section'}{'Version Information'})) {
        ($self->{'sgosreleaseid'}) = $self->{'sgos_sysinfo_section'}{'Version Information'} =~ m/^Release id:\s(\d+)/im;
    }
    return undef;
} ## end sub _parse_sgos_releaseid

sub _parse_sgos_version {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_sgos_version\n";
    }

    # parse  SGOS version, SGOS releaseid, and serial number
    if ($self->{'sgos_sysinfo_section'}{'Version Information'} && $self->{'_debuglevel'} > 0) {
        print "VERSION INFO SECTION:\n";
        print $self->{'sgos_sysinfo_section'}{'Version Information'} . "\n";
    }

    # SGOS version
    # #Version Information
    # URL_Path /SYSINFO/Version
    # Blue Coat Systems, Inc., ProxySG Appliance Version Information
    # Version: SGOS 4.2.10.1
    #
    if (defined($self->{'sgos_sysinfo_section'}{'Version Information'})) {
        ($self->{'sgosversion'}) = $self->{'sgos_sysinfo_section'}{'Version Information'} =~ m/^\s*Version:\sSGOS\s(\d+\.\d+\.\d+\.\d+)/im;
        if (defined($self->{'sgosversion'})) {
            ($self->{'sgosmajorversion'}) = $self->{'sgosversion'} =~ m/^(\d+\.\d+)/;
        }

        if ($self->{'_debuglevel'} > 0) {
            print "SGOS version = $self->{'sgosversion'}\n";
            print "SGOS major version = $self->{'sgosmajorversion'}\n";
        }
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_sgos_version

sub _parse_pac_file {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_pac_file\n";
    }

    # inline accelerated-pac end-616706434-inline
    # end-616706434-inline
    if (defined($self->{'sgos_sysinfo_section'}{'Software Configuration'})) {
        if ($self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/inline accelerated-pac/) {
            my $marker;
            ($marker) = $self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/inline accelerated-pac (end-\d+-inline)/;

            # IOW, we don't have a pac file
            #
            if (!defined($marker)) {
                return undef;
            }
            ($self->{'config'}->{'pac-file'}) = $self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/inline accelerated-pac $marker(.*?)$marker$/ism;
            if ($self->{'_debuglevel'} > 0) {
                print "pacfile=$self->{'config'}->{'pac-file'}\n";
            }
        } ## end if ($self->{'sgos_sysinfo_section'...})
    } ## end if (defined($self->{'sgos_sysinfo_section'...}))
    return undef;
} ## end sub _parse_pac_file

sub _parse_wccp_config {
    my $self = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "_parse_wccp_config\n";
    }

    # inline wccp-settings end-616502376-inline
    # end-616706434-inline
    if ($self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/inline wccp-settings/) {
        my $marker;
        ($marker) = $self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/inline wccp-settings (end-\d+-inline)/;

        # IOW, we don't have a pac file
        if (!defined($marker)) {
            return undef;
        }
        ($self->{'config'}->{'wccp-settings'}->{'raw'}) =
            $self->{'sgos_sysinfo_section'}{'Software Configuration'} =~ m/inline wccp-settings $marker(.*?)$marker$/ism;
        ($self->{'config'}->{'wccp-settings'}->{'enabled'}) = $self->{'config'}->{'wccp-settings'}->{'raw'} =~ m/^wccp ((ena|dis)able)$/im;
        if (defined($self->{'config'}->{'wccp-settings'}->{'enabled'})) {
            if ($self->{'config'}->{'wccp-settings'}->{'enabled'} =~ m/enable/i) {
                $self->{'config'}->{'wccp-settings'}->{'enabled'} = 1;
            }
            if ($self->{'config'}->{'wccp-settings'}->{'enabled'} =~ m/disable/i) {
                $self->{'config'}->{'wccp-settings'}->{'enabled'} = 0;
            }
        } ## end if (defined($self->{'config'...}))
        ($self->{'config'}->{'wccp-settings'}->{'version'}) = $self->{'config'}->{'wccp-settings'}->{'raw'} =~ m/^wccp version (\d+)$/im;

        my @wccpchunks;
        (@wccpchunks) = $self->{'config'}->{'wccp-settings'}->{'raw'} =~ m/(^service-group \d+.*?end$)+/ismg;
        #
        #service-flags ports-defined
        #ports 80 443 0 0 0 0 0 0
        #
        foreach my $chunk (@wccpchunks) {
            my $w;
            ($w->{'service-group'})   = $chunk =~ m/service-group (\d+)/i;
            ($w->{'forwarding-type'}) = $chunk =~ m/forwarding-type (.*?)$/im;
            ($w->{'multicast-ttl'})   = $chunk =~ m/multicast-ttl(.*?)$/im;
            ($w->{'priority'})        = $chunk =~ m/priority (\d+)/im;
            ($w->{'protocol'})        = $chunk =~ m/protocol (\d+)/im;
            ($w->{'router-affinity'}) = $chunk =~ m/router-affinity (.*?)$/im;
            ($w->{'interface'})       = $chunk =~ m/interface (.*?)$/im;

            #($w->{'service-flags'})   = $chunk =~ m/service-flags (.*?)$/im;
            (@{$w->{'service-flags'}}) = $chunk =~ m/service-flags (.*?)$/igm;
            my ($ports) = $chunk =~ m/ports (.*)$/igm;
            if (scalar($ports)) {
                (@{$w->{'ports'}}) = split(/\s+/, $ports);
            }
            else {
                (@{$w->{'ports'}}) = undef;
            }

            ($w->{'primary-hash-weight'}) = $chunk =~ m/primary-hash-weight (.*?)$/im;
            (@{$w->{'home-router'}})      = $chunk =~ m/home-router (.*?)$/igm;
            ($w->{'assignment-type'})     = $chunk =~ m/assignment-type (.*?)$/im;
            ($w->{'mask-scheme'})         = $chunk =~ m/mask-scheme (.*?)$/im;
            ($w->{'mask-value'})          = $chunk =~ m/mask-value (.*?)$/im;

            # hacky
            foreach my $key (keys %{$w}) {
                if (defined $w->{$key}) {
                    $w->{$key} =~ s/^\s+//;
                    $w->{$key} =~ s/\s+$//;
                }
            } ## end foreach my $key (keys %{$w})
            push @{$self->{'config'}->{'wccp-settings'}->{'service-groups'}}, $w;
        } ## end foreach my $chunk (@wccpchunks)

        if ($self->{'_debuglevel'} > 0) {
            print "wccp-settings=$self->{'config'}->{'wccp-settings'}->{'raw'}\n";
        }
    } ## end if ($self->{'sgos_sysinfo_section'...})
    return undef;
} ## end sub _parse_wccp_config

=head2 send_command

Takes one parameter: a scalar that contains configuration commands to send to the appliance.
This command is executed in configuration mode.

    my $output = $bc->send_command('show version');
    # or
    my $commands =qq{
        int 0:0
        speed 100
    };
    my $output = $bc->send_command($commands);

=cut

sub send_command {
    my $self    = shift;
    my $command = shift;
    if ($self->{'_debuglevel'} > 0) {
        print "begin sub:send_command\n";
        print "command=$command\n";
    }
    if (!defined($self->{'_lwpua'})) {
        $self->_create_ua();
    }
    my $request = POST $self->{'_applianceurlbase'} . $_URL{'send_command'},
        Content_Type => 'form-data',
        'Content'    => ['file' => $command];
    $request->authorization_basic($self->{'_applianceusername'}, $self->{'_appliancepassword'});
    my $response = $self->{'_lwpua'}->request($request);
    my $content;
    if ($response->is_success) {
        $content = $response->content;
    }
    else {
        croak 'error';
    }
    $content =~ s/\r//ig;
    return $content;
} ## end sub send_command

=head2 Other Data

Other data that is directly accessible in the object:

    Appliance Name:   $bc->{'appliance-name'}
    Model Number:     $bc->{'modelnumber'}
    Serial Number:    $bc->{'serialnumber'}
    SGOS Version:     $bc->{'sgosversion'}
    Release ID:       $bc->{'sgosreleaseid'}
    Default Gateway:  $bc->{'ip-default-gateway'}
    Sysinfo Time:     $bc->{'sysinfotime'}
    Accelerator Info: $bc->{'ssl-accelerator'}

    You can retrieve a list of sections as follows:
    my @sectionlist = $bc->get_section_list();

    You can retrieve a section as follows:
    my $softwareconfig = $bc->get_section('Software Configuration');

    Different sections that can be retrieved are:
        ADN Compression Statistics
        ADN Configuration
        ADN Node Info
        ADN Sizing Peers
        ADN Sizing Statistics
        ADN Tunnel Statistics
        AOL IM Statistics
        Access Log Objects
        Access Log Statistics
        Authenticator Memory Statistics
        Authenticator Realm Statistics
        Authenticator Total Realm Statistics
        CCM Configuration
        CCM Statistics
        CIFS Memory Usage
        CIFS Statistics
        CPU Monitor
        CacheEngine Main
        Configuration Change Events
        Content Filter Status
        Core Image
        Crypto Statistics
        DNS Cache Statistics
        DNS Query Statistics
        Disk 1
            ... and up to Disk 16, in some cases
        Endpoint Mapper Internal Statistics
        Endpoint Mapper Statistics
        Endpoint Mapper database contents
        FTP Statistics
        Forwarding Settings
        Forwarding Statistics Per IP
        Forwarding Summary Statistics
        Forwarding health check settings
        Forwarding health check statistics
        HTTP Configuration
        HTTP Main
        HTTP Requests
        HTTP Responses
        Hardware Information
        Hardware sensors
        Health Monitor
        Health check entries
        Health check statistics
        ICP Hosts
        ICP Settings
        ICP Statistics
        IM Configuration
        Kernel Statistics
        Licensing Statistics
        MAPI Client Statistics
        MAPI Conversation Client Errors
        MAPI Conversation Other Errors
        MAPI Conversation Server Errors
        MAPI Errors
        MAPI Internal Statistics
        MAPI Server Statistics
        MAPI Statistics
        MMS Configuration
        MMS General
        MMS Statistics
        MMS Streaming Statistics
        MSN IM Statistics
        OPP Services
        OPP Statistics
        P2P Statistics
        Persistent Statistics
        Policy
        Policy Statistics
        Priority 1 Events
        Quicktime Configuration
        Quicktime Statistics
        RIP Statistics
        Real Configuration
        Real Statistics
        Refresh Statistics
        SCSI Disk Statistics
        SOCKS Gateways Settings
        SOCKS Gateways Statistics
        SOCKS Proxy Statistics
        SSL Proxy Certificate Cache
        SSL Statistics
        Security processor Statistics
        Server Side persistent connections
        Services Management Statistics
        Services Per-service Statistics
        Services Proxy Statistics
        Software Configuration
        System Memory Statistics
        TCP/IP ARP Information
        TCP/IP Listening list
        TCP/IP Malloc Information
        TCP/IP Routing Table
        TCP/IP Statistics
        Threshold Monitor Statistics
        Version Information
        WCCP Configuration
        WCCP Statistics
        Yahoo IM Statistics


    The details for interface 0:0 are stored here:
        IP address:   $bc->{'interface'}{'0:0'}{'ip'} 
        Netmask:      $bc->{'interface'}{'0:0'}{'netmask'} 
        MAC address:  $bc->{'interface'}{'0:0'}{'mac'} 
        Link status:  $bc->{'interface'}{'0:0'}{'linkstatus'} 
        Capabilities: $bc->{'interface'}{'0:0'}{'capabilities'} 

    You can retrieve the interface names like this:
        my @interfaces = keys %{$bc->{'interface'}};

    The route table can be retrieved as follows:
        $bc->{'sgos_sysinfo_section'}{'TCP/IP Routing Table'}

    The static route table can be retrieved as follows:
        $bc->{'static-route-table'}

    The WCCP configuration can be retrieved as follows:
        $bc->{'sgos_sysinfo_section'}{'WCCP Configuration'}


=cut

=head1 DEPENDENCIES

This module requires some other modules.

Date::Parse
LWP::UserAgent > 6.00 (requires the ssl_opts in newer versions)
LWP::Protocol::https
HTTP::Request

TODO: FIXME


=head1 AUTHOR

Matthew Lange E<lt>mmlange@cpan.orgE<gt>

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=BlueCoat-SGOS>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc BlueCoat::SGOS


You can also look for information at:

=over 4

=item * 

L<RT: CPAN's request tracker|http://rt.cpan.org/NoAuth/Bugs.html?Dist=BlueCoat-SGOS>

=item * 

L<AnnoCPAN: Annotated CPAN documentation|http://annocpan.org/dist/BlueCoat-SGOS>

=item * 

L<CPAN Ratings|http://cpanratings.perl.org/d/BlueCoat-SGOS>

=item * 

L<CPAN|http://search.cpan.org/dist/BlueCoat-SGOS/>

=back


=head1 LICENSE AND COPYRIGHT

Copyright (C) 2008-2013 Matthew Lange

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License version 2 as 
published by the Free Software Foundation.

=cut

1;    # End of BlueCoat::SGOS

