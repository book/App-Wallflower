package App::Wallflower;

use strict;
use warnings;

use Getopt::Long qw( GetOptionsFromArray );
use Pod::Usage;
use Plack::Util ();
use Wallflower;
use Wallflower::Util qw( links_from );
use Module::Load;
use Module::Load::Conditional;

sub new_with_options {
    my ( $class, $args ) = @_;
    my $input = (caller)[1];

    # save previous configuration
    my $save = Getopt::Long::Configure();

    # ensure we use Getopt::Long's default configuration
    Getopt::Long::ConfigDefaults();

    # get the command-line options (modifies $args)
    my %option = (
        follow      => 1,
        environment => 'deployment',
        host        => ['localhost']
    );
    GetOptionsFromArray(
        $args,           \%option,
        'application=s', 'destination|directory=s',
        'index=s',       'environment=s',
        'follow!',       'filter|files|F',
        'quiet',         'include|INC=s@',
        'host=s@',
        'help',          'manual',
        'tutorial',
        's3-bucket=s',
        's3-access-key=s',
        's3-secret-key=s',
        's3-acl=s',
        's3-cache-content-types=s',
        's3-cache-time=s',
        's3-delete-unused'
    ) or pod2usage(
        -input   => $input,
        -verbose => 1,
        -exitval => 2,
    );

    # restore Getopt::Long configuration
    Getopt::Long::Configure($save);

    # simple on-line help
    pod2usage( -verbose => 1, -input => $input ) if $option{help};
    pod2usage( -verbose => 2, -input => $input ) if $option{manual};
    pod2usage(
        -verbose => 2,
        -input   => do {
            require Pod::Find;
            Pod::Find::pod_where( { -inc => 1 }, 'Wallflower::Tutorial' );
        },
    ) if $option{tutorial};

    # application is required
    pod2usage(
        -input   => $input,
        -verbose => 1,
        -exitval => 2,
        -message => 'Missing required option: application'
    ) if !exists $option{application};

    if(defined($option{'s3-bucket'})) {

        my $use_list = {
            'Net::Amazon::S3' => 0.59,
            'Digest::MD5' => undef,
        };
        Module::Load::Conditional::can_load(modules => $use_list) 
            || croak("Can not load Net::Amazon::S3 or Digest::MD5 for Amazon S3 support");

        map { 
            Module::Load::load($_);
        } keys %$use_list;

        # if a s3-bucket is specified we require keys
        $option{'s3-access-key'} ||= $ENV{AWS_ACCESS_KEY};
        $option{'s3-secret-key'} ||= $ENV{AWS_SECRET_KEY};
        
        foreach my $name ('s3-access-key', 's3-secret-key') {
            pod2usage(
                -input   => $input,
                -verbose => 1,
                -exitval => 2,
                -message => 'Missing required option: ' . $name
                ) if !exists($option{$name});
        }

        $option{'s3-acl'} ||= 'public-read';

        if(defined($option{'s3-cache-time'}) && $option{'s3-cache-time'} !~ /^\d+$/) {
            croak("S3 cache time must be an integer");
        }
    }
        
    # include option
    my $path_sep = $Config::Config{path_sep} || ';';
    $option{inc} = [ split /\Q$path_sep\E/, join $path_sep,
        @{ $option{include} || [] } ];

    local $ENV{PLACK_ENV} = $option{environment};
    local @INC = ( @{ $option{inc} }, @INC );
    return bless {
        option     => \%option,
        args       => $args,
        seen       => {},
        wallflower => Wallflower->new(
            application => Plack::Util::load_psgi( $option{application} ),
            ( destination => $option{destination} )x!! $option{destination},
            ( index       => $option{index}       )x!! $option{index},
        ),
    }, $class;

}

sub run {
    my ($self) = @_;
    ( my $args, $self->{args} ) = ( $self->{args}, [] );
    my $method = $self->{option}{filter} ? '_process_args' : '_process_queue';
    $self->$method(@$args);
}

