/* execstate.h
 *
 * The "separation" artifact for the proposed core interpreter execution-state
 * API (see Porting/execstate_api.md).  It holds, in ONE place, the list of the
 * generic execution registers that make up a switchable execution context - the
 * value / mark / scope / save / temporaries stacks, the execution position, the
 * compile-time cursors and the execution flags - as a single X-macro.  From
 * that one list it generates the PerlExecState struct and the trivial save/load
 * register copy; Coro's state.h consumes the SAME list (via a VARx bridge) so
 * the register set is never written twice.
 *
 * It deliberately EXCLUDES the policy set of per-thread dynamic globals Coro
 * also swaps ($_/@_/$@/$//select/%^H/$SIG hooks) - which of those are
 * per-green-thread is Coro's design choice, not an interpreter fact - and
 * PL_mainstack, which load_perl sets directly.  Those stay in Coro's state.h.
 *
 * It ALSO carries the fresh-stack setup and the unwinding teardown
 * (execstate_init / _unwind / _destroy, bodies in execstate.c) - these were
 * long treated as "Coro's own", but they are just as much interpreter fact:
 * the teardown order is a perl 24+ scope/context/pad contract (see the ae354a2
 * fix) and the setup carries SS_MAXPUSH / retstack / scopestack_name version
 * gates.  So they belong on the core side of the line too, and live here with
 * the register list.  What stays purely Coro is the initial stack SIZES (tuning)
 * and PL_mainstack, which load_perl sets directly.
 *
 * This file IS the backport copy, organised as a capability LADDER so core can
 * implement the execution-state API up to whatever level it wants and Coro
 * backfills the rest:
 *
 *     level 1  register snapshot     (PerlExecState, execstate_save/load)
 *     level 2  fresh-stack lifecycle (execstate_init/unwind/destroy)
 *     (level 3 pad, level 4 transfer: declared here once their code moves out
 *      of State.xs)
 *
 * Core announces how far it goes via PERL_EXECSTATE_LEVEL (the legacy boolean
 * PERL_EXECSTATE counts as level 1).  Each section below is compiled only when
 * core is below that level (#if PERL_EXECSTATE_LEVEL < N); State.xs includes
 * this file only while Coro still has a level to backfill, and a perl that
 * provides a level is served by its own execstate.h via perl.h.
 *
 * The list, types and gates match Coro/state.h exactly, so the generated
 * members are byte-identical to the hand-written ones.  When this moves to core,
 * the version/build gates (OP_IN_REGISTER, HAS_SCOPESTACK_NAME,
 * PERL_VERSION_ATLEAST) translate to core's own spellings.
 *
 * ATTRIBUTION: this register list is derived from Coro/state.h by
 * Marc A. Lehmann <schmorp@schmorp.de> (http://software.schmorp.de/pkg/Coro.html)
 * and is used under the same terms as perl.  Knowing exactly which interpreter
 * registers make up a switchable execution context is his contribution.
 */

#ifndef CORO_EXECSTATE_H
#define CORO_EXECSTATE_H

/* ========================= level 1: register snapshot ==================== */
#if PERL_EXECSTATE_LEVEL < 1

/* --- build/version-gated slots, factored out so they can appear inside the
 *     X-macro (a #define body cannot contain #if) --- */

#ifdef OP_IN_REGISTER
#  define PERL_EXECSTATE_SLOT_OP(SLOT)   SLOT(opsave, PL_opsave, OP *) /* probably not necessary */
#else
#  define PERL_EXECSTATE_SLOT_OP(SLOT)   SLOT(op,     PL_op,     OP *) /* currently executing op */
#endif

#if HAS_SCOPESTACK_NAME
#  define PERL_EXECSTATE_SLOT_SSNAME(SLOT) \
     SLOT(scopestack_name, PL_scopestack_name, const char **)
#else
#  define PERL_EXECSTATE_SLOT_SSNAME(SLOT)
#endif

#if !PERL_VERSION_ATLEAST(5,9,0)
#  define PERL_EXECSTATE_SLOT_RETSTACK(SLOT) \
     SLOT(retstack,     PL_retstack,     OP **) /* OPs we have postponed executing */ \
     SLOT(retstack_ix,  PL_retstack_ix,  I32)   \
     SLOT(retstack_max, PL_retstack_max, I32)
#  define PERL_EXECSTATE_SLOT_SORTCXIX(SLOT) \
     SLOT(sortcxix,     PL_sortcxix,     I32) /* from pp_ctl.c */
#  define PERL_EXECSTATE_SLOT_FLAGS(SLOT) \
     SLOT(localizing,   PL_localizing,   U32) /* are we processing a local() list? */ \
     SLOT(in_eval,      PL_in_eval,      U32) /* trap "fatal" errors? */
