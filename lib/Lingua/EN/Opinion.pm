package Lingua::EN::Opinion;

# ABSTRACT: Measure the emotional sentiment of text

our $VERSION = '0.1506';

use Moo;
use strictures 2;
use namespace::clean;

use Lingua::EN::Opinion::Positive;
use Lingua::EN::Opinion::Negative;
use Lingua::EN::Opinion::Emotion;

use Carp;
use File::Slurper qw( read_text );
use Lingua::EN::Sentence qw( get_sentences );
use Statistics::Lite qw( mean );
use Try::Tiny;

=head1 SYNOPSIS

  use Lingua::EN::Opinion;

  # Positive/Negative:
  my $opinion = Lingua::EN::Opinion->new( file => '/some/file.txt', stem => 1 );
  $opinion->analyze();

  my $scores = $opinion->scores;

  my $ratio = $opinion->ratio(); # Knowns / ( Knowns + Unknowns )
  $ratio = $opinion->ratio(1); # Unknowns / ( Knowns + Unknowns )

  $scores = $opinion->averaged_scores(5);

  my $score = $opinion->get_word('foo');
  $score = $opinion->get_sentence('Mary had a little lamb.');

  # NRC:
  $opinion = Lingua::EN::Opinion->new( text => 'Mary had a little lamb...' );
  $opinion->nrc_analyze();

  $scores = $opinion->nrc_scores;

  $ratio = $opinion->ratio();
  $ratio = $opinion->ratio(1);

  $score = $opinion->nrc_get_word('foo');
  $score = $opinion->nrc_get_sentence('Mary had a little lamb.');

=head1 DESCRIPTION

A C<Lingua::EN::Opinion> object measures the emotional sentiment of
text and saves the results in the B<scores> and B<nrc_scores>
attributes.

When run against the positive and negative classified training reviews
in the dataset referenced under L</"SEE ALSO">, this module does ...
okay.  Out of 25k reviews, the F<eg/pos-neg> program gets about 70%
correct.

=head1 ATTRIBUTES

=head2 file

  $file = $opinion->file;

The text file to analyze.

=cut

has file => (
    is  => 'ro',
    isa => sub { die "File $_[0] does not exist" unless -e $_[0] },
);

=head2 text

  $text = $opinion->text;

A text string to analyze instead of a text file.

=cut

has text => (
    is => 'ro',
);

=head2 stem

  $stem = $opinion->stem;

Boolean flag to indicate that word stemming should take place.

For example, "horses" becomes "horse" and "hooves" becomes "hoof."

This is the proper way to use this module but takes ... a lot longer.

=cut

has stem => (
    is      => 'ro',
    default => sub { 0 },
);

=head2 stemmer

  $stemmer = $opinion->stemmer;

Require the L<WordNet::QueryData> and L<WordNet::stem> modules to stem
each word of the provided file or text.

* These modules must be installed and working to use this feature.

This is a computed result.  Providing this in the constructor will be
ignored.

=cut

has stemmer => (
    is       => 'ro',
    lazy     => 1,
    builder  => 1,
    init_arg => undef,
);

sub _build_stemmer {
    try {
        require WordNet::QueryData;
        require WordNet::stem;

        my $wn      = WordNet::QueryData->new();
        my $stemmer = WordNet::stem->new($wn);

        return $stemmer;
    }
    catch {
        croak 'The WordNet::QueryData and WordNet::stem modules must be installed and working to enable stemming support';
    };
}

=head2 sentences

  $sentences = $opinion->sentences;

Computed result.  An array reference of every sentence!

=cut

has sentences => (
    is       => 'rw',
    init_arg => undef,
    default  => sub { [] },
);

=head2 scores

  $scores = $opinion->scores;

Computed result.  An array reference of the score of each sentence.

=cut

has scores => (
    is       => 'rw',
    init_arg => undef,
    default  => sub { [] },
);

=head2 nrc_scores

  $scores = $opinion->nrc_scores;

Computed result.  An array reference of hash references containing the
NRC scores for each sentence.

=cut

has nrc_scores => (
    is       => 'rw',
    init_arg => undef,
    default  => sub { [] },
);

