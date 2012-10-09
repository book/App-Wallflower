use strict;
use warnings;
use 5.006;
use Module::Build;

my $builder = Module::Build->new(
    module_name       => 'App::Wallflower',
    license           => 'perl',
    dist_author       => 'Philippe Bruhat (BooK) <book@cpan.org>',
    dist_version_from => 'lib/Wallflower.pm',
    requires          => {
        'Path::Class' => 0,
        'Plack'       => 0,
        'URI'         => 0,
    },
    build_requires => {
        'Test::More' => 0,
        'List::Util' => 0,
    },
    script_files   => ['script/wallflower'],
    add_to_cleanup => ['App-Wallflower-*'],
    meta_merge     => {
        resources =>
            { repository => 'http://github.com/book/App-Wallflower', },
    },
);

$builder->create_build_script();
