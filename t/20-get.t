use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use List::Util qw( sum );
use URI;
use App::Wallflower;

# setup test data
my @tests;

# test data is an array ref containing:
# - quick description of the app
# - destination directory
# - the app itself
# - a list of test url for the app
#   as [ url, status, headers, file, content ]

push @tests, [
    'direct content',
    tempdir( CLEANUP => 1 ),
    sub {
        [   200,
            [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
            [ 'Hello,', ' ', 'World!' ]
        ];
    },
    [   '/' => 200,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
        'index.html',
        'Hello, World!'
    ],
    [   URI->new( '/index.htm' ) => 200,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
        'index.htm',
        'Hello, World!'
    ],
    [ 'wrong' => 500, [], '', '' ],
    [   '/klonk/' => 200,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
        File::Spec->catfile( 'klonk', 'index.html' ),
        'Hello, World!'
    ],
];

push @tests, [
    'content in a glob',
    tempdir( CLEANUP => 1 ),
    sub {
        [   200,
            [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
            do {
                my $file = File::Spec->catfile( $tests[0][1], 'index.html' );
                open my $fh, '<', $file or die "Can't open $file: $!";
                $fh;
                }
        ];
    },
    [   '/' => 200,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
        'index.html',
        'Hello, World!'
    ],
];

push @tests, [
    'content in an object',
    tempdir( CLEANUP => 1 ),
    sub {
        [   200,
            [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
            do {
                package Clange;
                sub new { bless [ 'Hello,', ' ', 'World!' ] }
                sub getline { shift @{$_[0]} }
                sub close {}
                __PACKAGE__->new();
            }
        ];
    },
    [   '/' => 200,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
        'index.html',
        'Hello, World!'
    ],
];

plan tests => sum map 2 * ( @$_ - 3 ), @tests;

for my $t (@tests) {
    my ( $desc, $dir, $app, @urls ) = @$t;

    my $wf = App::Wallflower->new(
        application => $app,
        destination => $dir,
    );

    for my $u (@urls) {
        my ( $url, $status, $headers, $file, $content ) = @$u;

        my $result = $wf->get($url);
        is_deeply(
            $result,
            [   $status, $headers, $file && File::Spec->catfile( $dir, $file )
            ],
            "app ($desc) for $url"
        );

        if ( $status eq '200' ) {
            my $file_content
                = do { local $/; local @ARGV = ( $result->[2] ); <> };
            is( $file_content, $content, "content ($desc) for $url" );
        }
        else {
            is( $result->[2], '', "no file ($desc) for $url" );
        }
    }
}
