/* used in state.h */
#ifndef VAR
  #define VAR(name,type) VARx(name, PL_ ## name, type)
#endif

/* Coro's POLICY set of per-thread dynamic globals: $_, @_, $@, $/, select,
 * %^H and the %SIG hooks.  Which of these are per-green-thread is Coro's design
 * choice, NOT an interpreter fact, so they are Coro's and do NOT move to core.
 *
 * The GENERIC execution registers (the value/mark/scope/save/tmps stacks, the
 * execution position, the compile cursors and the flags) live entirely in
 * execstate.h now, as a PerlExecState that save_perl/load_perl swap via
 * execstate_save/execstate_load - so this file lists only the policy set.
 */

VARx(defsv,    GvSV (PL_defgv),  SV *)
VARx(defav,    GvAV (PL_defgv),  AV *)
VARx(errsv,    GvSV (PL_errgv),  SV *)
VARx(irsgv,    GvSV (irsgv),     SV *)
VARx(hinthv,   GvHV (PL_hintgv), HV *)
VAR(rs,        SV *)               /* input record separator $/ */
VAR(defoutgv,  GV *)               /* default FH for output ($SELECT) */
VAR(diehook,   SV *)               /* $SIG{__DIE__}  */
VAR(warnhook,  SV *)               /* $SIG{__WARN__} */

#undef VAR
#undef VARx
