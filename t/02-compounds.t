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
                
my $lex = Lingua::Lex->new (dbh => $dbh, table=>['words'], starts=>'starts');

my $tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
$tok = $lex->word('Eine');
is_deeply ($tok, ['art', 'Eine']);
$tok = $lex->word('kleine');
is_deeply ($tok, ['aa', 'kleine']);
$tok = $lex->word('Nachtmusik');
is_deeply ($tok, ['n', 'Nachtmusik', 'Nacht+musik']);

$tok = $lex->word('Nachtigall');
is_deeply ($tok, ['?', 'Nachtigall']); # We don't find compounds just because we know the first part.


done_testing();
