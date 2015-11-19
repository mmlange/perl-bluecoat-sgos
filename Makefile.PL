use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    ($ExtUtils::MakeMaker::VERSION >= 6.18
        ? (MM->can('signature_target') ? (SIGN => 1) : ())
        : ()),
    NAME             => 'BlueCoat::SGOS',
    AUTHOR           => q{Matthew Lange <mmlange@cpan.org>},
    VERSION_FROM     => 'lib/BlueCoat/SGOS.pm',
    ABSTRACT_FROM    => 'lib/BlueCoat/SGOS.pm',
    MIN_PERL_VERSION => '5.6.0',
    (
        $ExtUtils::MakeMaker::VERSION >= 6.3002
        ? ('LICENSE' => 'GPL_2')
        : ()
    ),
    (
        $ExtUtils::MakeMaker::VERSION >= 6.46
        ? (
            META_MERGE => {
                'meta-spec' => {version => 2},
                'resources' => {
                    'repository' => {
                        'type' => 'git',
                        'url'  => 'https://github.com/mmlange/perl-bluecoat-sgos.git',
                        'web'  => 'https://github.com/mmlange/perl-bluecoat-sgos'
                    },
                }
            }
            )
        : ()
    ),
    PL_FILES  => {},
    PREREQ_PM => {
        'Crypt::OpenSSL::X509' => '1.804',
        'DateTime'             => '0',
        'Date::Parse'          => '0',
        'English'              => 0,
        'File::Map'            => 0,
        'HTTP::Request'        => '6.00',
        'LWP::Protocol::https' => '6.06',
        'LWP::UserAgent'       => '6.00',    # requires ssl_opts
        'Readonly'             => 0
    },
    BUILD_REQUIRES => {
        'File::Slurp'      => '9999.19',
        'TAP::Harness'     => '3.18',
        'Test::More'       => '0',
        'Test::NoWarnings' => '1.04',
    },
    dist => {
        COMPRESS => 'gzip -9f',
        SUFFIX   => 'gz',
    },
    clean => {FILES => 'Debian_CPANT* BlueCoat-SGOS-*'},
);

