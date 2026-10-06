$|=1;
print "1..8\n";

# An XSUB declared to take a Coro::State is handed its argument through the
# T_CORO_STATE typemap, which is SvSTATE($arg) -> SvSTATE_ -> SvSTATEhv_p.
#
# That probe checked SvTYPE (coro) == SVt_PVHV and then looked the state magic
# up with CORO_MAGIC_state, which was the CORO_MAGIC_NN variant: it reads
# SvMAGIC (sv)->mg_type without checking SvMAGIC (sv) is there at all.  Any hash
# that is not a coro therefore dereferenced a null pointer before SvSTATE_ could
# reach its croak - a blessed hash, as a fake coro in a test would be, or a bare
# one.  Non-hashes were fine, failing the SvTYPE check and never reaching it.
#
# Every XSUB taking a Coro::State shares the path: call, eval, clone, is_ready,
# has_cctx, rss, swap_sv, on_destroy, prio, cede_interval and the rest.

use Coro::State;

my $n = 0;

# Each of these must croak, not crash. The first two are the regression: they
# are hashes, so they used to get as far as the unguarded magic read.
for my $case (
   [ 'blessed hash'   => sub { Coro::State::call (bless ({}, "NotACoro"), sub { }) } ],
   [ 'bare hash'      => sub { Coro::State::call ({},                     sub { }) } ],
   [ 'blessed array'  => sub { Coro::State::call (bless ([], "NotACoro"), sub { }) } ],
   [ 'bare array'     => sub { Coro::State::call ([],                     sub { }) } ],
   [ 'plain scalar'   => sub { Coro::State::call (42,                     sub { }) } ],
   [ 'undef'          => sub { Coro::State::call (undef,                  sub { }) } ],
) {
   my ($what, $try) = @$case;

   eval { $try->() };
   print +($@ =~ /Coro::State object required/ ? "" : "not "),
         "ok ", ++$n, " # $what: ", ($@ =~ /^(.*)$/m)[0] || "no exception", "\n";
}

# a second XSUB on the same path, to show it is the typemap and not call()
eval { Coro::State::is_ready (bless {}, "NotACoro") };
print +($@ =~ /Coro::State object required/ ? "" : "not "), "ok ", ++$n, "\n";

# ... and a real Coro::State still goes through, so the probe did not become
# too strict. has_cctx takes a Coro::State and does not transfer.
my $st = new Coro::State sub { };
print +(eval { Coro::State::has_cctx ($st); 1 } ? "" : "not "), "ok ", ++$n, "\n";
