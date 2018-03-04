package Lingua::EN::Opinion;

# ABSTRACT: Measure the positive/negative sentiment of text

our $VERSION = '0.04';

use Moo;
use strictures 2;
use namespace::clean;

use Lingua::EN::Opinion::Positive;
use Lingua::EN::Opinion::Negative;
use Lingua::EN::Opinion::Emotion;

use File::Slurper qw( read_text );
use Lingua::EN::Sentence qw( get_sentences );
use Statistics::Lite qw( mean );

=head1 SYNOPSIS

  use Lingua::EN::Opinion;
  my $opinion = Lingua::EN::Opinion->new( file => '/some/file.txt' );
  $opinion->analyze();
  my $score = $opinion->averaged_score(5);
  # OR
  $opinion = Lingua::EN::Opinion->new( text => 'Mary had a little lamb...' );
  $opinion->nrc_sentiment();
  # And now do something cool with $opinion->nrc_scores...

=head1 DESCRIPTION

A C<Lingua::EN::Opinion> measures the positive/negative sentiment of text.

NOTE: This module is 3.4MB because of the GIANT sentiment text it comes with.

Please see the F<eg/> and F<t/> scripts for example usage.

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

=head2 sentences

Computed result.

=cut

has sentences => (
    is       => 'rw',
    init_arg => undef,
);

=head2 scores

Computed result.

=cut

has scores => (
    is       => 'rw',
    init_arg => undef,
);

=head2 nrc_scores

Computed result.

=cut

has nrc_scores => (
    is       => 'rw',
    init_arg => undef,
);

=head1 METHODS

=head2 new()

  $opinion = Lingua::EN::Opinion->new(%arguments);

Create a new C<Lingua::EN::Opinion> object.

=head2 analyze()

  $opinion->analyze();

Measure the positive/negative sentiment of text.  This method sets the B<scores>
and B<sentences> attributes.

=cut

sub analyze {
    my ($self) = @_;

    my $contents = $self->file ? read_text( $self->file ) : $self->text;

    $self->sentences( get_sentences($contents) );

    my @sentences = map { $_ } @{ $self->sentences };

    my @scores;

    my $positive = Lingua::EN::Opinion::Positive->new();
    my $negative = Lingua::EN::Opinion::Negative->new();

    for my $sentence ( @sentences ) {
        $sentence =~ s/[[:punct:]]//g;  # Drop punctuation

        my @words = split /\s+/, $sentence;

        my $score = 0;

        for my $word ( @words ) {
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

Compute the NRC sentiment of the given text.

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

=cut

sub nrc_sentiment {
    my ($self) = @_;

    my $null_state = { anger=>0, anticipation=>0, disgust=>0, fear=>0, joy=>0, negative=>0, positive=>0, sadness=>0, surprise=>0, trust=>0 };

    my $contents = $self->file ? read_text( $self->file ) : $self->text;

    $self->sentences( get_sentences($contents) );

    my @sentences = map { $_ } @{ $self->sentences };

    my @scores;

    my $emotion = Lingua::EN::Opinion::Emotion->new();

    for my $sentence ( @sentences ) {
        $sentence =~ s/[[:punct:]]//g;  # Drop punctuation

        my @words = split /\s+/, $sentence;

        for my $word ( @words ) {
            push @scores, exists $emotion->wordlist->{$word}
                ? $emotion->wordlist->{$word} : $null_state;
        }
    }

    $self->nrc_scores( \@scores );
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

=cut
