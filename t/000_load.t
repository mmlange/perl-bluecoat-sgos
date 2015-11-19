#!perl -T
#
#
#
use strict;
use BlueCoat::SGOS;
use Test::More;

plan tests => 1;

note("Testing BlueCoat::SGOS $BlueCoat::SGOS::VERSION, Perl $], $^X");
use_ok('BlueCoat::SGOS');

