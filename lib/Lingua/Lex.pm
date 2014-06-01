package Lingua::Lex;

use 5.006;
use strict;
use warnings FATAL => 'all';
#use DBD::SQLite;
use Data::Dumper;
use DBI qw(:sql_types);
use utf8;
use File::stat;
use Carp;

=head1 NAME

Lingua::Lex - Provides lexical services for an NLP tokenizer

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

When working with natural languages, we end up working with words a lot. The lexicon provides a central
point of query and management when working with knowledge about words. The simplest form of a lexicon
is simply the word list, which manages lists of words that are known to be words. A step up from that
is a category recognizer, which can tell you whether a given word is a number or a URL. More complete
information about a word includes its part of speech (whether it's a noun or a verb or - in context -
could be either), or, going even further, its stem and information such as whether it's
plural or in accusative case, and so on (morphological analysis). Going into even further detail,
we can even get information like the word's likely translations into other languages, or a semantic
frame we can use to interpret its usage in a sentence.

All that is centralized in the lexicon, and it's often used in conjunction with a tokenizer that extracts
individual words from a given text. (The token stream consisting of marked words is then usually passed
up the ladder to a parser to discover the syntactic relationships between the words, but we don't
actually care about that terribly much at this level.)

A lexicon I<run> should be considered as distinct from the lexicon itself. A Lingua::Lex object is
really a run (or can be considered one). As such, it can also collect statistics about the run, including
word and phrase counts and so on. A lexicon run roughly corresponds to the words in a given document.

=head1 SUBROUTINES/METHODS

=head2 new (dbh, table, ngrams, nmax, recog)

Creates a new run against a database. The C<dbh> parameter is required, and specifies a DBI handle
to the database to be used. C<table> is not required, and defaults to "words". The schema of the
table to be used is fairly loose, but the key must be "word" and must obviously be a text column.

Multiple tables can be specified by providing an arrayref; in this case, each table will be consulted
in order and the first match will be returned.

The C<ngrams> parameter indicates whether n-grams should be tracked along with words during the run;
if so, set C<nmax> to indicate the maximum size of an n-gram. Each n-gram stops on a stopword boundary
that the lexicon itself must detect based on its own lexical information. The tokenizer can also
explicitly indicate a stop by calling C<stop> on the lexicon (usually based on punctuation, which is
not passed into the lexicon).

If a C<recog> parameter is provided, it is an arrayref of rule-based lexical recognizers that should
be called on each word before the database is consulted. These are used to recognize things like
numbers and URLs before cluttering up the word list with them.

The lexicon I<always> returns an arrayref from every call, which can be used as a token. At a minimum,
the token type will be either 'word' (for a recognized word) or '?' (for an unknown word). If the
wordlist has a pos column, then the content of that column will be returned as the token type if
the word is found.

=cut

sub new {
    my $class = shift;
    my $self = bless {@_}, $class;

    $self->{db_fresh} = 0;
    if ($self->{dbh} and not $self->{db}) {
        eval { $self->{db} = $self->{dbh}->sqlite_db_filename(); };
    } elsif (not $self->{db}) {
        $self->{db} = $self->default_filename;  # Overridable.
    }

    if (not $self->{dbh}) {
        $self->{db_fresh} = not (-e $self->{db});
        $self->{db_stat} = stat($self->{db});
        $self->{dbh} = DBI->connect('dbi:SQLite:dbname=' . $self->{db}, '', '', {sqlite_unicode => 1})
                or croak "Couldn't connect to database: " . DBI->errstr;
    }

    if (defined $self->{table}) {
        $self->{table} = [$self->{table}] unless ref $self->{table};
        my @sql = map { $self->{dbh}->prepare ("select * from $_ where word=? collate nocase") } @{$self->{table}};
        $self->{sql}->{words} = [@sql];
        $self->{sql}->{starts}   = $self->{dbh}->prepare (sprintf ("select * from %s where word=substr(?,1,length(word)) order by length(word) desc", $self->{starts})) if $self->{starts};
        $self->{sql}->{suffixes} = $self->{dbh}->prepare (sprintf ("select * from %s where suffix=substr(?, ?-length(suffix), length(suffix)) order by length (suffix) desc, length(stem) asc", $self->{suffixes})) if $self->{suffixes};
        $self->{stop_pos} = {};
    } elsif (defined $self->{load}) {
        $self->reload($self->{load});
        $self->{stop_pos} = {};
    } elsif (defined $self->default_lexicon) {
        $self->reload($self->default_lexicon);
    }
    $self->{stop_pos} = {};
    $self->stop_on_pos($self->default_stoppos);
    $self->restart;
    $self;
}

