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
typedef struct _ReverseRef {
    SV *sv;
    char *tag;
    UT_hash_handle hh; /* makes this structure hashable */
} ReverseRef;

typedef struct _SV2Refcount {
    SV *sv;
    unsigned long refcount;
    char reachable;
    ReverseRef *reverserefs;
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
recordref(SV2Refcount **refcounts, SV *target, int refcount, SV *source, char *tag) {
    //fprintf(stderr, "recording sv(%p)", target);
    //fprintf(stderr, " with refcount %d\n", SvREFCNT(target));
    SV2Refcount *record = NULL;
    HASH_FIND_PTR(*refcounts, &target, record);
    if(!record) {
        record = (SV2Refcount*)malloc(sizeof(SV2Refcount));
        memset(record, 0, sizeof(SV2Refcount));
        record->sv = target;
        HASH_ADD_PTR(*refcounts, sv, record);
    }
    record->refcount+= refcount;

    //fprintf(stderr, "SV(%p) -> SV(%p)\n", source, target);

    if(source) {
        ReverseRef *revref;
        HASH_FIND_PTR(record->reverserefs, &source, revref);
        if(!revref) {
            revref = (ReverseRef*)malloc(sizeof(ReverseRef));
            memset(revref, 0, sizeof(ReverseRef));
            revref->sv = source;
            revref->tag = tag;
            HASH_ADD_PTR(record->reverserefs, sv, revref);
        }
    }
}

long
countrefs(SV2Refcount **refcounts, SV *sv, long balance)
{
    balance+=SvREFCNT(sv);
    recordref(refcounts, sv, 0, NULL, "setnull");
    if(SvROK(sv) && !SvWEAKREF(sv)) {
        SV *target = SvRV(sv);
        recordref(refcounts, target, 1, sv, "scalarref");
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
                        recordref(refcounts, *item, 1, sv, "from av");
                        balance--;
                    } else {
                        //fprintf(stderr,"Item %ld / %ld not found???\n", i, av_top_index(av));
                        //sv_dump(av);
                        //abort();
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
                    //fprintf(stderr,"Loop number %d\n", i++);

                    val = hv_iterval(hv, he);
                    if(val > 10000) { // HUH???
                        recordref(refcounts, val, 1, sv, "from hv");
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
markrecordreachable(SV2Refcount *refcounts, SV2Refcount *record, int indent);

void
markreachable(SV2Refcount *refcounts, SV *sv, int indent) {
    SV2Refcount *record = NULL;
    HASH_FIND_PTR(refcounts, &sv, record);
    if(record) {
        markrecordreachable(refcounts, record, indent);
    } else {
        fprintf(stderr,"Scalar value SV(%p) not recorded???\n", sv);
        //abort();
    }
}

void
markrecordreachable(SV2Refcount *refcounts, SV2Refcount *record, int indent) {
    char already_marked = record->reachable;
    record->reachable = 1;
    //for(int k=indent;k; k--) {
    //    fprintf(stderr, " ");
    //}
    //fprintf(stderr, "->SV(%p)\n", record->sv);
    //
    if(!already_marked) {
        if(SvROK(record->sv)) {
            SV *target = SvRV(record->sv);
            markreachable(refcounts, target, indent+1);
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
                            markreachable(refcounts, *item, indent+1);
                        } else {
                            //fprintf(stderr,"Item %ld / %ld not found???\n", i, av_top_index(av));
                            //sv_dump(av);
                            //abort();
                        }
                    }
                }
            break;
            case SVt_PVHV:
                hv = (HV*)record->sv;
                if(!SvMAGICAL(hv)) {
                    hv_iterinit(hv);
                    while(he = hv_iternext(hv)) {
                        //int len;
                        //char *k = hv_iterkey(he, &len);
                        //fprintf(stderr,"Reachable: Descending into key: ");
                        //write(2, k, len);
                        //fprintf(stderr, "\n");

                        val = hv_iterval(hv, he);
                        if(val > 10000) { // HUH???
                            markreachable(refcounts, val, indent+1);
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
            markrecordreachable(refcounts, record, 0);
        }
        if((SvREFCNT(record->sv) < record->refcount)) {
            fprintf(stderr,"Found too many (%ld > %d) references to sv(%p)\n", record->refcount, SvREFCNT(record->sv), record->sv);
            ReverseRef *revref, *tmp2;
            HASH_ITER(hh, record->reverserefs, revref, tmp2) {
                fprintf(stderr, "Pointed at by:\n");
                sv_dump(revref->sv);
            }
            fprintf(stderr, "(end)\n");
            //sv_dump(record->sv);
            //abort();
        }
    }

    HASH_ITER(hh, refcounts, record, tmp) {
        if(!record->reachable && SvTYPE(record->sv) != SVTYPEMASK) {
            fprintf(stderr, "Found unreachable sv! refcount: %d, ours: %ld\n", SvREFCNT(record->sv), record->refcount);
            sv_dump(record->sv);
            ReverseRef *revref, *tmp2;
            HASH_ITER(hh, record->reverserefs, revref, tmp2) {
                fprintf(stderr, "Pointed at by (through %s):\n", revref->tag);
                sv_dump(revref->sv);
            }
            if(SvROK(record->sv)) {
                fprintf(stderr, "Unsetting this ref.\n");
                sv_unref(record->sv);
            } else switch(SvTYPE(record->sv)) {
                case SVt_PVAV:
                    fprintf(stderr, "Unsetting this array.\n");
                    av_clear((AV*)record->sv);
                    break;
                case SVt_PVHV:
                    fprintf(stderr, "Unsetting this hash.\n");
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

