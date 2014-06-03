#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Lingua::Lex;
use utf8;
use DBI qw(:sql_types);

#plan tests => 1;

my $dbh = DBI->connect('dbi:SQLite:dbname=t/test.sqlt', '', '', {sqlite_unicode => 1})
                or die "Couldn't connect to database: " . DBI->errstr;

my $lex = Lingua::Lex->new ([{rec => 'NUM'},
                             {dbh => $dbh, table=>['words']},
                            ]);

my $tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
$tok = $lex->word('Eine');
is_deeply ($tok, ['art', 'Eine']);

$tok = $lex->word('42');
is_deeply ($tok, ['NUM', '42']);

# Words not found have pos '?'
$tok = $lex->word('nixda');
is_deeply ($tok, ['?', 'nixda']);


done_testing();
