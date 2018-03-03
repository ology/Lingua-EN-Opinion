#!perl
use Test::More;
use Test::Exception;

use_ok 'Lingua::EN::Opinion';

my $obj = eval { Lingua::EN::Opinion->new };
isa_ok $obj, 'Lingua::EN::Opinion';

throws_ok {
    $obj = Lingua::EN::Opinion->new( file => 'foo' );
} qr/File foo does not exist/, 'bogus file';

$obj = Lingua::EN::Opinion->new( file => 't/test.txt' );
isa_ok $obj, 'Lingua::EN::Opinion';

my $sentences = [
    'I begin this story with a neutral statement.',
    'Basically this is a very silly test.',
    'You are testing the Lingua::EN::Opinion package using short, inane sentences.',
    'I am actually very happy today.',
    'I have finally finished writing this package.',
    'Tomorrow I will be very sad.',
    "I won't have anything left to do.",
    'I might get angry and decide to do something horrible.',
    'I might destroy the entire package and start from scratch.',
    'Then again, I might find it satisfying to have completed my this package.',
    "You might even say it's beautiful!",
];

my $x = $obj->analyze;
$x = $obj->sentences;
is_deeply $x, $sentences, 'sentences';
$x = $obj->scores;
my $scores = [ 0, -1, -1, 1, 0, -1, 0, -2, -2, 1, 1 ];
is_deeply $x, $scores, 'scores';

my $text = <<'END';
I begin this story with a neutral statement.
Basically this is a very silly test.
You are testing the Lingua::EN::Opinion package using short, inane sentences.
I am actually very happy today.
I have finally finished writing this package.
Tomorrow I will be very sad.
I won't have anything left to do.
I might get angry and decide to do something horrible.
I might destroy the entire package and start from scratch.
Then again, I might find it satisfying to have completed my this package.
You might even say it's beautiful!
END

$obj = Lingua::EN::Opinion->new( text => $text );
isa_ok $obj, 'Lingua::EN::Opinion';
my $x = $obj->analyze;
$x = $obj->sentences;
is_deeply $x, $sentences, 'sentences';
$x = $obj->scores;
my $scores = [ 0, -1, -1, 1, 0, -1, 0, -2, -2, 1, 1 ];
is_deeply $x, $scores, 'scores';

done_testing();
