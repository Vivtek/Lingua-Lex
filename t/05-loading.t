#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Lingua::Lex;
use DBI qw(:sql_types);
use Data::Dumper;
use utf8;

#plan tests => 1;

my $lex = Lingua::Lex->new (db => 't/loadtest.sqlt');

$lex->load(string => <<'EOF');
words: < t/extra_words.txt
eine        art
kleine/a    aa
rot/A       aa
Musik       n
Sache       n
nopos

starts: cstarts
Nacht

suffixes:
A: general adjective stuff
aa  .       .   r   -f-n+m  a
aa  [^e]    .   e   -m-n+f  a
aa  .       .   er  +c      A

a: masculine -er for e-ending words
aa  .       e   er  -f-n+m  .

L: -lich to test pos changes
n   .       e   lich    aa  A

EOF

my $tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
$tok = $lex->word('nixda');
is_deeply ($tok, ['?', 'nixda']);
$tok = $lex->word('Nachtmusik');
is_deeply ($tok, ['n', 'Nachtmusik', 'Nacht+musik']);
$tok = $lex->word('grün');
is_deeply ($tok, ['aa', 'grün']);
$tok = $lex->word('sachlich');
is_deeply ($tok, ['aa', 'sachlich', 'sache+lich']);  # Sache is a noun but '+lich' turns it into an adjective.

undef $lex;
unlink 't/loadtest.sqlt';

$lex = Lingua::Lex->new (db => 't/filetest.sqlt');
$lex->load(file=>'t/load_lex.txt');


$tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
$tok = $lex->word('Nachtmusik');
is_deeply ($tok, ['n', 'Nachtmusik', 'Nacht+musik']);
$tok = $lex->word('grün');
is_deeply ($tok, ['aa', 'grün']);
$tok = $lex->word('sachlich');
is_deeply ($tok, ['aa', 'sachlich', 'sache+lich']);  # Sache is a noun but '+lich' turns it into an adjective.

undef $lex;
unlink 't/filetest.sqlt';

$lex = Lingua::Lex->new (db => 't/datatest.sqlt');
$lex->load(file=>\*DATA);


$tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
$tok = $lex->word('Nachtmusik');
is_deeply ($tok, ['n', 'Nachtmusik', 'Nacht+musik']);
$tok = $lex->word('grün');
is_deeply ($tok, ['aa', 'grün']);
$tok = $lex->word('sachlich');
is_deeply ($tok, ['aa', 'sachlich', 'sache+lich']);  # Sache is a noun but '+lich' turns it into an adjective.

undef $lex;
unlink 't/datatest.sqlt' or die $!;


$lex = Lingua::Lex->new (db => 't/dirtest.sqlt');
$lex->load(directory=>'t/testdict');


$tok = $lex->word('eine');
is_deeply ($tok, ['art', 'eine']);
$tok = $lex->word('Nachtmusik');
is_deeply ($tok, ['n', 'Nachtmusik', 'Nacht+musik']);
$tok = $lex->word('grün');
is_deeply ($tok, ['aa', 'grün']);
$tok = $lex->word('sachlich');
is_deeply ($tok, ['aa', 'sachlich', 'sache+lich']);  # Sache is a noun but '+lich' turns it into an adjective.

undef $lex;
unlink 't/dirtest.sqlt';


done_testing();


__DATA__
words: < t/extra_words.txt
eine        art
kleine/a    aa
rot/A       aa
Musik       n
Sache       n
nopos

starts: cstarts
Nacht

suffixes:
A: general adjective stuff
aa  .       .   r   -f-n+m  a
aa  [^e]    .   e   -m-n+f  a
aa  .       .   er  +c      A

a: masculine -er for e-ending words
aa  .       e   er  -f-n+m  .

L: -lich to test pos changes
n   .       e   lich    aa  A

