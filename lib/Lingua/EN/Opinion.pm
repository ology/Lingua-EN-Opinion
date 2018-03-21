package Lingua::EN::Opinion;

# ABSTRACT: Measure the emotional sentiment of text

our $VERSION = '0.09';

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
  my $opinion = Lingua::EN::Opinion->new( file => '/some/file.txt' );
  $opinion->analyze();
  my $score = $opinion->averaged_score(5);
  my $sentiment = $opinion->get_word('foo');
  $sentiment = $opinion->get_sentence('Mary had a little lamb.');
  # OR
  $opinion = Lingua::EN::Opinion->new( text => 'Mary had a little lamb...' );
  $opinion->nrc_sentiment();
  # And now do something cool with $opinion->nrc_scores...
  $sentiment = $opinion->nrc_get_word('foo');
  $sentiment = $opinion->nrc_get_sentence('Mary had a little lamb.');

=head1 DESCRIPTION

A C<Lingua::EN::Opinion> measures the emotional sentiment of text.

* This module is large because of the GIANT sentiment text it comes with.

Please see the F<eg/> and F<t/> scripts for example usage.

The write-up illustrating results can be found at
L<http://techn.ology.net/book-of-revelation-sentiment-analysis/>

=head1 ATTRIBUTES

=head2 file

The text file to analyze.

=cut

has file => (
    is  => 'ro',
    isa => sub { die "File $_[0] does not exist" unless -e $_[0] },
);

=head2 text

A text string to analyze instead of a text file.

=cut

has text => (
    is => 'ro',
);

=head2 stem

Boolean flag to indicate that word stemming should take place.

=cut

has stem => (
    is      => 'ro',
    default => sub { 0 },
);

=head2 stemmer

Require the L<WordNet::stem> and L<WordNet::QueryData> modules to stem each word
of the provided file or text.

* These modules must be installed and working to use this feature.

=cut

has stemmer => (
    is       => 'ro',
    lazy     => 1,
    builder  => 1,
    init_arg => undef,
);

