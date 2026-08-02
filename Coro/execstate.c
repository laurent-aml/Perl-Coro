/* execstate.c
 *
 * BACKPORT of perl core's interpreter execution-state register copy, for perls
 * that do not (yet) ship the API.  This is deliberately a near-copy of core's
 * Perl_execstate_save / Perl_execstate_load (perl's scope.c).  State.xs decides
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