=head2 positive

  $positive = $opinion->positive;

Computed result.  A module to use to L</analyze>.

=cut

has positive => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { Lingua::EN::Opinion::Positive->new },
);

=head2 negative

  $negative = $opinion->negative;

Computed result.  A module to use to L</analyze>.

=cut

has negative => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { Lingua::EN::Opinion::Negative->new },
);

=head2 emotion

  $emotion = $opinion->emotion;

Computed result.  The module to used to find the L</nrc_sentiment>.

=cut

has emotion => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { Lingua::EN::Opinion::Emotion->new },
);

=head2 familiarity

  $familiarity = $opinion->familiarity;

Computed result.  Hash reference of total known and unknown words:

 { known => $x, unknown => $y }

=cut

has familiarity => (
    is       => 'rw',
    init_arg => undef,
    default  => sub { { known => 0, unknown => 0 } },
);

=head1 METHODS

=head2 new

  $opinion = Lingua::EN::Opinion->new(
    file => $file,
    text => $text,
    stem => $stem,
  );

Create a new C<Lingua::EN::Opinion> object.

=head2 analyze

  $scores = $opinion->analyze();

Measure the positive/negative emotional sentiment of text.

This method sets the B<scores> and B<sentences> attributes.

=cut

sub analyze {
    my ($self) = @_;

    my @scores;
    my ( $known, $unknown ) = ( 0, 0 );

    for my $sentence ( $self->_get_sentences ) {
        my @words = _tokenize($sentence);

        my $score = 0;

        for my $word ( @words ) {
            $word = $self->_stemword($word)
                if $self->stem;

            my $value = exists $self->positive->wordlist->{$word} ? 1
                : exists $self->negative->wordlist->{$word} ? -1 : 0;

            if ( $value ) {
                $known++;
            }
            else {
                $unknown++;
            }

            $score += $value;
        }

        push @scores, $score;
    }

    $self->familiarity( { known => $known, unknown => $unknown } );

    $self->scores( \@scores );
}

=head2 averaged_score

Synonym for the L</averaged_scores> method.

=head2 averaged_scores

  $scores = $opinion->averaged_scores($bins);

Compute the averaged scores given a number of (integer) B<bins>.

Default: C<10>

This reduces the amount of "noise" in the original signal.  As such,
it loses information detail.

For example, if there are 400 sentences, B<bins> of 10 will result in
40 data points.  Each point will be the mean of each successive
bin-sized set of points in the analyzed scores.

=cut

sub averaged_score { shift->averaged_scores(@_) }

sub averaged_scores {
    my ( $self, $bins ) = @_;

    $bins ||= 10;

    my @scores = map { $_ } @{ $self->scores };

    my @averaged;

    while ( my @n = splice @scores, 0, $bins ) {
        push @averaged, mean(@n);
    }

    return \@averaged;
}

=head2 nrc_sentiment

Synonym for the L</nrc_analyze> method.

=head2 nrc_analyze

  $scores = $opinion->nrc_analyze();

Compute the NRC sentiment of the given text.

This is given by a C<0/1> list of these 10 emotional elements:

  anger
  anticipation
  disgust
  fear
  joy
  negative
  positive
  sadness
  surprise
  trust

This method sets the B<nrc_scores> and B<sentences> attributes.

=cut

sub nrc_sentiment { shift->nrc_anaylze(@_) };

sub nrc_analyze {
    my ($self) = @_;

    my $null_state = { anger=>0, anticipation=>0, disgust=>0, fear=>0, joy=>0, negative=>0, positive=>0, sadness=>0, surprise=>0, trust=>0 };

    my @scores;
    my ( $known, $unknown ) = ( 0, 0 );

    for my $sentence ( $self->_get_sentences ) {
        my @words = _tokenize($sentence);

        my $score;

        for my $word ( @words ) {
            $word = $self->_stemword($word)
                if $self->stem;

            if ( exists $self->emotion->wordlist->{$word} ) {
                $known++;

                for my $key ( keys %{ $self->emotion->wordlist->{$word} } ) {
                    $score->{$key} += $self->emotion->wordlist->{$word}{$key};
                }
            }
            else {
                $unknown++;
            }
        }

        $score = $null_state
            unless $score;

        push @scores, $score;
    }

    $self->familiarity( { known => $known, unknown => $unknown } );

    $self->nrc_scores( \@scores );
}