=head2 default_filename

The default filename if no handle is passed and no filename specified is 'lexicon.sqlt'. That can be overridden by subclasses.

=cut

sub default_filename { 'lexicon.sqlt'; }

=head2 default_lexicon

The directory containing the default lexicon. For this base class, this is blank; it can be overridden to use e.g. File::ShareDir for
language-specific subclasses.

=cut

sub default_lexicon { undef; }

=head2 default_stoppos

This registers the lexicon's default stopword parts of speech. It's blank for the base class but can be subclassed for specific
languages.

=cut

sub default_stoppos { (); }

=head2 status_message

By default, this does nothing. If a status callback is installed with set_status_callback, though, it sends its arguments to
that callback.  Status messages are primarily used during reloading to indicate what's going on.

=cut

sub status_message {
    my $self = shift;
    return unless defined $self->{status_callback};
    $self->{status_callback}->(@_);
}

=head2 set_status_callback

Sets the status message callback. This is a closure which expects one string as a message for display.

=cut

sub set_status_callback {
    my $self = shift;
    $self->{status_callback} = shift;
}

=head2 word, word_debug

Looks up a word during the run. For purposes of debugging morphology, word_debug does the same thing but calls the status message
callback with informative messages during the lookup process. Note that I<that> is a maintenance nightmare waiting to happen; these
two functions must always be guaranteed to do the same thing, and I'm sure they won't, as soon as I depend on them to.

=cut

sub _handle_ngrams {
    my $self = shift;
    my $word = shift;
    return unless $self->{ngrams};
    push @{$self->{currun}}, $word;
    shift @{$self->{currun}} if defined $self->{nmax} and @{$self->{currun}} > $self->{nmax};
    my $len = 2;
    while ($len <= @{$self->{currun}}) {
        $self->{ngrams}->{join ' ', @{$self->{currun}}[-$len..-1]}++;   # How's *that* for line noise?
        $len ++;
    }
}

sub _returnval {
    my $self = shift;
    my $hash = shift;

    my $stop = 0;
    my $word;
    my $pos;
    my $fullpos;
    if (ref($hash) eq 'HASH') {
        $word = $hash->{'word'};
        $pos  = $hash->{'pos'} || 'word';
        if ($pos =~ /^(.*?)\+/) {
            $fullpos = $pos;
            $pos = $1;
        }
        if ($hash->{'stop'}) {
            $stop = 1;
        } else {
            $stop = 1 if $self->{stop_pos}->{$pos};
        }
    } else {
        $word = $hash->[1];
        $pos  = $hash->[0];
        $stop = 1 if $self->{stop_pos}->{$pos};
    }
    if ($stop) {
        $self->stop;
    } else {
        $self->_handle_ngrams($word);
    }
    return $hash if ref($hash) eq 'ARRAY';
    return [$pos, $word, $fullpos ? ($word, $fullpos) : ()];
}

sub _modify_pos {
    my $orig = shift;
    my $orig_full = shift;
    my $changes = shift;
    
    $orig = $orig_full if $orig_full;
    $orig = '' unless $orig;
    my ($old, @oattr) = split /([\-\+])/, $orig;
    if (@oattr) {
       shift @oattr;
       push @oattr, '+';
    }
    my %oattr = @oattr;
    
    $changes = '' unless $changes;
    my ($new, @nattr) = split /([\-\+])/, $changes;
    $old = $new if $new;
    while (my $op = shift @nattr) {
        if ($op eq '-') {
            delete $oattr{shift @nattr};
        } elsif ($op eq '+') {
            $oattr{shift @nattr} = '+';
        } else {
            shift @nattr; # noop
        }
    }
    join '+', ($old, sort keys %oattr);  # We sort to simplify comparison - testing, mostly.
}

