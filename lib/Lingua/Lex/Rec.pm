package Lingua::Lex::Rec;

use 5.006;
use strict;
use warnings FATAL => 'all';
#use DBD::SQLite;
use Data::Dumper;
use utf8;
use Carp;

=head1 NAME

Lingua::Lex::Rec - Provides a simple recognizer for use in tokenizing

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

The L<Lingua::Lex> module itself is geared towards data-intensive lexicalization, but there are also a lot of word-like things interspersed
in normal text that, while treated like words from a grammatical point of view, are really not things you'd put in a dictionary. Things like
numbers, URLs, dates, certain kinds of ID strings, and so on, are all best represented as a lightweight regular expression recognizer.

This module makes that easy to manage in an overall lexicalization chain.

=head1 SUBROUTINES/METHODS

=head2 new (list)

Given a list of matches, strings, or coderefs, creates a recognizer that will scan them for matches or equivalence.

   use Lingua::Lex::Rec;
   my $lex = Lingua::Lex::Rec->new (['NUM', qr/\d+/]);
   my $tok = $lex->word('3');
   # -> ['NUM', '3']
   $tok = $lex->word('word');
   # -> undef

Any parentheses within the match will cause additional items to be returned in the token.
A non-regex-quoted string will simply be checked for equivalence.

There are also several standard patterns that can be interspersed by name, so:

   my $lex = Lingua::Lex::Rec-> ('NUM', 'URL', ['YES', 'yes']);
   my $tok = $lex->word('yes');
   # -> ['YES', 'yes']
   $tok = $lex->word('YES');
   # -> undef (use a regex if you need case-insensitivity)
   $tok = $lex->word('98.2');
   # -> ['NUM', '98.2', '.']
   $tok = $lex->word('98,3');
   # -> ['NUM', '98,3', ',']
   
=cut

sub new {
   my $self = bless [], shift;
   my $r = shift @_;
   while (defined $r) {
      my $rf = ref($r);
      if (!$rf) {
         unshift @_, $self->standard_recognizer($r);
      } elsif ($rf eq 'ARRAY') {
         push @{$self}, $r;
      } else {
         croak "Trying to recognize something that's not a name or an arrayref";
      }
      $r = shift @_;
   }
   $self;
}

=head2 word

Like a regular lexer, a recognizer is also passed one word at a time for matching. Its matchers are called in succession, and if one
matches no more are called.

=cut

sub word {
    my ($self, $word) = @_;
    foreach my $r (@{$self}) {
       my ($name, @matches) = @{$r};
       foreach my $match (@matches) {
          my $rf = ref $match;
          if (!$rf) {
             return [$name, $word] if $word eq $match;
          } elsif ($rf eq 'Regexp') {
             #print STDERR "matching $word against $match\n";
             next unless $word =~ /^$match$/;
             my @ret = ($name, $word);
             if (defined $1) {
                @ret = (@ret, ($word =~ /^$match$/)); # I can't see any way to avoid calling this twice.
             }
             return \@ret;
          } elsif ($rf eq 'CODE') {
             my $return = $match->($word);
             return $return if $return;
          }
       }
    }
    return undef;
}

=head2 standard_recognizer, grouped_recognizers

Looks up a standard recognizer by name.  The results of this are inserted into the list in the same point the name appeared, and a name
can also refer to a specific group of other named or non-named recognizers.  For example, 'DATE' can refer to a 'DOTDATE' or a 'SLASHDATE'.

=cut

sub standard_recognizer {
   my $self = shift;
   my $r = shift;
   
   {
      'COPY' => ['COPY', '©'],
      'LSEC' => ['LSEC', '§', '§§'],
      'NUM'  => ['NUM', qr/\d+/,
                        qr/\d+([.,])\d+/,
                        qr/\d[\d.]*/],
      'DATE' => ['DATE', \&date_recognizer],
      'URL'  => ['URL', \&url_recognizer],
      'ID'   => ['ID',  qr/[a-z][a-z0-9_]*[0-9_][a-z0-9_]*/i],
      'SPLIT' => ['SPLIT', \&punctuation_splitter],
   }->{$r} || $self->grouped_recognizers($r);
}

sub grouped_recognizers {
   my $self = shift;
   my $r = shift;
   
   my $group = {
      'SPECIALS' => ['COPY', 'LSEC'],
   }->{$r} || croak "Unknown recognizer $r";
   @$group;
}

