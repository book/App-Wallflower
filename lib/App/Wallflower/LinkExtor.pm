package App::Wallflower::LinkExtor;

use strict;
use warnings;

use HTTP::Headers;
use HTML::LinkExtor;

# some code to obtain links to resources
my %linkextor = (
    'text/html'                     => \&_links_from_html,
    'text/x-server-parsed-html'     => \&_links_from_html,
    'application/xhtml+xml'         => \&_links_from_html,
    'application/vnd.wap.xhtml+xml' => \&_links_from_html,
    'text/css'                      => \&_links_from_css,
);

sub new { bless {}, $_[0] }

sub links {
    my ( $self, $response, $url ) = @_;
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
    $parser->parse_file($file);
    return @links;
}

# CSS
my $css_regexp = qr{
    (?:
      \@import\s+(?:"([^"]+)"|'([^']+)')
    | url\(([^)]+)\)
    )
}x;
sub _links_from_css {
    my ( $file, $url ) = @_;

    my $content = do { local ( @ARGV, $/ ) = ($file); <> };
    return grep defined, $content =~ /$css_regexp/gc;
}

1;

__END__

=head1 NAME

App::Wallflower::LinkExtor - Basic resource link extractor for App::Wallflower

=head SYNOPSIS

    use App::Wallflower::LinkExtor;

    # use App::Wallflower to get a response array
    my $wf = App::Wallflower->new( application => $app, destination => $dir );
    my $response = $wf->get($url);

    # obtain links to resources linked from the document
    my $le = App::Wallflower::LinkExtor->new();
    my @links = $le->links( $response, $url );

    # the object has no attributes, so both forms are equivalent
    my @links = App::Wallflower::LinkExtor->links( $response, $url );

=head1 DESCRIPTION

This module provides a single method to be used on the data structures
returned by L<App::Wallflower>'s C<get()> method.

=head1 METHODS

=head2 new()

Dummy constructor.

The object has no attributes, therefore all methods can be called as
class methods.

=head2 links( $response, $url )

Returns all links found in the response body, depending on its content type.

C<$response> is the array reference returned by L<App::Wallflower>'s C<get()>
method. C<$url> is the base URI for resolving relative links, i.e. the
original argument to C<get()>.

=head1 AUTHOR

Philippe Bruhat (BooK)

=head1 COPYRIGHT

Copyright 2012 Philippe Bruhat (BooK), all rights reserved.

=head1 LICENSE

This program is free software and is published under the same
terms as Perl itself.

=cut

