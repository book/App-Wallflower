package Wallflower::Util;

use strict;
use warnings;

use Exporter;
use HTTP::Headers;
use HTML::LinkExtor;
use Path::Canonical ();

our @ISA = qw( Exporter );
our @EXPORT_OK = qw( links_from );

# some code to obtain links to resources
my %linkextor = (
    'text/html'                     => \&_links_from_html,
    'text/x-server-parsed-html'     => \&_links_from_html,
    'application/xhtml+xml'         => \&_links_from_html,
    'application/vnd.wap.xhtml+xml' => \&_links_from_html,
    'text/css'                      => \&_links_from_css,
);

sub links_from {
    my ( $response, $url ) = @_;
    my $le = $linkextor{ HTTP::Headers->new( @{ $response->[1] } )
            ->content_type };
    return if !$le;
    return $le->( $response->[2], $url );
}

# HTML
sub _links_from_html {
    my ( $file, $url ) = @_;
    my @links;
    my $parser = HTML::LinkExtor->new(
        sub {
            my ( $tag, @pairs ) = @_;
            my $i = 0;
            push @links, grep $i++ % 2, @pairs;
        },
        $url
    );
    $parser->parse_file("$file");
    return @links;
}

# CSS
my $css_regexp = qr{
    (?:
      \@import\s+(?:"([^"]+)"|'([^']+)')
    | url\((?:"([^"]+)"|'([^']+)'|([^)]+))\)
    )
}x;
sub _links_from_css {
    my ( $file, $url ) = @_;

    my $content = do { local ( @ARGV, $/ ) = ("$file"); <> };
    return map { _expand_link($url, $_) } grep defined, $content =~ /$css_regexp/gc;
}

sub _expand_link {
    my ($base, $link) = @_;
    $base = $base->path if ref $base;

    if ($link =~ m!\A[-+.a-zA-Z0-9]+://!ms || $link =~ m!\A/!ms ) {
        return $link
    }

    $base =~ s![^/]+$!!;
    $base .= '/' if $base !~ m!/$!;

    Path::Canonical::canon_path($base . $link)
}

1;

# ABSTRACT: Utility functions for Wallflower

=pod

=head1 SYNOPSIS

    use Wallflower;
    use Wallflower::Util qw( links_from );

    # use Wallflower to get a response array
    my $wf = Wallflower->new( application => $app, destination => $dir );
    my $response = $wf->get($url);

    # obtain links to resources linked from the document
    my @links = links_from( $response, $url );

=head1 DESCRIPTION

This module provides methods to extract links from the files
produced by L<Wallflower>'s C<get()> method.

=func links_from( $response, $url )

Returns all links found in the response body, depending on its content type.

C<$response> is the array reference returned by L<Wallflower>'s C<get()>
method. C<$url> is the base URL for resolving relative links, i.e. the
original argument to C<get()>.

=cut