sub _process_args {
    my $self = shift;
    local @ARGV = @_;
    my @urls;
    while (<>) {
        # ignore blank lines and comments
        next if /^\s*(#|$)/;
        chomp;
        push @urls, $_;
    }
    $self->_process_queue(@urls);
}

sub _process_queue {
    my ( $self, @queue ) = @_;
    my ( $quiet, $follow, $seen )
        = @{ $self->{option} }{qw( quiet follow seen )};
    my $wallflower = $self->{wallflower};
    my $host_ok    = $self->_host_regexp;


    my $s3;
    my $s3_bucket;
    my $s3_bucket_contents = {};
    
    if($self->{option}->{'s3-bucket'}) {
        $s3 = Net::Amazon::S3->new({
            aws_access_key_id     => $self->{option}->{'s3-access-key'},
            aws_secret_access_key => $self->{option}->{'s3-secret-key'},
            retry                 => 1,
                                   });
        
        $s3_bucket = $s3->bucket($self->{option}->{'s3-bucket'}) || croak("S3 bucket does not exist: " . $self->{option}->{'s3-bucket'});
        my $bucket_list = $s3_bucket->list_all() || croak("Error getting list of S3 bucket:" .  $s3->err . ": " . $s3->errstr);
        foreach my $key ( @{ $bucket_list->{keys} } ) {
            $s3_bucket_contents->{$key->{key}} = $key;
        }
    }
    

    # I'm just hanging on to my friend's purse
    local $ENV{PLACK_ENV} = $self->{option}{environment};
    local @INC = ( @{ $self->{option}{inc} }, @INC );
    @queue = ('/') if !@queue;
    while (@queue) {

        my $url = URI->new( shift @queue );
        next if $seen->{ $url->path }++;
        next if $url->scheme && ! eval { $url->host =~ $host_ok };

        # get the response
        my $response = $wallflower->get($url);
        my ( $status, $headers, $file ) = @$response;


        if(defined($s3_bucket) && ($status == 200 || $status == 304)) {
            # Calculate the MD5 digest for the content, we can compare this to the etag at S3.
            my $contents;
            my $fh;
            open($fh, "<$file") || croak("Failed to open source file: $file, $!");
            {
                local $/ = undef;
                $contents = <$fh>;
            }
            close($fh);
            my $digest = Digest::MD5::md5_hex($contents);

            my $save_path = $url->path;
            $save_path =~ s/^\///;
            if($save_path eq '') {
                $save_path = $self->{option}->{index} || 'index.html';
            }
            
            # Check to see if the content alredy exists on s3 if it does, and the etag matches 
            # don't publish it.
            if(!defined($s3_bucket_contents->{$save_path}) || 
               $s3_bucket_contents->{$save_path}->{etag} ne $digest) {
                # Use HTTP::Headers since there could be multiple headers 
                my $h = HTTP::Headers->new(@$headers);
                my $ct = $h->header('Content-Type');

                my $s3_headers = {
                    'content_type' => $ct,
                    # Make sure the file is publically readable
                    'x-amz-acl' => $self->{option}->{'s3-acl'}
                };

                
                if(defined($ct) && 
                   defined($self->{option}->{'s3-cache-content-types'}) && 
                   defined($self->{option}->{'s3-cache-time'})) {
                    # Set some caching headers if requested
                    
                    foreach my $match (grep /\S/, split /\s*,\s*/, $self->{option}->{'s3-cache-content-types'}) {
                        $match =~ s/\*/\.\+/g;
                        if($ct =~ /$match/) {
                            $s3_headers->{'Cache-Control'} = 'public, max-age=' . $self->{option}->{'s3-cache-time'};
                        }
                    }
                    
                    if(!defined($s3_headers->{'Cache-Control'})) {
                        $s3_headers->{'Cache-Control'} = 'max-age=0, no-cache, must-revalidate, proxy-revalidate';
                    }
                }
                
                print "Setting headers: " . Data::Dumper->Dump([$s3_headers]) . "\n";
                $s3_bucket->add_key_filename($save_path,
                                             "$file",
                                             $s3_headers
                    ) || croak("Failed to save S3 file to $save_path error: " . $s3->err . ": " . $s3->errstr);
            }

            # Mark this new content as being touched so it does not get deleted.
            $s3_bucket_contents->{$save_path}->{wallflower_used} = 1;
        }
            

        # tell the world
        printf "$status %s%s\n", $url->path, $file && " => $file [${\-s $file}]"
            if !$quiet;

        # obtain links to resources
        if ( $status eq '200' && $follow ) {
            push @queue, links_from( $response => $url );
        }

        # follow 301 Moved Permanently
        elsif ( $status eq '301' ) {
            require HTTP::Headers;
            my $l = HTTP::Headers->new(@$headers)->header('Location');
            unshift @queue, $l if $l;
        }
    }


    if(defined($s3_bucket) && $self->{option}->{'s3-delete-unused'}) {
        foreach my $key (sort { length($b) <=> length($a) } grep { !$s3_bucket_contents->{$_}->{wallflower_used} } keys %$s3_bucket_contents) {
            $s3_bucket->delete_key($key) || croak("Failed to delete S3 file $key error: " . $s3->err . ": " . $s3->errstr);
        }
    }
}

sub _host_regexp {
    my ($self) = @_;
    my $re = join '|',
        map { s/\./\\./g; s/\*/.*/g; $_ }
        @{ $self->{option}{host} };
    return qr{^(?:$re)$};
}

1;

# ABSTRACT: Class performing the moves for the wallflower program

=pod

=head1 SYNOPSIS

    # this is the actual code for wallflower
    use App::Wallflower;
    App::Wallflower->new_with_options( \@ARGV )->run;

=head1 DESCRIPTION

L<App::Wallflower> is a container for functions for the L<wallflower>
program.


=method new_with_options( \@argv )

Process options in the provided array reference (modifying it),
and return a object ready to be C<run()>.

See L<wallflower> for the list of options and their usage.

=method run( )

Make L<wallflower> dance.

Process the remaining arguments according to the options,
i.e. either as URLs to save or as files containing lists of URLs to save.

=cut

