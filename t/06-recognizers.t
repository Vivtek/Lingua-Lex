#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use Lingua::Lex::Rec;
use Data::Dumper;
use utf8;

#plan tests => 1;

# Plain strings.
my $lex = Lingua::Lex::Rec->new(['YES', 'yes']);
my $tok = $lex->word('yes');
is_deeply ($tok, ['YES', 'yes']);
$tok = $lex->word('no');
ok (not defined $tok);

# Standard recognizers.
$lex = Lingua::Lex::Rec->new('COPY');
$tok = $lex->word('©');
is_deeply ($tok, ['COPY', '©']);
$tok = $lex->word('yes');
ok (not defined $tok);

$lex = Lingua::Lex::Rec->new('LSEC');
$tok = $lex->word('§');
is_deeply ($tok, ['LSEC', '§']);
$tok = $lex->word('§§');
is_deeply ($tok, ['LSEC', '§§']);

# Grouped standard recognizers.
$lex = Lingua::Lex::Rec->new('SPECIALS');
$tok = $lex->word('©');
is_deeply ($tok, ['COPY', '©']);
$tok = $lex->word('§');
is_deeply ($tok, ['LSEC', '§']);
$tok = $lex->word('§§');
is_deeply ($tok, ['LSEC', '§§']);
$tok = $lex->word('yes');
ok (not defined $tok);

# Match recognizers.
$lex = Lingua::Lex::Rec->new('NUM');
$tok = $lex->word('99.9');
is_deeply ($tok, ['NUM', '99.9', '.']);
$tok = $lex->word('99,9');
is_deeply ($tok, ['NUM', '99,9', ',']);
$tok = $lex->word('99');
is_deeply ($tok, ['NUM', '99']);
$tok = $lex->word('10.0.1');
is_deeply ($tok, ['NUM', '10.0.1']);
$tok = $lex->word('99y');
ok (not defined $tok);

# Code recognizers.
$lex = Lingua::Lex::Rec->new('DATE');
$tok = $lex->word('1/1/2000');
is_deeply ($tok, ['DATE', '1/1/2000']);
$tok = $lex->word('2004.03.04');
is_deeply ($tok, ['DATE', '2004.03.04']);
$tok = $lex->word('3.04.1989');
is_deeply ($tok, ['DATE', '3.04.1989']);
$tok = $lex->word('1/1');
ok (not defined $tok);
$tok = $lex->word('4.03.1');
ok (not defined $tok);

# URLs
$lex = Lingua::Lex::Rec->new('URL');
$tok = $lex->word('http://cpan.org');
is_deeply ($tok, ['URL', 'http://cpan.org']);
$tok = $lex->word('michael@vivtek.com');
is_deeply ($tok, ['EMAIL', 'michael@vivtek.com']);
$tok = $lex->word('mailto:michael@vivtek.com');
is_deeply ($tok, ['URL', 'mailto:michael@vivtek.com']);
$tok = $lex->word('www.mysite.com');
is_deeply ($tok, ['URL', 'www.mysite.com']);
$tok = $lex->word('something.else');
ok (not defined $tok);

done_testing();