sub word {
    my $self = shift;
    my $word = shift;
    my $internal = shift;
    croak "Lexicon not loaded or initialized" unless defined $self->{sql}->{words};
    
    $self->{nonwords} = {} unless $internal;
    $self->{indirect} = {} unless $internal;
    return ['?', $word] if $internal and $self->{nonwords}->{$word};

    $self->{stats}->{count}++ unless $internal;
    $self->{words}->{$word}++ unless $internal;
    return $self->_returnval ($self->{cache}->{$word}) if defined $self->{cache}->{$word}; # Caching will hit twice for upper/lower case
    foreach my $check (@{$self->{sql}->{words}}) {
        $check->execute($word);
        my $ret = $check->fetchrow_hashref;
        if ($ret) {
            next if $internal and $ret->{word} =~ /^\p{Upper}+$/ and $ret->{word} ne $word;
                                                         # This is to prevent capitalized acronyms from acting as parts of words: vorher+IG+er for acronym IG
                                                         # This might not be the best way to handle it; probably acronyms should be a different POS than just nouns.
            $ret->{word} = $word; # Make sure capitalization matches
            $self->{cache}->{$word} = $ret unless $internal;
            return $self->_returnval($ret);
        }
    }

    #$self->status_message ("$word not found directly.\n");

    # If the word has non-ASCII caps in it, let's try lower-casing it to get around the fact that COLLATE NOCASE
    # doesn't work for UTF8 in SQLite.  (You're very right, this is not the way to do this. But it works for today.)
    # TODO: provide a proper collation sequence for SQLite for each specific language, probably.
    # TODO: also provide a better detection regex for capital non-ASCII letters than the one here.
    if ($word =~ /[ÄÜÖÁÓÚÍÀÒÙÌ]/) {
        my $lcword = lc($word);
        #$self->status_message ("Could it be $lcword?");
        my $lookup = $self->word($lcword, 1);
        if ($lookup->[0] ne '?') {
            return $self->_returnval($lookup);
        }
    }

    $self->{indirect}->{$word} = 1;
    my $word_length = length($word);

    # Check prefixes
    if ($self->{sql}->{prefixes}) {
        $self->{sql}->{prefixes}->execute($word);
        my @starts = ();
        while (my $ret = $self->{sql}->{prefixes}->fetchrow_hashref) {
            push @starts, $ret;
        }
        foreach my $start (@starts) { # Possible matches, longest to shortest
            my $rest = substr($word, length($start->{word}), $word_length-length($start->{word}));
            next if length($rest) < 2;
            #$self->status_message ("Could it be " . $start->{word} . "+$rest?\n");
            my $lookup = $self->word($rest, 1);
            if ($lookup->[0] ne '?') {
                $lookup->[1] = $word;
                $lookup->[2] = $start->{word} . "+$rest";
                $self->{cache}->{$word} = $lookup;
                return $self->_returnval($lookup);
            }
        }
    }
    
    # Check compounds
    if ($self->{sql}->{starts}) {
        $self->{sql}->{starts}->execute($word);
        my @starts = ();
        while (my $ret = $self->{sql}->{starts}->fetchrow_hashref) {
            push @starts, $ret;
        }
        foreach my $start (@starts) {
            my $rest = substr($word, length($start->{word}), $word_length-length($start->{word}));
            next if length($rest) < 2;
            #$self->status_message ("Could it be " . $start->{word} . "+$rest?\n");
            my $lookup = $self->word($rest, 1);
            if ($lookup->[0] ne '?') {
                $lookup->[1] = $word;
                $lookup->[2] = $start->{word} . "+$rest";
                $self->{cache}->{$word} = $lookup;
                return $self->_returnval($lookup);
            }
        }
    }
    
    # Check suffixes
    if ($self->{sql}->{suffixes}) {
        $self->{sql}->{suffixes}->execute($word, length($word)+1);
        my @suffixes = ();
        while (my $ret = $self->{sql}->{suffixes}->fetchrow_hashref) {
            push @suffixes, $ret;
        }
        foreach my $suff (@suffixes) {
            next if length($suff->{suffix}) >= length($word);
            my $rest = substr($word, 0, $word_length-length($suff->{suffix}));
            next if length($rest) < 2;
            # Do we match match?
            next unless $rest =~ /$suff->{match}$/;
            $rest .= $suff->{stem};
            next if length($rest) < 2;
            next if $self->{indirect}->{$rest};
            #$self->status_message ("Could it be $rest+" . $suff->{suffix} . "?\n");
            my $lookup = $self->word($rest, 1);
            if ($lookup->[0] ne '?') {
                $lookup->[0] = _modify_pos($lookup->[0], $lookup->[3], $suff->{pos});
                if ($lookup->[0] =~ /\+/) {
                    $lookup->[3] = $lookup->[0];
                    $lookup->[0] =~ s/\+.*//;
                }
                $lookup->[1] = $word;
                $rest = $lookup->[2] if $lookup->[2];
                $lookup->[2] = "$rest+" . $suff->{suffix};
                $self->{cache}->{$word} = $lookup;
                return $self->_returnval($lookup);
            }
        }
    }
    
    #$self->status_message ("$word is unknown.\n");
    $self->{nonwords}->{$word} = 1 if $internal;
    $self->{stats}->{ucount}++ unless $internal;
    $self->{unknown}->{$word}++ unless $internal;
    $self->_handle_ngrams($word) unless $internal;
    return ['?', $word];
}
sub word_debug {
    my $self = shift;
    my $word = shift;
    my $internal = shift;
    croak "Lexicon not loaded or initialized" unless defined $self->{sql}->{words};
    
    $self->status_message ("Looking up $word\n");
    $self->{nonwords} = {} unless $internal;
    $self->{indirect} = {} unless $internal;
    return ['?', $word] if $internal and $self->{nonwords}->{$word};

    $self->{stats}->{count}++ unless $internal;
    $self->{words}->{$word}++ unless $internal;
    return $self->_returnval ($self->{cache}->{$word}) if defined $self->{cache}->{$word}; # Caching will hit twice for upper/lower case
    foreach my $check (@{$self->{sql}->{words}}) {
        $check->execute($word);
        my $ret = $check->fetchrow_hashref;
        if ($ret) {
            next if $internal and $ret->{word} =! /^\p{Upper}+$/ and $ret->{word} ne $word;
                                                         # This is to prevent capitalized acronyms from acting as parts of words: vorher+IG+er for acronym IG
                                                         # This might not be the best way to handle it; probably acronyms should be a different POS than just nouns.
            $ret->{word} = $word; # Make sure capitalization matches
            $self->{cache}->{$word} = $ret unless $internal;
            return $self->_returnval($ret);
        }
    }
    $self->status_message ("$word not found directly.\n");
    
    # If the word has non-ASCII caps in it, let's try lower-casing it to get around the fact that COLLATE NOCASE
    # doesn't work for UTF8 in SQLite.  (You're very right, this is not the way to do this. But it works for today.)
    # TODO: provide a proper collation sequence for SQLite for each specific language, probably.
    # TODO: also provide a better detection regex for capital non-ASCII letters than the one here.
    if ($word =~ /[ÄÜÖÁÓÚÍÀÒÙÌ]/) {
        my $lcword = lc($word);
        $self->status_message ("Could it be $lcword?");
        my $lookup = $self->word_debug($lcword, 1);
        if ($lookup->[0] ne '?') {
            return $self->_returnval($lookup);
        }
    }

    $self->{indirect}->{$word} = 1;
    my $word_length = length($word);

    # Check prefixes
    if ($self->{sql}->{prefixes}) {
        $self->{sql}->{prefixes}->execute($word);
        my @starts = ();
        while (my $ret = $self->{sql}->{prefixes}->fetchrow_hashref) {
            push @starts, $ret;
        }
        foreach my $start (@starts) { # Possible matches, longest to shortest
            my $rest = substr($word, length($start->{word}), $word_length-length($start->{word}));
            next if length($rest) < 2;
            $self->status_message ("Could it be (" . $start->{word} . ")+$rest?\n");
            my $lookup = $self->word_debug($rest, 1);
            if ($lookup->[0] ne '?') {
                $lookup->[1] = $word;
                $lookup->[2] = $start->{word} . "+$rest";
                $self->{cache}->{$word} = $lookup;
                return $self->_returnval($lookup);
            }
        }
    }

    # Check compounds
    if ($self->{sql}->{starts}) {
        $self->{sql}->{starts}->execute($word);
        my @starts = ();
        while (my $ret = $self->{sql}->{starts}->fetchrow_hashref) {
            push @starts, $ret;
        }
        foreach my $start (@starts) { # Possible matches, longest to shortest
            my $rest = substr($word, length($start->{word}), $word_length-length($start->{word}));
            next if length($rest) < 2;
            $self->status_message ("Could it be (" . $start->{word} . ")+$rest?\n");
            my $lookup = $self->word_debug($rest, 1);
            if ($lookup->[0] ne '?') {
                $lookup->[1] = $word;
                $lookup->[2] = $start->{word} . "+$rest";
                $self->{cache}->{$word} = $lookup;
                return $self->_returnval($lookup);
            }
        }
    }
    
    # Check suffixes
    if ($self->{sql}->{suffixes}) {
        $self->{sql}->{suffixes}->execute($word, length($word)+1);
        my @suffixes = ();
        while (my $ret = $self->{sql}->{suffixes}->fetchrow_hashref) {
            push @suffixes, $ret;
        }
        foreach my $suff (@suffixes) {
            next if length($suff->{suffix}) >= length($word);
            my $rest = substr($word, 0, $word_length-length($suff->{suffix}));
            next if length($rest) < 2;
            # Do we match match?
            next unless $rest =~ /$suff->{match}$/;
            $rest .= $suff->{stem};
            next if length($rest) < 2;
            next if $self->{indirect}->{$rest};
            $self->status_message ("Could it be $rest+(" . $suff->{suffix} . ")?\n");
            my $lookup = $self->word_debug($rest, 1);
            if ($lookup->[0] ne '?') {
                $lookup->[0] = _modify_pos($lookup->[0], $lookup->[3], $suff->{pos});
                if ($lookup->[0] =~ /\+/) {
                    $lookup->[3] = $lookup->[0];
                    $lookup->[0] =~ s/\+.*//;
                }
                $lookup->[1] = $word;
                $rest = $lookup->[2] if $lookup->[2];
                $lookup->[2] = "$rest+" . $suff->{suffix};
                $self->{cache}->{$word} = $lookup;
                return $self->_returnval($lookup);
            }
        }
    }

    
    
    $self->status_message ("$word is unknown.\n");
    $self->{nonwords}->{$word} = 1 if $internal;
    $self->{stats}->{ucount}++ unless $internal;
    $self->{unknown}->{$word}++ unless $internal;
    $self->_handle_ngrams($word) unless $internal;
    return ['?', $word];
}

