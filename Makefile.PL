use strict;
use warnings;
use 5.006;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'App::Wallflower',
    LICENSE      => 'perl',
    AUTHOR       => 'Philippe Bruhat (BooK) <book@cpan.org>',
    ABSTRACT_FROM => 'script/wallflower',
    VERSION_FROM => 'lib/Wallflower.pm',
    PREREQ_PM    => {
        'Path::Class' => 0,
        'Plack'       => 0,
        'URI'         => 0,

        # build_requires
        'Test::More' => 0,
        'List::Util' => 0,
    },
    EXE_FILES   => ['script/wallflower'],
    clean       => { FILES => 'App-Wallflower-*' },
    META_MERGE  => {
        resources =>
            { repository => 'http://github.com/book/Git-Repository', },
    },
    PL_FILES    => {},
    INSTALLDIRS => 'site',
);
