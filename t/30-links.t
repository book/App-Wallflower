use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use URI;
use App::Wallflower::LinkExtor;

# setup test data
my @tests = (
    [   '/',
        [   200,
            [ 'Content-Type' => 'text/plain' ],
            File::Spec->catfile( t => 'file-01.html' )
        ],
    ],
    [   '/',
        [   200,
            [ 'Content-Type' => 'text/html' ],
            File::Spec->catfile( t => 'file-01.html' )
        ],
        'mailto:author@example.com',
        '/style.css',
        '/#content',
        '/',
        '/',
        '/news.html',
        '/credits.html',
        '/contact.html',
        '/img/lorem.png',
    ],
);

plan tests => 1 + @tests;

my $le = App::Wallflower::LinkExtor->new();
isa_ok( $le, 'App::Wallflower::LinkExtor' );

for my $t (@tests) {
    my ( $url, $response, @expected ) = @$t;
    is_deeply( [ $le->links( $response, $url ) ],
        \@expected, "links for $response->[2]" );
}
