use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use URI;
use Wallflower::Util qw( links_from );

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
    [   '/',
        [   200,
            [ 'Content-Type' => 'text/css' ],
            File::Spec->catfile( t => 'file-01.css' )
        ],
        '/foo.css', '/bar.css', '/img.png', '/img_qq.png', '/img_q.png'
    ],
);

plan tests => scalar @tests;

for my $t (@tests) {
    my ( $url, $response, @expected ) = @$t;
    is_deeply( [ links_from( $response, $url ) ],
        \@expected, "links for $response->[2]" );
}
