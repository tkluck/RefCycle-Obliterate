use ExtUtils::MakeMaker;

WriteMakefile( 
    'NAME'     => 'Devel::Leak',
    'clean' => {FILES => "*% *.bak"},
    'dist'     => { COMPRESS => 'gzip -f9', SUFFIX => '.gz' },
    'VERSION_FROM'  => 'Leak.pm'
);