#else
#  define PERL_EXECSTATE_SLOT_RETSTACK(SLOT)
#  define PERL_EXECSTATE_SLOT_SORTCXIX(SLOT)
#  define PERL_EXECSTATE_SLOT_FLAGS(SLOT) \
     SLOT(localizing,   PL_localizing,   U8) /* are we processing a local() list? */ \
     SLOT(in_eval,      PL_in_eval,      U8) /* trap "fatal" errors? */
#endif

#if PERL_VERSION_ATLEAST(5,10,0)
#  define PERL_EXECSTATE_SLOT_PARSER(SLOT) \
     SLOT(parser,       PL_parser,       yy_parser *)
#else
#  define PERL_EXECSTATE_SLOT_PARSER(SLOT)
#endif

/* --- the one list of generic execution registers, matching Coro/state.h.
 *     The per-register notes are Marc Lehmann's, from the original state.h;
 *     most were in turn copied from perl's thrdvar.h. --- */
#define PERL_EXECSTATE_SLOTS(SLOT)                                              \
  SLOT(stack_sp,            PL_stack_sp,            SV **)  /* the main stack */ \
  PERL_EXECSTATE_SLOT_OP(SLOT)                                                  \
  SLOT(curpad,              PL_curpad,              SV **)  /* active pad (lexicals+tmps) */ \
  SLOT(stack_base,          PL_stack_base,          SV **)                      \
  SLOT(stack_max,           PL_stack_max,           SV **)                      \
  SLOT(scopestack,          PL_scopestack,          I32 *)  /* scopes we've ENTERed */ \
  SLOT(scopestack_ix,       PL_scopestack_ix,       I32)                        \
  SLOT(scopestack_max,      PL_scopestack_max,      I32)                        \
  PERL_EXECSTATE_SLOT_SSNAME(SLOT)                                              \
  SLOT(savestack,           PL_savestack,           ANY *)  /* items to restore when LEAVEing ENTERed scopes */ \
  SLOT(savestack_ix,        PL_savestack_ix,        I32)                        \
  SLOT(savestack_max,       PL_savestack_max,       I32)                        \
  SLOT(tmps_stack,          PL_tmps_stack,          SV **)  /* mortals we've made */ \
  SLOT(tmps_ix,             PL_tmps_ix,             SSize_t)                    \
  SLOT(tmps_floor,          PL_tmps_floor,          SSize_t)                    \
  SLOT(tmps_max,            PL_tmps_max,            SSize_t)                     \
  SLOT(markstack,           PL_markstack,           I32 *)  /* stack_sp locations we're remembering */ \
  SLOT(markstack_ptr,       PL_markstack_ptr,       I32 *)                      \
  SLOT(markstack_max,       PL_markstack_max,       I32 *)                      \
  PERL_EXECSTATE_SLOT_RETSTACK(SLOT)                                            \
  SLOT(curpm,               PL_curpm,               PMOP *) /* current match, interps in REs from */ \
  SLOT(curcop,              PL_curcop,              COP *)                      \
  SLOT(curstack,            PL_curstack,            AV *)   /* THE STACK */      \
  SLOT(curstackinfo,        PL_curstackinfo,        PERL_SI *) /* current stack + context */ \
  SLOT(sortcop,             PL_sortcop,             OP *)   /* user defined sort routine */ \
  SLOT(sortstash,           PL_sortstash,           HV *)   /* which is in some package or other */ \
  PERL_EXECSTATE_SLOT_SORTCXIX(SLOT)                                            \
  PERL_EXECSTATE_SLOT_FLAGS(SLOT)                                              \
  SLOT(tainted,             PL_tainted,             bool)   /* using variables controlled by $< */ \
  /* compcv is technically an interpreter var, but Coro treats it as per-thread */ \
  SLOT(compcv,              PL_compcv,              CV *)   /* currently compiling subroutine */ \
  SLOT(comppad,             PL_comppad,             AV *)   /* storage for lexically scoped temporaries */ \
  SLOT(comppad_name,        PL_comppad_name,        PADNAMELIST *) /* variable names for "my" variables */ \
  SLOT(comppad_name_fill,   PL_comppad_name_fill,   PADOFFSET)  /* last "introduced" variable offset */ \
  SLOT(comppad_name_floor,  PL_comppad_name_floor,  PADOFFSET)  /* start of vars in innermost block */ \
  SLOT(runops,              PL_runops,              runops_proc_t) /* for tracing support */ \
  SLOT(hints,               PL_hints,               U32)   /* pragma-tic compile-time flags */ \
  PERL_EXECSTATE_SLOT_PARSER(SLOT)

struct PerlExecState {
#define PERL_EXECSTATE_MEMBER(name, lval, type) type name;
  PERL_EXECSTATE_SLOTS(PERL_EXECSTATE_MEMBER)
#undef PERL_EXECSTATE_MEMBER
};
typedef struct PerlExecState PerlExecState;

