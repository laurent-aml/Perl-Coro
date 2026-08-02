# Execution-state separation artifact (Coro/execstate.h): the register list +
# save/load copy that is destined to move into perl core.  Here we only check
# the piece that lives in the header - that execstate_save/load round-trip the
# live interpreter registers exactly, compiled into Coro's real build.  Coro's
# own coro_init_stacks / coro_unwind_stacks (the setup/teardown that also move
# to core) are exercised by the rest of the suite.
use strict;
use warnings;
use Test::More tests => 2;

use Coro::State;

is Coro::State::_execstate_roundtrip_ok(), 1,
    "execstate_save/load round-trips the live registers exactly";

# and again inside a local(), so the save stack is non-trivial
{
    local $Coro::State::probe = 1;
    is Coro::State::_execstate_roundtrip_ok(), 1,
        "round-trip is exact with a live local() on the save stack";
}
