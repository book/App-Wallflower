package App::Wallflower;

use strict;
use warnings;

use Plack::Util ();
use Path::Class;
use URI;
use Carp;

our $VERSION = '1.000';

# quick accessors
for my $attr (qw( application destination env index )) {
    no strict 'refs';
    *$attr = sub { $_[0]{$attr} };
}

# create a new instance
sub new {
    my ( $class, %args ) = @_;
    my $self = bless {
        destination => Path::Class::Dir->new(),    # File::Spec->curdir
        env         => {},
        index       => 'index.html',
        %args,
    }, $class;

    # some basic parameter checking
    croak "application is required" if !defined $self->application;
    croak "destination is invalid"
        if !-e $self->destination || !-d $self->destination;

    return $self;
}

# url -> file converter
sub target {
    my ( $self, $uri ) = @_;

    # the URI must have a path
    croak "$uri has an empty path" if !length $uri->path;

    # absolute paths have the empty string as their first path_segment
    my @segments = $uri->path_segments;
    croak "$uri is not an absolute URI" if length( shift @segments );

    # assume directory if the last segment has no extension
    push @segments, $self->index if $segments[-1] !~ /\./;

    # generate target file name
    return Path::Class::File->new( $self->destination, @segments );
}

# save the URL to a file
sub get {
    my ( $self, $uri ) = @_;
    my ( $status, $headers, $file, $content ) = ( 500, [], '', '' );

    $uri = URI->new($uri) if !ref $uri;

    # setup the environment
    my $env = {

        # current environment
        %ENV,

        # overridable defaults
        'psgi.errors' => \*STDERR,

        # current instance defaults
        %{ $self->env },

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
        croak "Delayed response and streaming not supported yet";
    }
    else { croak "Unknown response from application: $res"; }

    # save the content to a file
    if ( $status eq '200' ) {

        # get a file to save the content in
        my $dir = ( $file = $self->target($uri) )->dir;
        $dir->mkpath if !-e $dir;
        open my $fh, '>', $file or croak "Can't open $file for writing: $!";

        # copy content to the file
        if ( ref $content eq 'ARRAY' ) {
            print $fh @$content;
        }
        elsif ( ref $content eq 'GLOB' ) {
            local $/ = \8192;
            print {$fh} $_ while <$content>;
            close $content;
        }
        elsif ( eval { $content->can('getline') } ) {
            local $/ = \8192;
            while ( defined( my $line = $content->getline ) ) {
                print {$fh} $line;
            }
            $content->close;
        }
        else {
            croak "Don't know how to handle body: $content";
        }

        # finish
        close $fh;
    }

    return [ $status, $headers, $file ];
}

1;

__END__

=head1 NAME

App::Wallflower - Class performing the moves for the wallflower program

=head1 SYNOPSIS

    use App::Wallflower;

    my $w = App::Wallflower->new(
        application => $app, # a PSGI app
        destination => $dir, # target directory
    );

    # dump all URL from $app to files in $dir
    $w->get( $_ ) for @urls;

=head1 DESCRIPTION

This module contains the core functionality of the L<wallflower> program,
that provides user-friendly functionality.

=head1 METHODS

=head2 new( %args )

Create a new L<App::Wallflower> object.

The parameters are:

=over 4

=item C<application>

The PSGI/Plack application, as a CODE reference.

This parameter is I<required>.

=item C<destination>

The destination directory. By default, will use the current directory.

=item C<env>

Additional environment key/value pairs.

=item C<index>

The default file name for URL ending with a C</>.
The default value is F<index.html>.

=back


=head2 get( $url )

Perform a C<GET> request for C<$url> through the application, and
in case of success, save the result to a file, whose name is obtained
via the C<target()> method.

C<$url> may be either a string or a L<URI> object, representing an
absolute URL (the path must start with a C</>). The scheme, host and port
elements are optional. The query string will be ignored.

The return value is very similar those of a L<Plack> application:

   [ $status, $headers, $file ]

where C<$status> and C<$headers> are those return by the application
itself for the given C<$url>, and C<$file> is the name of the file where
the content has been saved.

=head2 target( $uri )

Return the filename where the content of C<$uri> will be saved.
The result depends on the C<destination> and C<index> attributes.

Note that target assumes C<$uri> is a L<URI> object.

=head1 ACCESSORS

Accessors (that are both getters and setters) exist for all parameters
to C<new()> and bear the same name.

=head1 AUTHOR

Philippe Bruhat (BooK)

=head1 COPYRIGHT

Copyright 2010-2012 Philippe Bruhat (BooK), all rights reserved.

=head1 LICENSE

This program is free software and is published under the same
terms as Perl itself.

=cut