/* The register copy is generated from the single list above.  The bodies are
 * NOT embedded here - they live in execstate.c (Perl_execstate_save / _load),
 * which these macros call. */
#define execstate_save(into) Perl_execstate_save (aTHX_ into)
#define execstate_load(from) Perl_execstate_load (aTHX_ from)

#endif /* level 1 */

/* ======================= level 2: fresh-stack lifecycle ================== */
#if PERL_EXECSTATE_LEVEL < 2

/* Execution-context lifecycle (bodies also in execstate.c).  execstate_init
 * reserves cxextra extra context-stack slots for the caller's per-thread
 * overlay; the initial stack sizes are the caller's tuning policy.  Under
 * CORO_PREFER_PERL_FUNCTIONS the setup falls back to perl's own init_stacks. */
#if CORO_PREFER_PERL_FUNCTIONS
# define execstate_init(cxextra) init_stacks ()
#else
# define execstate_init(cxextra) Perl_execstate_init (aTHX_ (cxextra))
#endif
#define execstate_unwind()  Perl_execstate_unwind  (aTHX)
#define execstate_destroy() Perl_execstate_destroy (aTHX)

#endif /* level 2 */

/* ============================== level 3: pads ============================ */
#if PERL_EXECSTATE_LEVEL < 3

/* Version-gated pad-access shims.  A padlist is opaque and its representation
 * has changed repeatedly across perls (the NEWPADAPI rework, the 5.15.3 AvREAL
 * flip, the 5.22 PadlistNAMES quirk, pre-5.8 AV-based pads), which is exactly
 * the interpreter knowledge level 3 lifts out of Coro. */
#ifdef PadARRAY
# define NEWPADAPI 1
# define newPADLIST(var)	(Newz (0, var, 1, PADLIST), Newx (PadlistARRAY (var), 2, PAD *))
#else
typedef AV PADNAMELIST;
# if !PERL_VERSION_ATLEAST(5,8,0)
typedef AV PADLIST;
typedef AV PAD;
# endif
# define PadlistARRAY(pl)	((PAD **)AvARRAY (pl))
# define PadlistMAX(pl)		AvFILLp (pl)
# define PadlistNAMES(pl)	(*PadlistARRAY (pl))
# define PadARRAY		AvARRAY
# define PadMAX			AvFILLp
# define newPADLIST(var)	((var) = newAV (), av_extend (var, 1))
#endif
#ifndef PadnamelistREFCNT
# define PadnamelistREFCNT(pnl) SvREFCNT (pnl)
#endif
#ifndef PadnamelistREFCNT_dec
# define PadnamelistREFCNT_dec(pnl) SvREFCNT_dec (pnl)
#endif
/* one off bugfix for perl 5.22 */
#if PERL_VERSION_ATLEAST(5,22,0) && !PERL_VERSION_ATLEAST(5,24,0)
# undef PadlistNAMES
# define PadlistNAMES(pl) *((PADNAMELIST **)PadlistARRAY (pl))
#endif

/* Derive a fresh padlist for a re-entered sub, and free one so derived (bodies
 * in execstate.c).  These are the deep padlist-internals primitives; Coro's own
 * get_padlist/put_padlist cache the results - that caching is Coro policy and
 * stays in State.xs. */
#define execstate_derive_padlist(cv) Perl_execstate_derive_padlist (aTHX_ (cv))
#define execstate_free_padlist(pl)   Perl_execstate_free_padlist   (aTHX_ (pl))

#endif /* level 3 */

/* ===================== level 4: JMPENV (transfer) registers ============== */
#if PERL_EXECSTATE_LEVEL < 4

/* The ONLY interpreter-state pieces of a context transfer: the exception-handler
 * chain head (top_env) that must follow a C-stack switch, the interpreter's base
 * JMPENV, and the run-loop restart op.  The machine switch itself - coro_transfer
 * and the cctx C-stack machinery - is deliberately NOT here: it is a pluggable,
 * build-time-selected mechanism (libcoro, like the asm backends), not interpreter
 * state, and only runs on a cross-cctx switch.  So these are just registers, as
 * in level 1: lvalue aliases the caller reads/writes/stores where it likes (Coro
 * keeps its copies per-cctx), plus helpers for the base and the chain root. */
#define execstate_topenv          PL_top_env       /* current JMPENV chain head (lvalue) */
#define execstate_restartop       PL_restartop     /* run-loop restart op (lvalue)       */
#define execstate_topenv_reset()  (PL_top_env = &PL_start_env) /* start at interpreter base */
#define execstate_topenv_root()   Perl_execstate_topenv_root (aTHX)

#endif /* level 4 */

#endif /* CORO_EXECSTATE_H */
