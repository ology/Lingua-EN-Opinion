package Lingua::EN::Opinion;

# ABSTRACT: Measure the positive/negative sentiment of text

our $VERSION = '0.01';

use Moo;
use strictures 2;
use namespace::clean;

use Lingua::EN::Opinion::Positive;
use Lingua::EN::Opinion::Negative;

use File::Slurper qw( read_text );
use Lingua::EN::Sentence qw( get_sentences );

=head1 SYNOPSIS

  use Lingua::EN::Opinion;
  my $opinion = Lingua::EN::Opinion->new( file => '/some/file.txt' );
  $opinion->analyze();
  my $sentences = $opinion->sentences;
  my $scores = $opinion->scores;

=head1 DESCRIPTION

A C<Lingua::EN::Opinion> measures the positive/negative sentiment of text.

=head1 ATTRIBUTES

=head2 file

The text file to analyze.

=cut

has file => (
    is  => 'ro',
    isa => sub { die "File $_[0] does not exist" unless -e $_[0] },
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

=head1 METHODS

=head2 new()

  $opinion = Lingua::EN::Opinion->new(%arguments);

Create a new C<Lingua::EN::Opinion> object.

=head2 analyze()

  $score = $opinion->analyze();

Measure the positive/negative sentiment of text.

=cut

sub analyze {
    my ($self) = @_;

    my $contents = read_text( $self->file );

    $self->sentences( get_sentences($contents) );

    my @scores;

    my $positive = Lingua::EN::Opinion::Positive->new();
    my $negative = Lingua::EN::Opinion::Negative->new();

    for my $sentence ( @{ $self->sentences } ) {
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

1;
__END__

=head1 SEE ALSO

L<Moo>

L<File::Slurper>

L<Lingua::EN::Sentence>

L<https://www.cs.uic.edu/~liub/FBS/sentiment-analysis.html#lexicon>

=head1 TO DO

Transform the scores into binned percentages.

=cut
