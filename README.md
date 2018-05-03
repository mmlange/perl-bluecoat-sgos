BlueCoat::SGOS
==============

This is the BlueCoat::SGOS module.  It seeks to parse
the configuration of a Blue Coat SGOS device.  It was
formerly Net::BlueCoat::SGOS.

Current build status:
[![Build Status](https://travis-ci.org/mmlange/perl-bluecoat-sgos.svg?branch=master)](https://travis-ci.org/mmlange/perl-bluecoat-sgos)



**WARNING**
This is currently beta-quality software.  This means:
    * there could be bugs
    * the API is not stable

It has been tested on a handful of sysinfo files with great
success.

Because sysinfo data is semi-unstructured, this module
reads everything into memory and splits it apart
at each "delimiter" section.  This is inefficient
and slow.


INSTALLATION

BlueCoat::SGOS uses well-tested and widely-used CPAN modules, so 
installation should be as simple as:
    perl Build.PL
    ./Build
    ./Build test
    ./Build install


SUPPORT AND DOCUMENTATION

After installing, you can find documentation for this module with the
perldoc command as follows:

    perldoc BlueCoat::SGOS

You can also find more information here:
    * RT, CPAN's request tracker
        http://rt.cpan.org/NoAuth/Bugs.html?Dist=BlueCoat-SGOS
    * AnnoCPAN, Annotated CPAN documentation
        http://annocpan.org/dist/BlueCoat-SGOS
    * CPAN Ratings
        http://cpanratings.perl.org/d/BlueCoat-SGOS
    * CPAN Search
        http://search.cpan.org/dist/BlueCoat-SGOS/

SOURCE
The source is located here: http://github.com/mmlange/perl-bluecoat/sgos


AUTHOR
Matthew Lange <mmlange@cpan.org>


LICENSE AND COPYRIGHT
Copyright (c) 2008-2015 Matthew Lange

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published
by the Free Software Foundation.
