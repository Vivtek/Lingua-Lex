#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Lingua::Lex;
use DBI qw(:sql_types);
use Data::Dumper;

#plan tests => 1;

my $dbh = DBI->connect('dbi:SQLite:dbname=t/test.sqlt', '', '', {sqlite_unicode => 1})
                or die "Couldn't connect to database: " . DBI->errstr;
                
my $lex = Lingua::Lex->new (dbh => $dbh, table=>['words'], ngrams_on=>'yes');
$lex->stop_on_pos('art');

$lex->word('rot');
$lex->word('eine');
$lex->word('rot');
$lex->word('rot');
$lex->word('rot');
$lex->word('eine');
$lex->word('rot');
$lex->word('rot');
$lex->word('eine');
$lex->word('rot');
$lex->word('rot');
$lex->word('eine');
$lex->word('rot');
$lex->word('rot');
$lex->word('blargh');

my $unk = $lex->stats('unknown');
is (ref($unk), 'HASH');
is ($unk->{'blargh'}, 1);

my $words = $lex->stats('words');
is (ref($words), 'HASH');
is ($words->{eine}, 4);
is ($words->{rot}, 10);
is ($words->{blargh}, 1);

my $ngrams = $lex->stats('ngrams');
is (ref($ngrams), 'HASH');
is ($ngrams->{'rot blargh'}, 1);
is ($ngrams->{'rot rot'}, 5);
is ($ngrams->{'rot rot blargh'}, 1);
is ($ngrams->{'rot rot rot'}, 1);

$ngrams = $lex->normalize_ngrams;
is (ref($words), 'HASH');
is ($ngrams->{'rot rot'}, 2);
is ($ngrams->{'rot rot blargh'}, 1);
is ($ngrams->{'rot rot rot'}, 1);




done_testing();
