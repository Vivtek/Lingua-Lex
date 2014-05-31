#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Lingua::Lex;
use DBI qw(:sql_types);

#plan tests => 1;

my $dbh = DBI->connect('dbi:SQLite:dbname=t/test.sqlt', '', '', {sqlite_unicode => 1})
                or die "Couldn't connect to database: " . DBI->errstr;
                
my $lex = Lingua::Lex->new (dbh => $dbh, table=>['words'], suffixes=>'suffixes');

my $tok = $lex->word('rot');
is_deeply ($tok, ['aa', 'rot']);
$tok = $lex->word('rote');
is_deeply ($tok, ['aa', 'rote', 'rot+e', 'aa+f']);
$tok = $lex->word('roter');
is_deeply ($tok, ['aa', 'roter', 'rot+er', 'aa+c']);   # This is bad German - but this is an intentionally oversimplified grammar for testing.
$tok = $lex->word('rotere');
is_deeply ($tok, ['aa', 'rotere', 'rot+er+e', 'aa+c+f']);  # Multiple suffixes are OK.


$tok = $lex->word('sachlich');
is_deeply ($tok, ['aa', 'sachlich', 'sache+lich']);  # Sache is a noun but '+lich' turns it into an adjective.


done_testing();
