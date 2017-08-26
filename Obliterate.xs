/*
  Copyright (c) 1995,1996-1998 Nick Ing-Simmons
  Copyright (c) 2017 Timo Kluck

  All rights reserved.
  This program is free software; you can redistribute it and/or
  modify it under the same terms as Perl itself.
*/

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include <uthash.h>
typedef struct _SV2Refcount {
    SV *sv;
    unsigned long refcount;
    char reachable;
    UT_hash_handle hh; /* makes this structure hashable */
} SV2Refcount;

typedef long used_proc _((void *,SV *,long));

#ifndef sv_dump
#define sv_dump(sv) PerlIO_printf(PerlIO_stderr(), "\n")
#endif

long int
sv_apply_to_used(p, proc,n)
void *p;
used_proc *proc;
long int n;
{
 SV *sva;
 for (sva = PL_sv_arenaroot; sva; sva = (SV *) SvANY(sva))
  {
   SV *sv = sva + 1;
   SV *svend = &sva[SvREFCNT(sva)];

   while (sv < svend)
    {
     if (SvTYPE(sv) != SVTYPEMASK)
      {
       n = (*proc) (p, sv, n);
      }
     ++sv;
    }
  }
 return n;
}

long
countsvs(void **p, SV *sv, long count) {
    return count+1;
}

void
recordref(SV2Refcount **refcounts, SV *target, int refcount) {
    SV2Refcount *record = NULL;
    HASH_FIND_PTR(*refcounts, &target, record);
    if(!record) {
        record = (SV2Refcount*)malloc(sizeof(SV2Refcount));
        memset(record, 0, sizeof(SV2Refcount));
        record->sv = target;
        HASH_ADD_PTR(*refcounts, sv, record);
    }
    record->refcount+= refcount;
}

long
countrefs(SV2Refcount **refcounts, SV *sv, long balance)
{
    balance+=SvREFCNT(sv);
    recordref(refcounts, sv, 0);
    if(SvROK(sv) && !SvWEAKREF(sv)) {
        SV *target = SvRV(sv);
        recordref(refcounts, target, 1);
        balance--;
    } else {
        SV *val;
        SV **item;
        AV *av;
        HV *hv;
        HE *he;
        if(SvTYPE(sv) < SVt_PVAV) { // scalar value
            // pass
        } else switch(SvTYPE(sv)) {
        case SVt_PVAV:
            av = (AV*)sv;
            if(AvREAL(av) && !SvMAGICAL(av)) {
                for(long i = 0; i <= av_top_index(av); i++) {
                    item = av_fetch(av, i, false);
                    if(item) {
                        recordref(refcounts, *item, 1);
                        balance--;
                    }
                }
            }
        break;
        case SVt_PVHV:
            hv = (HV*)sv;
            if(!SvMAGICAL(hv)) {
                hv_iterinit(hv);
                int i = 1;
                while(he = hv_iternext(hv)) {
                    val = hv_iterval(hv, he);
                    if(val > 10000) { // HUH???
                        recordref(refcounts, val, 1);
                        balance--;
                    }
                }
            }
        break;
        //default:
        //    fprintf(stderr,"Unhandled type! %d\n", SvTYPE(sv));
        }
    }
    return balance;
}

void
markrecordreachable(SV2Refcount *refcounts, SV2Refcount *record);

void
markreachable(SV2Refcount *refcounts, SV *sv) {
    SV2Refcount *record = NULL;
    HASH_FIND_PTR(refcounts, &sv, record);
    if(record) {
        markrecordreachable(refcounts, record);
    } else {
        fprintf(stderr,"Scalar value SV(%p) not recorded???\n", sv);
        abort();
    }
}

void
markrecordreachable(SV2Refcount *refcounts, SV2Refcount *record) {
    char already_marked = record->reachable;
    record->reachable = 1;
    if(!already_marked) {
        if(SvROK(record->sv)) {
            SV *target = SvRV(record->sv);
            markreachable(refcounts, target);
        } else {
            SV *val;
            SV **item;
            AV *av;
            HV *hv;
            HE *he;
            if(SvTYPE(record->sv) < SVt_PVAV) { // scalar value
                // pass
            } else switch(SvTYPE(record->sv)) {
            case SVt_PVAV:
                av = (AV*)record->sv;
                if(AvREAL(av) && !SvMAGICAL(av)) {
                    for(long i = 0; i <= av_top_index(av); i++) {
                        item = av_fetch(av, i, false);
                        if(item) {
                            markreachable(refcounts, *item);
                        }
                    }
                }
            break;
            case SVt_PVHV:
                hv = (HV*)record->sv;
                if(!SvMAGICAL(hv)) {
                    hv_iterinit(hv);
                    while(he = hv_iternext(hv)) {
                        val = hv_iterval(hv, he);
                        if(val > 10000) { // HUH???
                            markreachable(refcounts, val);
                        }
                    }
                }
            break;
            //default:
            //    fprintf(stderr,"Unhandled type! %d\n", SvTYPE(record->sv));
            }
        }
    }
}

long
garbage_collect()
{
    SV2Refcount *refcounts = NULL;
    SV2Refcount *record, *tmp;

    sv_apply_to_used(&refcounts, countrefs, 0);

    unsigned long unreachable = 0;

    HASH_ITER(hh, refcounts, record, tmp) {
        if((SvREFCNT(record->sv) > record->refcount)) {
            markrecordreachable(refcounts, record);
        }
    }

    HASH_ITER(hh, refcounts, record, tmp) {
        if(!record->reachable && SvTYPE(record->sv) != SVTYPEMASK) {
            if(SvROK(record->sv)) {
                sv_unref(record->sv);
            } else switch(SvTYPE(record->sv)) {
                case SVt_PVAV:
                    av_clear((AV*)record->sv);
                    break;
                case SVt_PVHV:
                    hv_clear((HV*)record->sv);
                    break;
            }
            unreachable++;
        }
        HASH_DEL(refcounts, record);
        free(record);
    }

    return unreachable;
}


MODULE = RefCycle::Obliterate	PACKAGE = RefCycle::Obliterate

PROTOTYPES: Enable

IV
obliterate()
CODE:
 {
  RETVAL = garbage_collect();
 }
OUTPUT:
 RETVAL

IV
scalar_value_count()
CODE:
 {
  RETVAL = sv_apply_to_used(NULL, countsvs, 0);
 }
OUTPUT:
 RETVAL

