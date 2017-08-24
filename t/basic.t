use Test;
plan test => 14;
eval { require RefCycle::Obliterate };
ok($@, "", "loading module");
eval { import RefCycle::Obliterate };
ok($@, "", "running import");

# --------------------------------------------
#
# hashrefs
#
# --------------------------------------------
my $foo = {}; $foo->{foo} = $foo;

ok( RefCycle::Obliterate::obliterate(), 0, "Destroying reachable reference cycles?");

undef $foo;

ok( RefCycle::Obliterate::obliterate(), 1, "Not destroying unreachable reference cycles?");

ok( RefCycle::Obliterate::obliterate(), 0, "Destroying reachable reference cycles?");

# --------------------------------------------
#
# arrayrefs
#
# --------------------------------------------
my $bar = []; push @$bar, { foo => $bar };

ok( RefCycle::Obliterate::obliterate(), 0, "Destroying reachable reference cycles?");

undef $bar;

ok( RefCycle::Obliterate::obliterate(), 2, "Not destroying unreachable reference cycles?");

ok( RefCycle::Obliterate::obliterate(), 0, "Destroying reachable reference cycles?");

# --------------------------------------------
#
# hashes
#
# --------------------------------------------
SCOPE: {
my %foo; $foo{foo} = \%foo;
ok( RefCycle::Obliterate::obliterate(), 0, "Destroying reachable reference cycles?");
use Data::Dumper;
print STDERR Dumper(\%foo);
}

ok( RefCycle::Obliterate::obliterate(), 1, "Not destroying unreachable reference cycles?");

ok( RefCycle::Obliterate::obliterate(), 0, "Destroying reachable reference cycles?");

# --------------------------------------------
#
# arrays
#
# --------------------------------------------
SCOPE: {
my @bar; push @bar, { foo => \@bar };
ok( RefCycle::Obliterate::obliterate(), 0, "Destroying reachable reference cycles?");
use Data::Dumper;
print STDERR Dumper(\@bar);
$bar = \@bar;
}

ok( RefCycle::Obliterate::obliterate(), 0, "Destroying reachable reference cycles?");

undef $bar;

ok( RefCycle::Obliterate::obliterate(), 1, "Not destroying unreachable reference cycles?");

ok( RefCycle::Obliterate::obliterate(), 0, "Destroying reachable reference cycles?");