=head2 date_recognizer

Given a string, decide whether it's a plausible date or not, and return a token if so. Also available as a standard recognizer
named 'DATE'.

The heuristics I'm using are that a 4-digit year should be between 1500 and 3000, and can be at the beginning (2014.01.01) or the
end (01.01.2014). There's no good way without context to know whether the month or the day comes first, so we don't even try;
the idea here is to make a good guess more or less as I would when looking at a document. A dotted date will probably end up
miscategorized as a number in some cases, and a slashed date will generally be recognized correctly.

This will also recognize times as x:xx, xx:xx, xx:xx:xx, and dashed time ranges xx:xx-xx:xx, all with a token type of TIME.

=cut

sub date_recognizer {
   my $s = shift;
   
   return ['DATE', $s] if $s =~ /^\d+\/\d+\/\d+$/;
   return ['TIME', $s] if $s =~ /^\d+:\d\d(:\d\d)?$/;
   return ['TIME', $s] if $s =~ /^\d+:\d\d(:\d\d)?-\d+:\d\d(:\d\d)?$/;
   
   if ($s =~ /^(\d+)\.(\d+)\.(\d+)$/ || $s =~ /^(\d+)-(\d+)-(\d+)$/) {
      return ['DATE', $s] if $1 < 32 and $2 < 32 and $3 >= 1500 and $3 <= 3000;
      return ['DATE', $s] if $3 < 32 and $2 < 32 and $1 >= 1500 and $1 <= 3000;
   }
   
   return undef;
}

=head2 url_recognizer

The "URL recognizer" will actually recognize not only URLs in http:... form, but also email addresses, and will make an attempt to
judge anything obviously DNS-like, in that it looks like something.something.something, where the final something is a valid TLD
according to L<Net::Domain::TLD> if it's installed, or .com, .org, .net, .gov, .mil, or two letters if not.

   http://my.actual.url/this?query => ['URL', 'http://my.actual.url/this?query']
   michael@vivtek.com              => ['EMAIL', 'michael@vivtek.com']
   www.mybiddingsite.de            => ['URL', 'www.mybiddingsite.de']
   
Obviously, no effort at all will be made to check the technical correctness of any URL or email address here; we're just interested
in making a rough guess as to whether a "word" (meaning a bunch of letters together without spaces) in a linguistic text
"looks like" a URL or email address.  The further process is responsible for deciding what to do about these entities once
they're found.

=cut

sub url_recognizer {
   my $s = shift;
   return ['URL', $s] if $s =~ /^[a-z]+:\/\/.+$/;
   return ['URL', $s] if $s =~ /^mailto:[a-z]/;
   return ['EMAIL', $s] if $s =~ /^[^@]+@[^@]+\..+$/;
   return ['URL', $s] if $s =~ /^[a-z0-9.]+\.([a-z]+)/ and _valid_tld($1);
   return undef;
}
sub _valid_tld {
   my $tld = shift;
   eval {
      require Net::Domain::TLD;
      Net::Domain::TLD->import('tld_exists');
      return tld_exists($tld);
   } or do {
      return 1 if length($tld) eq 2;
      {
         'mil' => 1,
         'org' => 1,
         'com' => 1,
         'net' => 1,
         'gov' => 1,
         'edu' => 1,
         'info' => 1,
      }->{$tld};
   }
}

=head2 punctuation_splitter

A splitter is any lexical component that returns "SPLIT" as a token type; Lingua::Tok will take the rest of that token and unpop its components,
thereby treating them as newly tokenized words before proceeding with the tokenization process. Lingua::Lex::Cascade will also not consider split
tokens in its n-gram statistics.

Note that a splitter is generally called I<after> the main lexica have had their chance to recognize a word - otherwise we'd never be able to
recognize "and/or" or "e-mail" as words.

=cut

sub punctuation_splitter {
   my $s = shift;
   my @pieces = split /([\p{Punct}=])/, $s;
   return undef if @pieces == 1;
   return ['SPLIT', grep { $_ ne '' } @pieces];
}
   

=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-lingua-lex at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Lingua-Lex>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lingua::Lex::Rec


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Lingua-Lex>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Lingua-Lex>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Lingua-Lex>

=item * Search CPAN

L<http://search.cpan.org/dist/Lingua-Lex/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2014 Michael Roberts.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of Lingua::Lex::Rec
