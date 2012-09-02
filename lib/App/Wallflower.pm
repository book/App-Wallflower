package App::Wallflower;

use strict;
use warnings;
use Path::Class;
use URI;

# quick accessors
for my $attr (qw( destination index ) ) {
    no strict 'refs';
    *$attr = sub { $_[0]{$attr} };
}

# create a new instance
sub new {
    my ( $class, %args ) = @_;
    return bless {
        index => 'index.html',
        %args
    }, $class;
}

# url -> file converter
sub target {
    my ( $self, $uri ) = @_;

    # absolute paths have the empty string as their first path_segment
    my (undef, @segments) = $uri->path_segments;

    # assume directory
    push @segments, $self->index if $segments[-1] !~ /\./;

    # generate target file name
    return Path::Class::File->new( $self->destination, @segments );
}

1;
