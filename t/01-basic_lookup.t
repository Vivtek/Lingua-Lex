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
                
my $lex = Lingua::Lex->new (dbh => $dbh, table=>['words']);

my $tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
$tok = $lex->word('Eine');
is_deeply ($tok, ['art', 'Eine']);
$tok = $lex->word('kleine');
is_deeply ($tok, ['aa', 'kleine']);
$tok = $lex->word('Musik');
is_deeply ($tok, ['n', 'Musik']);

# Words not found have pos '?'
$tok = $lex->word('nixda');
is_deeply ($tok, ['?', 'nixda']);

# Words found without explicit pos have 'word'
$tok = $lex->word('nopos');
is_deeply ($tok, ['word', 'nopos']);

$dbh->do("drop table if exists wordlist");
$dbh->do("create table wordlist (word varchar)");
my $wordlist_insert = $dbh->prepare ("insert into wordlist values (?)");
$wordlist_insert->execute('nopos');
$wordlist_insert->execute('wordlist_word');

# Words from tables without a pos column at all also have 'word'
$lex = Lingua::Lex->new (dbh=>$dbh, table=>['wordlist']);
$tok = $lex->word('nopos');
is_deeply ($tok, ['word', 'nopos']);
$tok = $lex->word('nixda');
is_deeply ($tok, ['?', 'nixda']);

# Cascading lookups in the same database, one table to the next with different schemas
$lex = Lingua::Lex->new (dbh=>$dbh, table=>['words', 'wordlist']);
$tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
$tok = $lex->word('wordlist_word');
is_deeply ($tok, ['word', 'wordlist_word']);

# Build the lexicon from a hashref passed in
$lex = Lingua::Lex->new ({dbh => $dbh, table=>['words']});

$tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
$tok = $lex->word('Eine');
is_deeply ($tok, ['art', 'Eine']);

done_testing();
