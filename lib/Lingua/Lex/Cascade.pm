package Lingua::Lex::Cascade;

use 5.006;
use strict;
use warnings FATAL => 'all';
use base 'Lingua::Lex';
use Data::Dumper;
use utf8;
use Carp;

=head1 NAME

Lingua::Lex::Cascade - Subclasses Lingua::Lex for a cascading lexicon

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

A single component lexicon is usually not enough to handle every word-like thing we throw at it. In real situations, though, we
at least normally have numbers within the text that should be recognized as such. The clean way to manage that is with a cascade.

The cascade maintains a list of component lexica that it consults one after the next. If one claims the word, that result is returned;
if not, the cascade asks the next. All else failing, it returns the unknown token.

=head1 SUBROUTINES/METHODS

=head2 new (list)

Given a list of matches, strings, or coderefs, creates a recognizer that will scan them for matches or equivalence.

   use Lingua::Lex::Cascade;
   my $lex = Lingua::Lex::Cascade->new (['NUM', qr/\d+/]);
   my $tok = $lex->word('3');
   # -> ['NUM', '3']
   $tok = $lex->word('word');
   # -> undef

Any parentheses within the match will cause additional items to be returned in the token.
A non-regex-quoted string will simply be checked for equivalence.

There are also several standard patterns that can be interspersed by name, so:

   my $lex = Lingua::Lex::Cascade-> ('NUM', 'URL', ['YES', 'yes']);
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
    my $class = shift;
    my $self = bless {cascade => []}, $class;

    $self->{stop_pos} = {};
    foreach my $c (@_) {
        my $r = ref $c;
        if ($r eq 'HASH') {
            push @{$self->{cascade}}, Lingua::Lex->new ($c);
        } else {
            push @{$self->{cascade}}, $c;
            $self->stop_on_pos($c->default_stoppos);
        }
    }
    $self->restart;
    $self;
}

=head2 word

Like a regular lexer, a recognizer is also passed one word at a time for matching. Its matchers are called in succession, and if one
matches no more are called.

=cut

sub word {
    my $self = shift;
    my $word = shift;
    my $internal = shift;
    
    $self->{stats}->{count}++ unless $internal;
    $self->{words}->{$word}++ unless $internal;
    return $self->_returnval ($self->{cache}->{$word}, $internal) if defined $self->{cache}->{$word}; # Caching will hit twice for upper/lower case

    foreach my $c (@{$self->{cascade}}) {
        my $return = $c->word($word, $internal);
        next unless defined $return;
        next if $return->[0] eq '?';
        return $self->_returnval ($return, $internal);
    }

    #$self->status_message ("$word is unknown.\n");
    $self->{nonwords}->{$word} = 1 if $internal;
    $self->{stats}->{ucount}++ unless $internal;
    $self->{unknown}->{$word}++ unless $internal;
    $self->_handle_ngrams($word) unless $internal;
    return ['?', $word];
}

=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-lingua-lex at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Lingua-Lex>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lingua::Lex::Cascade


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

1; # End of Lingua::Lex::Cascade
