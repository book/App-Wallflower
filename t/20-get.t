use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use App::Wallflower;

my $dir = tempdir( CLEANUP => 1 );
my $app = sub {
    return [
        200, [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
        ['Hello,', ' ', 'World!']
    ];
};

my $wf = App::Wallflower->new(
    application => $app,
    destination => $dir,
);

plan tests => 2;

my $result = $wf->get('/');
is_deeply(
    $result,
    [   200,
        [ 'Content-Type' => 'text/plain', 'Content-Length' => 13 ],
        File::Spec->catfile( $dir, 'index.html' )
    ],
    'hello app'
);

my $file = $result->[2];
my $content = do { local $/; local @ARGV = ( $file ); <> };
is( $content, 'Hello, World!', 'hello content' );

