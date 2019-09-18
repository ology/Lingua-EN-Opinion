# :!plackup %

use Plack::Builder;
use Plack::Request;
use Encode 'encode_utf8';
use Template;
use lib 'lib';
use Lingua::EN::Opinion;
use Data::Dumper;
$Data::Dumper::Quotekeys = 0;
$Data::Dumper::Varname   = 'score';

my $template =<<HTML;
<html><body>
<h1>Lingua::EN::Opinion!</h1>
<form action="/" method="POST">
<textarea name="text" rows="10" cols="30">
[% text %]
</textarea>
<br>
<input type="submit" value="Evaluate" />
</form>
<pre>[% score %]</pre>
<p>
NRC: <pre>[% nrc_score %]</pre>
</body></html>
HTML

my $default = 'The quick onyx goblin jumps over the lazy dwarf.';

builder {
    mount '/' => sub {
        my $req = Plack::Request->new(shift);
        my $sentence = $req->param('text') || $default;

        my $opinion = Lingua::EN::Opinion->new();

        my $score = $opinion->get_sentence($sentence);
        for my $item ( keys %$score ) {
            if ( $score->{$item} ) {
                $score->{$item} = $score->{$item}{positive} ? 1 : -1;
            }
            else {
                delete $score->{$item};
            }
        }

        my $nrc_score = $opinion->nrc_get_sentence($sentence);
        for my $item ( keys %$nrc_score ) {
            delete $nrc_score->{$item}
                unless $nrc_score->{$item};
        }

        my $body;
        Template->new->process(\$template, {
            text      => $sentence,
            score     => Dumper($score),
            nrc_score => Dumper($nrc_score),
        }, \$body);

        my $res = $req->new_response(200);
        $res->content_type('text/html; charset=utf-8');
        $res->body(encode_utf8 $body);
        $res->finalize;
    }
};
