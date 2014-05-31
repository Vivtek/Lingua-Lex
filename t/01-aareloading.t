#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Lingua::Lex;
use File::stat;
use Data::Dumper;

plan tests => 2;

my $lex = Lingua::Lex->new (db => 't/test.sqlt');
$lex->reload('t/testlex.txt');

my $dbs = stat('t/test.sqlt');
my $fs = stat('t/testlex.txt');
ok ($fs->mtime < $dbs->mtime);

my $tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