=head2 stop

Signifies a phrase boundary. This is needed only if you're tracking n-grams.

=cut

sub stop {
    my $self = shift;
    $self->{currun} = [];
}

=head2 ngram_punc

Provides the ngram tracker with punctuation we want to consider parts of phrases (like slashes)

=cut

sub ngram_punc {
    my $self = shift;
    foreach my $p (@_) {
        $self->_handle_ngrams($p);
    }
}

=head2 stop_on_pos

Sets the stop flag for the parts of speech listed. By default, nothing is a stop word.

=cut

sub stop_on_pos {
    my $self = shift;
    foreach my $p (@_) {
        $self->{stop_pos}->{$p} = 1;
    }
}

=head2 stats

Retrieves the current stats from the run.

=cut

sub stats {
    my $self = shift;
    my $which = shift;
    return $self->{$which} if defined $which;
    ($self->{stats}, $self->{words}, $self->{unknown});
}

=head2 restart

Clears out stats to start a new run with the same lexicon.

=cut

sub restart {
    my $self = shift;
    $self->{stats} = {count => 0, ucount=>0, longrun=>0};
    $self->{words} = {};
    $self->{ngrams} = {};
    $self->{unknown} = {};
    $self->{cache} = {};
    $self->{currun} = [];
}

=head2 normalize_ngrams (ngrams)

