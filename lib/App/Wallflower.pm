package App::Wallflower;

use strict;
use warnings;

use Getopt::Long qw( GetOptionsFromArray );
use Pod::Usage;
use Plack::Util ();
use Wallflower;
use Wallflower::Util qw( links_from );

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
        'server-name=s',
        'scheme=s',
        'help',          'manual',
        'tutorial',
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
            ( server_name => $option{server-name} )x!! $option{server-name},
            ( scheme      => $option{scheme}      )x!! $option{scheme},
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
    while (<>) {

        # ignore blank lines and comments
        next if /^\s*(#|$)/;
        chomp;

        $self->_process_queue("$_");
    }
}

sub _process_queue {
    my ( $self, @queue ) = @_;
    my ( $quiet, $follow, $seen )
        = @{ $self->{option} }{qw( quiet follow seen )};
    my $wallflower = $self->{wallflower};
    my $host_ok    = $self->_host_regexp;

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

