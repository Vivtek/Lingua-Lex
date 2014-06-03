#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 2;

BEGIN {
    use_ok( 'Lingua::Lex' ) || print "Bail out on Lingua::Lex!\n";
    use_ok( 'Lingua::Lex::Rec' ) || print "Bail out on Lingua::Lex::Rec!\n";
}

diag( "Testing Lingua::Lex $Lingua::Lex::VERSION, Perl $], $^X" );
