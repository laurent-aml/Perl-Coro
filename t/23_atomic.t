#!perl
# Coro::Atomic - the three forms of atomic {} plus the yield enforcement.

use strict;
use warnings;

use Coro;
use Coro::Atomic qw(atomic scoped_atomic);

use Test::More tests => 30;

sub depth() { Coro::_atomic_count () }

# --- block form: value + call context ------------------------------------
is scalar (atomic { 2 + 3 }), 5, "block form returns scalar value";
my @l = atomic { (1, 2, 3) };
is "@l", "1 2 3", "block form propagates list context";

# --- scoped form (no variable) ---------------------------------------------
{
    scoped_atomic;
    is Coro::_atomic_count (), 1, "scoped_atomic: in effect inside the scope";
}
is Coro::_atomic_count (), 0, "scoped_atomic: released on scope exit";

# --- enforcement: any yield attempt inside atomic is fatal, deterministically
eval { atomic { cede }; 1 };
like $@, qr/atomic/, "a stray cede inside atomic dies deterministically";
is Coro::_atomic_count (), 0, "count fine after the die";

eval { atomic { Coro::Semaphore->new (0)->down }; 1 };
like $@, qr/atomic/, "blocking Semaphore->down inside atomic dies (C-level)";
is Coro::_atomic_count (), 0, "count restored - scheduler left consistent";

# --- attribute form ------------------------------------------------------
sub cleanup :Atomic { Coro::_atomic_count () }
is cleanup (), 1, "attribute: body runs inside atomic";
is Coro::_atomic_count (), 0, "attribute: released after return";

sub blocky :Atomic { Coro::Semaphore->new (0)->down }
eval { blocky (); 1 };
like $@, qr/atomic/, "attribute: a blocking call inside a :Atomic sub dies";

# --- normal cooperative scheduling is unaffected outside atomic ----------
my @order;
async { push @order, "A1"; cede; push @order, "A2" };
async { push @order, "B1"; cede; push @order, "B2" };
cede for 1 .. 4;
is "@order", "A1 B1 A2 B2", "normal cede/scheduling unaffected outside atomic";

# --- nesting: the section is a counter, not a flag ------------------------
my @seen;
atomic {
    push @seen, depth;
    atomic {
        push @seen, depth;
        atomic { push @seen, depth };
        push @seen, depth;
    };
    push @seen, depth;
};
is "@seen", "1 2 3 2 1", "depth tracks nesting in and out";
is depth, 0, "fully released after nested blocks";

# the three forms nest with each other, in any combination
atomic {
    is depth, 1, "nesting: block form is depth 1";
    scoped_atomic;
    is depth, 2, "nesting: scoped_atomic inside a block is depth 2";
    is cleanup (), 3, "nesting: :Atomic sub inside both is depth 3";
    is depth, 2, "nesting: attribute form released on return, outer two intact";
};
is depth, 0, "nesting: all three forms released together";

# THE reason this must be a counter: leaving an inner section must not
# re-permit yielding while an outer one is still in effect.
my $inner_err;
atomic {
    atomic { };                 # inner enters and leaves
    $inner_err = !eval { cede; 1 } ? $@ : undef;
};
like $inner_err, qr/atomic/, "a cede is still fatal after an inner section exits";

# a die unwinds every level, leaving the count consistent
eval { atomic { atomic { die "boom\n" } }; 1 };
like $@, qr/boom/, "a die propagates out of nested sections";
is depth, 0, "count restored after a die two levels deep";

# --- abnormal exits: the count is one global, so a leak would poison every
# other coro (they would all croak on their next cede).
# Terminating switches away from the dying thread, i.e. it yields, so it has to
# be refused rather than silently abandoning the section.  ->cancel on oneself
# is not tested separately: it is documented to equal terminate, and State.xs
# routes it through the same slf_init_terminate_cancel_common.
my $term_err;
async {
    scoped_atomic;
    eval { Coro::terminate; 1 } or $term_err = $@;
};
cede for 1 .. 3;
like $term_err, qr/atomic/, "terminate inside atomic is refused, not silent";
is depth, 0, "count restored after the refused terminate";

# cancelling from another coro cannot catch one mid-section at all: for the
# canceller to be running, the atomic coro must already have left.
my $victim = async { atomic { }; Coro::schedule };
cede;
is depth, 0, "another coro never observes a live atomic section";
$victim->cancel;

# --- scoped_atomic: the enclosing scope is the section --------------------
# A bare call is all it takes; the section is in effect for the rest of the scope.
{
    scoped_atomic;
    ok depth, "a bare call puts the section in effect";
}

# repeated in one scope: each call adds a level, all released together
{
    scoped_atomic;
    scoped_atomic;
    is depth, 2, "two calls in one scope nest";
}
is depth, 0, "both released at that scope's exit";

# it covers the rest of the enclosing block, nested blocks included
my @depths;
for my $i (1 .. 2) {
    push @depths, depth;
    scoped_atomic;
    { push @depths, depth }         # inner block does not end it
    push @depths, depth;
}
is "@depths", "0 1 1 0 1 1", "covers the rest of the block, and ends per iteration";
is depth, 0, "released after the loop";