=head2 get_word

  $sentiment = $opinion->get_word($word);

Get the positive/negative sentiment for a given word.  Return
C<undef>, C<0> or C<1> for "does not exist", "is positive" or "is
negative", respectively.

=cut

sub get_word {
    my ( $self, $word ) = @_;

    $word = $self->_stemword($word)
        if $self->stem;

    return exists $self->positive->wordlist->{$word} ? 1
        : exists $self->negative->wordlist->{$word} ? -1
        : undef;
}

=head2 nrc_get_word

  $sentiment = $opinion->nrc_get_word($word);

Get the NRC emotional sentiment for a given word.  Return a hash
reference of the NRC emotions as detailed in L</nrc_analyze>.  If the
word does not exist, return C<undef>.

=cut

sub nrc_get_word {
    my ( $self, $word ) = @_;

    $word = $self->_stemword($word)
        if $self->stem;

    return exists $self->emotion->wordlist->{$word}
        ? $self->emotion->wordlist->{$word}
        : undef;
}

=head2 get_sentence

  $values = $opinion->get_sentence($sentence);

Return the positive/negative values for the words of the given
sentence.

=cut

sub get_sentence {
    my ( $self, $sentence ) = @_;

    my @words = _tokenize($sentence);

    my @score = ();

    for my $word ( @words ) {
        my $score = $self->get_word($word);
        $score = 0
            unless $score;
        push @score, $score;
    }

    return \@score;
}

=head2 nrc_get_sentence

  $values = $opinion->nrc_get_sentence($sentence);

Return the NRC emotion values for each word of the given sentence.

=cut

sub nrc_get_sentence {
    my ( $self, $sentence ) = @_;

    my @words = _tokenize($sentence);

    my %score;

    for my $word ( @words ) {
        $score{$word} = $self->nrc_get_word($word);
    }

    return \%score;
}

=head2 ratio

Return the ratio of either the known or unknown words vs the total
known + unknown words.

Default: C<0>

If the method is given a C<1> as an argument, the unknown words ratio
is returned.  Otherwise the known ratio is returned by default.

=cut

sub ratio {
    my ( $self, $flag ) = @_;

    my $numerator = $flag ? $self->familiarity->{unknown} : $self->familiarity->{known};

    my $ratio = $numerator / ( $self->familiarity->{known} + $self->familiarity->{unknown} );

    return $ratio;
}

sub _tokenize {
    my ($sentence) = @_;
    $sentence =~ s/[[:punct:]]//g;  # Drop punctuation
    $sentence =~ s/\d//g;           # Drop digits
    my @words = grep { $_ } map { lc $_ } split /\s+/, $sentence;
    return @words;
}

sub _stemword {
    my ( $self, $word ) = @_;

    my @stems = $self->stemmer->stemWord($word);

    $word = [ sort @stems ]->[0]
        if @stems;

    return $word;
}

sub _get_sentences {
    my ($self) = @_;

    unless ( @{ $self->sentences } ) {
        my $contents = $self->file ? read_text( $self->file ) : $self->text;
        $self->sentences( get_sentences($contents) );
    }

    return map { $_ } @{ $self->sentences };
}

1;
__END__

=head1 SEE ALSO

The F<eg/> and F<t/> scripts

L<Moo>

L<File::Slurper>

L<Lingua::EN::Sentence>

L<Statistics::Lite>

L<Try::Tiny>

L<WordNet::QueryData> and L<WordNet::stem> for stemming

L<https://www.cs.uic.edu/~liub/FBS/sentiment-analysis.html#lexicon>

L<http://saifmohammad.com/WebPages/NRC-Emotion-Lexicon.htm>

L<http://techn.ology.net/book-of-revelation-sentiment-analysis/> is a write-up using this technique.

L<https://ai.stanford.edu/~amaas/data/sentiment/> is the "Large Movie Review Dataset"

=cut
