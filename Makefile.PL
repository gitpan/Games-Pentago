use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Games::Pentago',
    AUTHOR              => q{Tim Nordenfur <tim@gurka.se>},
    VERSION_FROM        => 'lib/Games/Pentago.pm',
    ABSTRACT_FROM       => 'lib/Games/Pentago.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Games-Pentago-*' },
);
