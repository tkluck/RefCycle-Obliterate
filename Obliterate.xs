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

void
check_arenas()
{
 SV *sva;
 for (sva = PL_sv_arenaroot; sva; sva = (SV *) SvANY(sva))
  {
   SV *sv = sva + 1;
   SV *svend = &sva[SvREFCNT(sva)];
   while (sv < svend)
    {
     if (SvROK(sv) && ((IV) SvANY(sv)) & 1)
      {
       warn("Odd SvANY for %p @ %p[%ld]",sv,sva,(sv-sva));
       abort();
      }
     ++sv;
    }
  }
}

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
        record->sv = target;
        record->reachable = 0;
        record->refcount = 0;
        HASH_ADD_PTR(*refcounts, sv, record);
    }
    record->refcount+= refcount;
}

long
countrefs(SV2Refcount **refcounts, SV *sv, long balance)
{
    balance+=SvREFCNT(sv);
    recordref(refcounts, sv, 0);
    if(SvROK(sv)) {
        SV *target = SvRV(sv);
        SV **item;
        AV *av;
        HV *hv;
        HE *he;
        if(SvTYPE(target) < SVt_PVAV) { // scalar value
            recordref(refcounts, target, 1);
            balance--;
        } else switch(SvTYPE(target)) {
        case SVt_PVAV:
            av = (AV*)target;
            for(unsigned long i = 0; i <= av_top_index(av); i++) {
                item = av_fetch(av, i, false);
                recordref(refcounts, *item, 1);
                balance--;
            }
        break;
        case SVt_PVHV:
            hv = (HV*)target;
            hv_iterinit(hv);
            while(he = hv_iternext(hv)) {
                //int len;
                //char *k = hv_iterkey(he, &len);
                //fprintf(stderr,"countrefs: Descending into key: ");
                //write(2, k, len);
                //fprintf(stderr, "\n");
                target = hv_iterval(hv, he);
                recordref(refcounts, target, 1);
                balance--;
            }
        break;
        case SVt_PV:
        break;
        default:
            fprintf(stderr,"Unhandled type! %d\n", SvTYPE(target));
        }
    }
    return balance;
}

void
markrecordreachable(SV2Refcount **refcounts, SV2Refcount *record);

void
markreachable(SV2Refcount **refcounts, SV *sv) {
    SV2Refcount *record;
    HASH_FIND_PTR(*refcounts, &sv, record);
    if(record) {
        markrecordreachable(refcounts, record);
    } else {
        fprintf(stderr,"Scalar value not recorded???\n");
        abort();
    }
}

void
markrecordreachable(SV2Refcount **refcounts, SV2Refcount *record) {
    char already_marked = record->reachable;
    record->reachable = 1;
    if(!already_marked && SvROK(record->sv)) {
        SV *target = SvRV(record->sv);
        SV **item;
        AV *av;
        HV *hv;
        HE *he;
        markreachable(refcounts, target);
        if(SvTYPE(target) < SVt_PVAV) { // scalar value
            markreachable(refcounts, target);
        } else switch(SvTYPE(target)) {
        case SVt_PVAV:
            av = (AV*)target;
            for(unsigned long i = 0; i <= av_top_index(av); i++) {
                item = av_fetch(av, i, false);
                markreachable(refcounts, *item);
            }
        break;
        case SVt_PVHV:
            hv = (HV*)target;
            hv_iterinit(hv);
            while(he = hv_iternext(hv)) {
                //int len;
                //char *k = hv_iterkey(he, &len);
                //fprintf(stderr,"Reachable: Descending into key: ");
                //write(2, k, len);
                //fprintf(stderr, "\n");

                target = hv_iterval(hv, he);
                markreachable(refcounts, target);
            }
        break;
        case SVt_PV:
        break;
        default:
            fprintf(stderr,"Unhandled type! %d\n", SvTYPE(target));
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
        if(SvREFCNT(record->sv) > record->refcount) {
            markrecordreachable(&refcounts, record);
        }
    }

    HASH_ITER(hh, refcounts, record, tmp) {
        if(!record->reachable && SvTYPE(record->sv) != SVTYPEMASK) {
            sv_setsv(record->sv, &PL_sv_undef);
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

