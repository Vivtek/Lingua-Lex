#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Lingua::Lex::Rec;
use Data::Dumper;
use utf8;

#plan tests => 1;

my $lex = Lingua::Lex::Rec->new(['YES', 'yes']);
my $tok = $lex->word('yes');
is_deeply ($tok, ['YES', 'yes']);
$tok = $lex->word('no');
ok (not defined $tok);


done_testing();
