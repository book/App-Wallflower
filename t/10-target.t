use strict;
use warnings;
use Test::More;

use File::Spec;
use URI;
use App::Wallflower;

my @tests = (
    [ '/'               => 'index.html' ],
    [ '/kayo/'          => File::Spec->catfile(qw( kayo index.html )) ],
    [ '/kayo'           => File::Spec->catfile(qw( kayo index.html )) ],
    [ '/awk/swoosh.css' => File::Spec->catfile(qw( awk swoosh.css )) ],
    [ '/awk/clash'      => File::Spec->catfile(qw( awk clash index.html )) ],
);

plan tests => scalar @tests;

# pick up a possible destination directory
my $dir = File::Spec->tmpdir;

my $wallflower = App::Wallflower->new(
    destination => $dir,
    application => sub { },    # dummy
);

for my $t (@tests) {
    my ( $uri, $file ) = @$t;
    $file = is( $wallflower->target( URI->new($uri) ),
        File::Spec->catfile( $dir, $file ), $uri );
}

