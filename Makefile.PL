use ExtUtils::MakeMaker;
use Config;

if ($] < 5.006 && $Config{'ccflags'} !~ /-DDEBUGGING/)
 {
  warn "This perl is not compiled with -DDEBUGGING - functions restricted\n";
 }

WriteMakefile( 
    'NAME'     => 'Devel::Leak',
    'clean' => {FILES => "*% *.bak"},
    'dist'     => { COMPRESS => 'gzip -f9', SUFFIX => '.gz' },
    'VERSION_FROM'  => 'Leak.pm'
);