Given I<any> list of ngrams structured according to this module (a hashref with keys being the ngram and values the counts),
normalizes the list by sorting it from longest to shortest, then deducting the count for each longer phrase from all the shorter
phrases it contains.  This should only be done after a run is complete, otherwise your counts will make no sense at all.

If no hashref is provided, we'll normalize our own ngram list and return it.

=cut

sub normalize_ngrams {
    my $self = shift;
    my $hashref = shift;
    $hashref = $self->{ngrams} unless $hashref;
    
    my @keys = keys %$hashref;
    my %lengths;
    foreach my $key (@keys) {
        my @phr = split / /, $key;
        $lengths{$key} = scalar @phr;
    }
    foreach my $key (sort { $lengths{$b} <=> $lengths{$a}} @keys) {
        next unless defined $hashref->{$key};
        my @fphr = split / /, $key;
        my @lphr = (@fphr);
        my $count = $hashref->{$key};
        my $len = scalar @lphr;
        last if $len == 2;
        while ($len > 2) {
            shift @fphr;
            my $fphr = join ' ', @fphr;
            pop @lphr;
            my $lphr = join ' ', @lphr;
            if (defined $hashref->{$fphr}) {
                my $newcount = $hashref->{$fphr} - $count;
                if ($newcount > 0) {
                    $hashref->{$fphr} = $newcount;
                } else {
                    delete $hashref->{$fphr};
                }
            }
            if (defined $hashref->{$lphr}) {
                my $newcount = $hashref->{$lphr} - $count;
                if ($newcount > 0) {
                    $hashref->{$lphr} = $newcount;
                } else {
                    delete $hashref->{$lphr};
                }
            }
            $len --;
        }
    }
    return $hashref;
}

=head1 MANAGING LEXICAL RESOURCES

The active lexicon is a database, but it can be loaded from (and to a limited extent dumped to) text files for easier version control
and portability.  I say "limited extent" because there are some rules, like suffixes, which undergo some processing during load and
therefore can't really be dumped back out without losing comments and so on. You can dump them, sure, but the dump will lose some clarity.

Word lists, though, can largely be dumped without much loss. My thinking on this is that word lists will probably be subject to frequent
change, as vocabulary is discovered (as well as being project-specific in many cases). Dumping and manipulation will be important.