sub _build_stemmer {
    try {
        require WordNet::QueryDataX;
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

Computed result.

=cut

has sentences => (
    is       => 'rw',
    init_arg => undef,
    default  => sub { [] },
);

=head2 scores

Computed result.

=cut

has scores => (
    is       => 'rw',
    init_arg => undef,
    default  => sub { [] },
);

=head2 nrc_scores

Computed result.

=cut

has nrc_scores => (
    is       => 'rw',
    init_arg => undef,
    default  => sub { [] },
);

=head1 METHODS

=head2 new()

  $opinion = Lingua::EN::Opinion->new(%arguments);

Create a new C<Lingua::EN::Opinion> object.

=head2 analyze()

  $opinion->analyze();

Measure the positive/negative emotional sentiment of text.  This method sets the
B<scores> and B<sentences> attributes.

=cut

sub analyze {
    my ($self) = @_;

    unless ( @{ $self->sentences } ) {
        my $contents = $self->file ? read_text( $self->file ) : $self->text;

        $self->sentences( get_sentences($contents) );
    }

    my @sentences = map { $_ } @{ $self->sentences };

    my @scores;

    my $positive = Lingua::EN::Opinion::Positive->new();
    my $negative = Lingua::EN::Opinion::Negative->new();

    for my $sentence ( @sentences ) {
        my @words = _tokenize($sentence);

        my $score = 0;

        for my $word ( @words ) {
            $word = $self->_stemword($word);

            $score += exists $positive->wordlist->{$word} ? 1
                    : exists $negative->wordlist->{$word} ? -1 : 0;
        }

        push @scores, $score;
    }

    $self->scores( \@scores );
}

=head2 averaged_score()

  $averaged = $opinion->averaged_score($bins);

Compute the averaged score given a number of (integer) B<bins> (default: 10).

This reduces the amount of "noise" in the original signal.  As such, it loses
information detail.

For example, if there are 400 sentences, B<bins> of 10 will result in 40 data
points.  Each point will be the mean of each successive bin-sized set of points
in the analyzed score.

=cut

sub averaged_score {
    my ( $self, $bins ) = @_;

    $bins ||= 10;

    my @scores = map { $_ } @{ $self->scores };

    my @averaged;

    while ( my @n = splice @scores, 0, $bins ) {
        push @averaged, mean(@n);
    }

    return \@averaged;
}

=head2 nrc_sentiment()

  $opinion->nrc_sentiment();

Compute the NRC sentiment of the given text by sentences.

This is given by a 0/1 list of these 10 emotional elements:

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

sub nrc_sentiment {
    my ($self) = @_;

    my $null_state = { anger=>0, anticipation=>0, disgust=>0, fear=>0, joy=>0, negative=>0, positive=>0, sadness=>0, surprise=>0, trust=>0 };

    unless ( @{ $self->sentences } ) {
        my $contents = $self->file ? read_text( $self->file ) : $self->text;

        $self->sentences( get_sentences($contents) );
    }

    my @sentences = map { $_ } @{ $self->sentences };

    my @scores;

    my $emotion = Lingua::EN::Opinion::Emotion->new();

    for my $sentence ( @sentences ) {
        my @words = _tokenize($sentence);

        my $score;

        for my $word ( @words ) {
            $word = $self->_stemword($word);

            if ( exists $emotion->wordlist->{$word} ) {
                for my $key ( keys %{ $emotion->wordlist->{$word} } ) {
                    $score->{$key} += $emotion->wordlist->{$word}{$key};
                }
            }
        }

        $score = $null_state
            unless $score;

        push @scores, $score;
    }

    $self->nrc_scores( \@scores );
}

=head2 get_word()

  $sentiment = $opinion->get_word($word);

Get the positive/negative sentiment for a given word.  Return a HashRef of
positive/negative keys.  If the word does not exist, return C<undef>.

=cut

sub get_word {
    my ( $self, $word ) = @_;

    $word = $self->_stemword($word);

    my $positive = Lingua::EN::Opinion::Positive->new();
    my $negative = Lingua::EN::Opinion::Negative->new();

    return exists $positive->wordlist->{$word} || exists $negative->wordlist->{$word}
        ? {
            positive => exists $positive->wordlist->{$word} ? 1 : 0,
            negative => exists $negative->wordlist->{$word} ? 1 : 0,
        }
        : undef;
}

=head2 nrc_get_word()

  $sentiment = $opinion->nrc_get_word($word);

Get the NRC emotional sentiment for a given word.  Return a HashRef of the NRC
emotions.  If the word does not exist, return C<undef>.

=cut

sub nrc_get_word {
    my ( $self, $word ) = @_;

    $word = $self->_stemword($word);

    my $emotion = Lingua::EN::Opinion::Emotion->new();

    return exists $emotion->wordlist->{$word}
        ? $emotion->wordlist->{$word}
        : undef;
}

=head2 get_sentence()

  $values = $opinion->get_sentence($sentence);

Return the positive/negative values for the words of the given sentence.

=cut

sub get_sentence {
    my ( $self, $sentence ) = @_;

    my @words = _tokenize($sentence);

    my %score;

    for my $word ( @words ) {
        $word = $self->_stemword($word);
        $score{$word} = $self->get_word($word);
    }

    return \%score;
}

=head2 nrc_get_sentence()

  $values = $opinion->nrc_get_sentence($sentence);

Return the NRC emotion values for each word of the given sentence.

=cut

sub nrc_get_sentence {
    my ( $self, $sentence ) = @_;

    my @words = _tokenize($sentence);

    my %score;

    for my $word ( @words ) {
        $word = $self->_stemword($word);
        $score{$word} = $self->nrc_get_word($word);
    }

    return \%score;
}

sub _tokenize {
    my ($sentence) = @_;
    $sentence =~ s/[[:punct:]]//g;  # Drop punctuation
    my @words = split /\s+/, $sentence;
    return @words;
}

sub _stemword {
    my ( $self, $word ) = @_;

    if ( $self->stem ) {
        my @stems = $self->stemmer->stemWord($word);
        $word = [ sort @stems ]->[0]
            if @stems;
    }

    return $word;
}

1;
__END__

=head1 SEE ALSO

L<Moo>

L<File::Slurper>

L<Lingua::EN::Sentence>

L<Statistics::Lite>

L<https://www.cs.uic.edu/~liub/FBS/sentiment-analysis.html#lexicon>

L<http://saifmohammad.com/WebPages/NRC-Emotion-Lexicon.htm>

L<http://techn.ology.net/book-of-revelation-sentiment-analysis/>

=cut
