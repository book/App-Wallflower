package App::Wallflower::LinkExtor;

use strict;
use warnings;

use HTTP::Headers;
use HTML::LinkExtor;

# some code to obtain links to resources
my %linkextor = (
    'text/html'                     => \&_links_from_html,
);

sub new { bless {}, $_[0] }

sub links {
    my ( $self, $response, $url ) = @_;
    my $le = $linkextor{ HTTP::Headers->new( @{ $response->[1] } )
            ->content_type };
    return if !$le;
    return $le->( $response->[2], $url );
}

# HTML
sub _links_from_html {
    my ( $file, $url ) = @_;
    my @links;
    my $parser = HTML::LinkExtor->new(
        sub {
            my ( $tag, @pairs ) = @_;
            my $i = 0;
            push @links, grep $i++ % 2, @pairs;
        },
        $url
    );
    $parser->parse_file($file);
    return @links;
}

1;

