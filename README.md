# RefCycle::Obliterate - Conservative garbage collector for Perl
[![][travis-img]][travis-url]

[travis-img]: https://travis-ci.org/tkluck/RefCycle-Obliterate.svg?branch=master
[travis-url]: https://travis-ci.org/tkluck/RefCycle-Obliterate

## Quickstart

Installation:

    perl Makefile.PL
    make
    make test 
    make install 

Use:

```perl
use RefCycle::Obliterate;
while(1) {
    RefCycle::Obliterate::obliterate();

    my $bar = {};
    $bar->{bar} = $bar;
} # Note how we don't get OOM-killed :)
```

## Description

The `obliterate()` function scans all Perl's `SV` structures and builds the tree of
references. Any unreachable structures are freed. The algorithm used is a
simple mark-and-sweep.

The function is *conservative* in the sense that it does not claim to know about
all the ways an `SV` can be referenced: currently, only `RV`s, arrays and
hashes are supported. Even more generally, it would never be possible to know what
references extension code holds, and where those are stored.

The function `obliterate()` only frees those cycles for which it can validate
that it knows about all the references: the `SvREFCOUNT` agrees with what we
compute.

In practice, this means that the roots of the reference tree are defined to be
those nodes that have a higher `SvREFCOUNT` than `obliterate()` computes.

## Package name

In keeping with Perl's prosaic naming conventions (e.g. `die` for an exception,
'mortal' scalar values, etc.), I decided against something more formal
like `Memory::GarbageCollector`.

## Copyright

Copyright (c) 1997-1998 Nick Ing-Simmons.
Copyright (c) 2017 Timo Kluck.

All rights reserved.  This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.
