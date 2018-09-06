use strict;
use warnings;
use Path::Tiny ();

exec $^X, Path::Tiny->new( bin => 'wallflower' ),
  '--application' => Path::Tiny->new( t => 'test.psgi' ),
  '--tap',
  ;
