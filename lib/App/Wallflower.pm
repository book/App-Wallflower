package App::Wallflower;

use strict;
use warnings;

use Plack::Util ();
use File::Spec  ();
use File::Path qw( mkpath );
use Path::Class;
use URI;

# quick accessors
for my $attr (qw( application destination env index )) {
    no strict 'refs';
    *$attr = sub { $_[0]{$attr} };
}

# create a new instance
sub new {
    my ( $class, %args ) = @_;
    return bless {
        env         => {},
        destination => File::Spec->curdir,
        index       => 'index.html',
        %args,
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

# save the URL to a file
sub get {
    my ( $self, $uri ) = @_;
    my ( $status, $headers, $file, $content ) = ( 500, [], '', '' );

    $uri = URI->new($uri) if !ref $uri;

    # require an absolute path
    return [ $status, $headers, $file ] if $uri->path !~ /^\//;

    # setup the environment
    my $env = {
        %ENV,               # current environment
        %{ $self->env },    # current instance defaults

        # request-related environment variables
        REQUEST_METHOD => 'GET',

        # TODO properly deal with SCRIPT_NAME and PATH_INFO with mounts
        SCRIPT_NAME     => '',
        PATH_INFO       => $uri->path,
        REQUEST_URI     => $uri->path,
        QUERY_STRING    => '',
        SERVER_NAME     => 'localhost',
        SERVER_PORT     => '80',
        SERVER_PROTOCOL => "HTTP/1.0",

        # wallflower defaults
        'psgi.streaming' => '',
    };

    # get the content
    my $res = Plack::Util::run_app( $self->application, $env );

    if ( ref $res eq 'ARRAY' ) {
        ( $status, $headers, $content ) = @$res;
    }
    elsif ( ref $res eq 'CODE' ) {
        die "Delayed response and streaming not supported yet";
    }
    else { die "Unknown response from application: $res"; }

    # save the content to a file
    if ( $status eq '200' ) {

        # get a file to save the content in
        my $dir = ( $file = $self->target($uri) )->dir;
        mkpath $dir if !-e $dir;
        open my $fh, '>', $file or die "Can't open $file for writing: $!";

        # copy content to the file
        if ( ref $content eq 'ARRAY' ) {
            print $fh @$content;
        }
        elsif ( ref $content eq 'GLOB' ) {
            print {$fh} <$content>;
        }
        elsif ( eval { $content->can('getlines') } ) {
            print {$fh} $content->getlines;
        }
        else {
            die "Don't know how to handle $content";
        }

        # finish
        close $fh;
    }

    return [ $status, $headers, $file ];
}

1;
