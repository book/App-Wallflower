package Wallflower;

use strict;
use warnings;

use Plack::Util ();
use Path::Class;
use URI;
use HTTP::Date qw( time2str );
use Carp;

# quick getters
for my $attr (qw( application destination env index server_name scheme )) {
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

    # URI ending with / have the empty string as their last path_segment
    my @segments = $uri->path_segments;
    $segments[-1] = $self->index if $segments[-1] eq '';

    # generate target file name
    return Path::Class::File->new( $self->destination, @segments );
}

# save the URL to a file
sub get {
    my ( $self, $uri ) = @_;
    $uri = URI->new($uri) if !ref $uri;

    # absolute paths have the empty string as their first path_segment
    croak "$uri is not an absolute URI"
        if $uri->path && length +( $uri->path_segments )[0];

    # setup the environment
    my $env = {

        # current environment
        %ENV,

        # overridable defaults
        'psgi.errors' => \*STDERR,

        # current instance defaults
        %{ $self->env },
        ('psgi.url_scheme' => $self->scheme )x!! $self->scheme,

        # request-related environment variables
        REQUEST_METHOD => 'GET',

        # TODO properly deal with SCRIPT_NAME and PATH_INFO with mounts
        SCRIPT_NAME     => '',
        PATH_INFO       => $uri->path,
        REQUEST_URI     => $uri->path,
        QUERY_STRING    => '',
        SERVER_NAME     => $self->server_name || 'localhost',
        SERVER_PORT     => ($self->scheme || '') eq 'https' ? 443 : 80,
        SERVER_PROTOCOL => "HTTP/1.0",

        # wallflower defaults
        'psgi.streaming' => '',
    };

    # add If-Modified-Since headers if the target file exists
    my $target = $self->target($uri);
    $env->{HTTP_IF_MODIFIED_SINCE} = time2str( ( stat _ )[9] ) if -e $target;

    # fixup URI (needed to resolve relative URLs in retrieved documents)
    $uri->scheme($self->scheme || 'http') if !$uri->scheme;
    $uri->host( $env->{SERVER_NAME} ) if !$uri->host;

    # get the content
    my ( $status, $headers, $file, $content ) = ( 500, [], '', '' );
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
        my $dir = ( $file = $target )->dir;
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

# ABSTRACT: Stick Plack applications to the wallpaper

=pod

=head1 SYNOPSIS

    use Wallflower;

    my $w = Wallflower->new(
        application => $app, # a PSGI app
        destination => $dir, # target directory
    );

    # dump all URL from $app to files in $dir
    $w->get( $_ ) for @urls;

=head1 DESCRIPTION

Given a URL and a L<Plack> application, a L<Wallflower> object will
save the corresponding response to a file.

=method new( %args )

Create a new L<Wallflower> object.

The parameters are:

=over 4

=item C<application>

The PSGI/Plack application, as a CODE reference.

This parameter is I<required>.

=item C<destination>

The destination directory. Default is the current directory.

The destination directory must exist.

=item C<env>

Additional environment key/value pairs.

=item C<index>

The default filename for URLs ending in C</>.
The default value is F<index.html>.

=item C<server_name>

Server name you deploy (Optional)

=item C<scheme>

URL scheme you use in production (Optional)

=back

=method get( $url )

Perform a C<GET> request for C<$url> through the application, and
if successful, save the result to a filename derived from C<$url> by
the C<target()> method.

C<$url> can be either a string or a L<URI> object, representing an
absolute URL (the path must start with a C</>). The scheme, host, port,
and query string are ignored if present.

The return value is very similar to a L<Plack> application's:

   [ $status, $headers, $file ]

where C<$status> and C<$headers> are those returned by the application
itself for the given C<$url>, and C<$file> is the name of the file where
the content has been saved.

If a file exists at the location pointed to by the target, a
C<If-Modified-Since> header is added to the Plack environment,
with the modification timestamp for this file as the value.
If the application sends a C<304 Not modified> in response,
the target file will not be modified.

=method target( $uri )

Return the filename where the content of C<$uri> will be saved.

The C<path> component of C<$uri> is concatenated to the C<destination>
attribute. If the URL ends with a C</>, the C<index> attribute is appended
to create a file path.

Note that C<target()> assumes C<$uri> is a L<URI> object, and that it
must be absolute.

=head1 ACCESSORS

Accessors (getters only) exist for all parameters
to C<new()> and bear the same name.

=cut