Large lexica will be in multiple files for ease of management, and at some point we'll probably want to provide some paramterization of
wordlists (for dialects, for example, or if we simply want to use this module to maintain lexical resource for use in ispell or Hunspell
in the same way that igerman98 is parameterizable).

At the same time, it will be nice to be able to keep everything in a single file or even a string for testing or small-scale applications.

So here's how it works. The whole thing is broken down into "keyword domains", of which the components that will end up in the lexicon
itself are: words for basic word lists; starts, middles, and ends for compound word construction a la German or Hungarian; prefixes, suffixes,
circumfixes, and infixes for the basic morphological rules (of which suffixes are rule-based and complex, and circumfixes and infixes
haven't even been written yet), stops to define the parts of speech that should be stopwords, and finally I<tables> will define the
tables that everything else will go into, if tables is specified.

If we're using the separate-file system, then each of these domains can be represented either as a file named [domain].txt, or as a directory
containing arbitrarily named files with .txt endings. (Anything with a non-.txt ending will be summarily ignored.) Here, if a "files.txt"
file exists, it will be used to define the names of the different domains, and the names of the tables to be used to store them. This allows
us to define multiple lexica in a single database if we like.

If everything is in a single file, it can be called anything you like, and the domains are named according to their defaults above:

   words:
   the  art+def
   a    art+indef
   child/R    n
   
   words: import mywordlist.txt
   
   starts:
   news
   
   ends:
   paper    n
   
   suffixes:
   R: irregular verb plural
   n    .   .   ren +p  .
   
=head2 load (string=>'string', file=>'file.txt', directory='directory')

Given a string, treats the string as a lexical definition; given a filename or a stream, loads the definition from there;
given a directory, looks at the files in the directory to see what to do.

=cut

sub _create_table {
    my ($self, $domain, $typed, $reload_only) = @_;
    my $table = $self->{domains}->{$domain};
    $self->{typed_domains}->{$domain} = $typed;

    if ($reload_only) {
        #$self->status_message ("Table for domain $domain already created.\n");
    } else {
        $self->status_message (sprintf "Creating and loading %s domain $domain.\n", $typed? 'typed':'non-typed');
    }
    if ($domain eq 'words') {
        if (not $reload_only) {
            $self->{dbh}->do        ("drop table if exists $table");
            $self->{dbh}->do        ("drop index if exists ${table}_word");
            $self->{dbh}->do        (sprintf("create table $table (word varchar primary key, %s flags varchar, pos varchar)", $typed ? "type varchar," : ''));
            $self->{dbh}->do        ("create index ${table}_word on $table (word collate nocase)");
        }
        $self->{ins}->{words} =
            $self->{dbh}->prepare (sprintf("insert into $table values (?, %s ?, ?)", $typed ? '?,' : ''));
        $self->{sql}->{words} =
          $self->{dbh}->prepare ("select * from $table where word=? collate nocase");
    } elsif ($domain eq 'prefixes') {
        if (not $reload_only) {
            $self->{dbh}->do        ("drop table if exists $table");
            $self->{dbh}->do        ("drop index if exists ${table}_word");
            $self->{dbh}->do        (sprintf("create table $table (word varchar primary key, %s flags varchar, pos varchar)", $typed ? "type varchar," : ''));
            $self->{dbh}->do        ("create index ${table}_word on $table (word collate nocase)");
        }
        $self->{ins}->{prefixes} =
          $self->{dbh}->prepare (sprintf("insert into $table values (?, %s ?, ?)", $typed ? '?,' : ''));
        $self->{sql}->{prefixes} =
          $self->{dbh}->prepare ("select * from $table where word=substr(?,1,length(word)) collate nocase order by length(word) desc");
    } elsif ($domain eq 'suffixes') {
        if (not $reload_only) {
            $self->{dbh}->do        ("drop table if exists $table");
            $self->{dbh}->do        ("drop index if exists ${table}_suffix");
            $self->{dbh}->do        ("create table $table (flag varchar, matchpos varchar, match varchar, stem varchar, suffix varchar, pos varchar, chain varchar)");
            $self->{dbh}->do        ("create index ${table}_suffix on $table (suffix)");
        }
        $self->{ins}->{suffixes} =
          $self->{dbh}->prepare ("insert into $table values (?, ?, ?, ?, ?, ?, ?)");
        $self->{sql}->{suffixes} =
          $self->{dbh}->prepare ("select * from $table where suffix=substr(?, ?-length(suffix), length(suffix)) order by length (suffix) desc, length(stem) asc");
    } else { #'starts', 'ends', 'middles', etc.
        if (not $reload_only) {
            $self->{dbh}->do        ("drop table if exists $table");
            $self->{dbh}->do        ("drop index if exists ${table}_word");
            $self->{dbh}->do        (sprintf("create table $table (word varchar primary key, %s flags varchar, pos varchar)", $typed ? "type varchar," : ''));
            $self->{dbh}->do        ("create index ${table}_word on $table (word collate nocase)");
        }
        $self->{ins}->{$domain} =
          $self->{dbh}->prepare (sprintf("insert into $table values (?, %s ?, ?)", $typed ? '?,' : ''));
        $self->{sql}->{$domain} =
          $self->{dbh}->prepare ("select * from $table where word=substr(?,1,length(word)) collate nocase order by length(word) desc");
    }
}
sub _load_table {
    my ($self, $domain, $type, $import) = @_;
    open my $in, '<', $import or croak "Can't find input file $import";
    my $short = $import;
    $short =~ s/^.*\///;
    $self->status_message (" $domain <-- $short\n");
    my $curflag = '';
    while (<$in>) {
        chomp;
        $self->_load_line ($domain, $type, \$curflag, $_);
    }
}
sub _load_line {
    my ($self, $domain, $type, $curflag, $line) = @_;
    return unless $line;
    $_ = $line;
    return if /^\s*$/;
    s/A"/Ä/g;
    s/O"/Ö/g;
    s/U"/Ü/g;
    s/a"/ä/g;
    s/o"/ö/g;
    s/u"/ü/g;
    s/sS/ß/g;
    s/e'/é/g;
    s/--/\//g;
    if ($domain eq 'suffixes') {
        s/#.*$//;
        return unless $_;
        if (/^(.): /) {
           $$curflag = $1;
           return;
        }
        my ($matchpos, $match, $stem, $suffix, $pos, $chain) = split /\s+/;
        $matchpos = '' if not $matchpos or $matchpos eq '.';
        $match    = '' if not $match    or $match    eq '.';
        $stem     = '' if not $stem     or $stem     eq '.';
        $suffix   = '' if not $suffix   or $suffix   eq '.';
        $pos      = '' if not $pos      or $pos      eq '.';
        $chain    = '' if not $chain    or $chain    eq '.';
        $self->{ins}->{$domain}->execute ($$curflag, $matchpos, $match, $stem, $suffix, $pos, $chain);
    } else {
        my ($wthing, $pos) = split /\s+/;
        my ($word, $flags) = split /\//, $wthing;

        $flags = '' unless $flags;
        $pos   = '' unless $pos;
        $self->{ins}->{$domain}->execute ($word, $self->{typed_domains}->{$domain} ? $type : (), $flags, $pos);
    }
}

sub load {
    my $self = shift;
    my %args = @_;
    my $next;
    if ($args{string}) {
        my @lines = split /\n/, $args{string};
        $next = sub { shift @lines; };
    } elsif ($args{file}) {
        if (ref($args{file})) {
            my $fh = $args{file};
            $next = sub { my $line = scalar <$fh>; chomp($line) if $line; $line; };
        } else {
            open IN, '<', $args{file} or croak "Can't find input file " . $args{file};
            $next = sub { my $line = scalar <IN>; chomp($line) if $line; $line; };
        }
    } else {
        croak "Can't find directory $args{directory}" unless -e $args{directory};
        croak "$args{directory} not a directory" unless -d $args{directory};
        return $self->_load_from_directory($args{directory});
    }
    my $domain = '';
    $self->{domains} = {};
    my $curflag = '';
    while (1) {
        my $line = $next->();
        last if not defined $line;
        $line =~ s/#.*//;
        next if not $line;

        if ($line =~ /^(\w+):\s*(.*?)\s*$/) {
            if (length($1) > 1) {
                $domain = $1;
                my $after = $2;
                my ($name, $import) = split /\s*<\s*/, $after;

                if (not defined $self->{domains}->{$domain}) {
                    $name = $domain unless $name;
                    $self->{domains}->{$domain} = $name;
                    $self->_create_table($domain);
                    if ($import) {
                        croak "Can't find $import to load domain $domain" unless -e $import;
                        $self->_load_table($domain, '', $import);
                    }
                }
            } else {
                $curflag = $1;
            }
            next;
        }
        $self->_load_line($domain, '', \$curflag, $line);
    }
    $self->{sql}->{words} = [$self->{sql}->{words}];
}

sub _load_from_directory {
    my ($self, $directory) = @_;
    opendir D, $directory or croak "Can't open directory $directory";

    my @components = grep { not /^\./ and (-d "$directory/$_" or /\.txt$/) } readdir (D);
    closedir D;
    foreach my $c (@components) {
        my ($domain) = $c =~ /^(\w+)/;  # This untaints the filenames in a more or less correct way: all spaces and punctuation are dropped.
        my $typed = 0;
        $typed = 1 if -d "$directory/$c";
        $self->{domains}->{$domain} = $domain;
        $self->_create_table($domain, $typed);
        if ($typed) {
            opendir D, "$directory/$c";
            my @typed_components = grep { /\.txt$/ } readdir (D);
            closedir D;
            foreach my $tyc (@typed_components) {
                my ($type) = $tyc =~ /^(.*)\.txt$/;
                $self->_load_table($domain, $type, "$directory/$c/$tyc");
            }
        } else {
            $self->_load_table($domain, '', "$directory/$c");
        }
    }
    $self->{sql}->{words} = [$self->{sql}->{words}];
}

=head2 reload ('file.txt') or reload ('directory')

Reloading is provided to make the testing of large lexica like Lingua::Lex::DE easier. It checks the date the database file was updated,
and compares it to the files used to load it. Any files that are newer will be reloaded - with the caveat that changes in structure,
specifically the change of any domain from an untyped (simple) domain to a typed (multi-file) domain or vice versa will break the loaded
lexicon. So don't do that. Sure, I could do error checking, but you're a grownup. When you change structure, do a full load and nobody
will get hurt.

Also, the database doesn't know its own name before SQLite v1.39. So if you open a lexicon by filename or directory name, you can reload it;
otherwise SQLite doesn't know what database file to compare file ages with, so we'll croak instead.

=cut

sub reload {
    my ($self, $where) = @_;

    croak "$where not found" unless -e $where;
    
    my $type = 'file';
    $type = 'directory' if -d $where;
    
    return $self->load ($type => $where) if $self->{db_fresh};
    
    if ($type eq 'file') {
        my $fs = stat($where);
        return $self->load(file => $where) if $fs->mtime > $self->{db_stat}->mtime;
        # Scan for domain information
        open SCAN, '<', $where;
        my $domain = '';
        while (<SCAN>) {
            chomp;
            my $line = $_;
            $line =~ s/#.*//;
            next if not $line;

            if ($line =~ /^(\w+):\s*(.*?)\s*$/) {
                if (length($1) > 1) {
                    $domain = $1;
                    my $after = $2;
                    my ($name, $import) = split /\s*<\s*/, $after;

                    if (not defined $self->{domains}->{$domain}) {
                        $name = $domain unless $name;
                        $self->{domains}->{$domain} = $name;
                        $self->_create_table($domain, 0, 1);
                    }
                }
                next;
            }
        }
        $self->{sql}->{words} = [$self->{sql}->{words}];
        $self->{db_stat} = stat($self->{db});
        return;
    }

    croak "$where is not a directory" unless -d $where;
    opendir D, $where or croak "Can't open directory $where";
    my @components = grep { not /^\./ and (-d "$where/$_" or /\.txt$/) } readdir (D);
    closedir D;
    foreach my $c (@components) {
        my ($domain) = $c =~ /^(\w+)/;  # This untaints the filenames in a more or less correct way: all spaces and punctuation are dropped.
        my $typed = 0;
        $typed = 1 if -d "$where/$c";
        $self->{domains}->{$domain} = $domain;
        $self->_create_table($domain, $typed, 1);
        if ($typed) {
            opendir D, "$where/$c";
            my @typed_components = grep { /\.txt$/ } readdir (D);
            my $sth = $self->{dbh}->prepare (sprintf ("delete from %s where type=?", $self->{domains}->{$domain}));
            closedir D;
            foreach my $tyc (@typed_components) {
                my ($type) = $tyc =~ /^(.*)\.txt$/;
                my $fs = stat("$where/$c/$tyc");
                next unless $fs->mtime > $self->{db_stat}->mtime;
                $sth->execute($type);
                $self->_load_table($domain, $type, "$where/$c/$tyc");
            }
        } else {
            my $fs = stat("$where/$c");
            next unless $fs->mtime > $self->{db_stat}->mtime;
            $self->{dbh}->do ("delete from " . $self->{domains}->{$domain});
            $self->_load_table($domain, '', "$where/$c");
        }
    }
    $self->{db_stat} = stat($self->{db});
    $self->{sql}->{words} = [$self->{sql}->{words}];
}

 

=head2 dump (file=>'file.txt', directory='directory')

Given nothing, returns an iterator that can be used to extract the entire lexicon as a string (good luck!); given a stream or
a file, writes it in single-file format; given a directory name, creates that directory and stores everything there in
multi-file format.

=cut

sub dump {
}

=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-lingua-lex at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Lingua-Lex>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lingua::Lex


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

1; # End of Lingua::Lex
