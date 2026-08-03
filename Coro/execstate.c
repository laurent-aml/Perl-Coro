/* execstate.c
 *
 * BACKPORT of perl core's interpreter execution-state API, for perls that do
 * not (yet) ship it: the register copy (Perl_execstate_save / _load, a near-copy
 * of core's Perl_execstate_save / _load in perl's scope.c) AND the fresh-stack
 * lifecycle (Perl_execstate_init / _unwind / _destroy).  State.xs decides
 * whether it is needed: it #includes this (and execstate.h) only when core lacks
 * the API (#ifndef PERL_EXECSTATE), so there is no self-guard here - reaching
 * this file already means the backport is wanted.
 *
 * Companion to execstate.h, which holds the single register list and the
 * PerlExecState struct (the copy of core's execstate.h).  #included into
 * State.xs the same way as libcoro/coro.c and clone.c, so it is compiled once
 * without a separate build rule.
 *
 * Register list derived from Coro/state.h by Marc A. Lehmann
 * <schmorp@schmorp.de>, used under the same terms as perl; see execstate.h.
 *
 * The functions are named Perl_execstate_* and reached through execstate_*
 * macros (execstate.h) - core's own function-plus-short-macro convention, so
 * this is a drop-in for the eventual core API rather than anything Coro-shaped.
 * They are static only because this is #included into the single State.xs
 * compilation unit; core's versions will be ordinary (external) API functions.
 */

/* ========================= level 1: register snapshot ==================== */
#if PERL_EXECSTATE_LEVEL < 1

static void
Perl_execstate_save (pTHX_ PerlExecState *into)
{
  #define CORO_ES_SAVE(name, lval, type) into->name = lval;
  PERL_EXECSTATE_SLOTS (CORO_ES_SAVE)
  #undef CORO_ES_SAVE
}

static void
Perl_execstate_load (pTHX_ PerlExecState *from)
{
  #define CORO_ES_LOAD(name, lval, type) lval = from->name;
  PERL_EXECSTATE_SLOTS (CORO_ES_LOAD)
  #undef CORO_ES_LOAD
}

#endif /* level 1 */

/* ======================= level 2: fresh-stack lifecycle ================== */
#if PERL_EXECSTATE_LEVEL < 2

/* ---------------------------------------------------------------------------
 * Execution-context lifecycle: allocate a fresh set of interpreter stacks for
 * a new execution context, unwind them, and free them.  This is where the
 * genuinely perl-version-sensitive code lives - the teardown ORDER in
 * Perl_execstate_unwind (a perl 24+ scope/context/pad contract; see the
 * ae354a2 fix) and the SS_MAXPUSH / retstack / scopestack_name gates in
 * Perl_execstate_init - which is the strongest reason for this half to become
 * a core API too.  The initial stack SIZES stay the caller's tuning policy;
 * Perl_execstate_init takes only the extra context-stack reservation (cxextra)
 * the caller needs to overlay its own per-thread slots.
 * ------------------------------------------------------------------------- */

/*
 * allocate various perl stacks. This is almost an exact copy
 * of perl.c:init_stacks, except that it uses less memory
 * on the (sometimes correct) assumption that coroutines do
 * not usually need a lot of stackspace.
 */
#if !CORO_PREFER_PERL_FUNCTIONS
static void
Perl_execstate_init (pTHX_ int cxextra)
{
    PL_curstackinfo = new_stackinfo(32, 4 + cxextra); /* 3 is minimum due to perl rounding down in scope.c:GROW() */
    PL_curstackinfo->si_type = PERLSI_MAIN;
    PL_curstack = PL_curstackinfo->si_stack;
    PL_mainstack = PL_curstack;		/* remember in case we switch stacks */

    PL_stack_base = AvARRAY(PL_curstack);
    PL_stack_sp = PL_stack_base;
    PL_stack_max = PL_stack_base + AvMAX(PL_curstack);

    New(50,PL_tmps_stack,32,SV*);
    PL_tmps_floor = -1;
    PL_tmps_ix = -1;
    PL_tmps_max = 32;

    New(54,PL_markstack,16,I32);
    PL_markstack_ptr = PL_markstack;
    PL_markstack_max = PL_markstack + 16;

#ifdef SET_MARK_OFFSET
    SET_MARK_OFFSET;
#endif

    New(54,PL_scopestack,8,I32);
    PL_scopestack_ix = 0;
    PL_scopestack_max = 8;
#if HAS_SCOPESTACK_NAME
    New(54,PL_scopestack_name,8,const char*);
#endif

    New(54,PL_savestack,24,ANY);
    PL_savestack_ix = 0;
    PL_savestack_max = 24;
#if PERL_VERSION_ATLEAST (5,24,0)
    /* perl 5.24 moves SS_MAXPUSH optimisation from */
    /* the header macros to PL_savestack_max */
    PL_savestack_max -= SS_MAXPUSH;
#endif

#if !PERL_VERSION_ATLEAST (5,10,0)
    New(54,PL_retstack,4,OP*);
    PL_retstack_ix = 0;
    PL_retstack_max = 4;
#endif
}
#endif

static void
Perl_execstate_unwind (pTHX)
{
  if (!IN_DESTRUCT)
    {
      /* unwind all extra stacks */
      POPSTACK_TO (PL_mainstack);

      /* Unwind the context stack first. dounwind() pops each context frame
       * and leaves *that frame's* scope (CX_LEAVE_SCOPE) in order, restoring
       * PL_comppad and CvDEPTH between frames. This must happen before any
       * blanket LEAVE_SCOPE(0): doing LEAVE_SCOPE(0) up front would process
       * inner-frame save-stack entries (e.g. a `local $h{k}` SAVEt_DELETE, or
       * SAVEt_CLEARSV) while the pad is still at the innermost frame's depth,
       * leaving an outer frame's pad slot PADSTALE -- which corrupts refcounts
       * and asserts/segfaults inside Perl_leave_scope on modern perls (seen
       * via ->safe_cancel of a thread blocked in a condvar). */
      dounwind (-1);

      /* restore any remaining base-level saved variables and free temporaries */
      LEAVE_SCOPE (0);
      assert (PL_tmps_floor == -1);

      /* free all temporaries */
      FREETMPS;
      assert (PL_tmps_ix == -1);
    }
}

/*
 * destroy the stacks, the callchain etc...
 */
static void
Perl_execstate_destroy (pTHX)
{
  while (PL_curstackinfo->si_next)
    PL_curstackinfo = PL_curstackinfo->si_next;

  while (PL_curstackinfo)
    {
      PERL_SI *p = PL_curstackinfo->si_prev;

      if (!IN_DESTRUCT)
        SvREFCNT_dec (PL_curstackinfo->si_stack);

      Safefree (PL_curstackinfo->si_cxstack);
      Safefree (PL_curstackinfo);
      PL_curstackinfo = p;
  }

  Safefree (PL_tmps_stack);
  Safefree (PL_markstack);
  Safefree (PL_scopestack);
#if HAS_SCOPESTACK_NAME
  Safefree (PL_scopestack_name);
#endif
  Safefree (PL_savestack);
#if !PERL_VERSION_ATLEAST (5,10,0)
  Safefree (PL_retstack);
#endif
}

#endif /* level 2 */
