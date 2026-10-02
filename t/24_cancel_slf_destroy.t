$|=1;
print "1..6\n";

# safe_cancel of a coro blocked inside an SLF call that armed an on_destroy
# callback, where the object that callback works on is dropped before the
# cancelled coro is destroyed.
#
# safe_cancel calls slf_destroy, which runs the on_destroy and lets go of what
# it held - then re-arms slf_frame.prepare while leaving slf_frame.destroy and
# .data pointing at that same object.  Destroying the coro later called
# slf_destroy a second time, which ran the on_destroy again, by then on memory
# nobody owned: a segfault, or "Attempt to free unreferenced scalar".
#
# Coro::Semaphore is used because down () on an exhausted semaphore is an SLF
# call that arms one; nothing here is specific to semaphores.

use Coro;
use Coro::Semaphore;

my $sem = Coro::Semaphore->new (0); # exhausted, so down () blocks
print "ok 1 - semaphore created\n";

my $coro = async {
   $sem->down; # parks in the SLF, with its on_destroy armed
};
print "ok 2 - coro created\n";

cede; # let it reach the block
print "ok 3 - coro blocked in down\n";

$coro->safe_cancel;
print "ok 4 - coro cancelled\n";

# The point of the test: nothing else holds the semaphore now, so the pointer
# the frame kept is stale from here on.
undef $sem;

cede for 1 .. 3; # let the cancellation run to the end
print "ok 5 - cancellation completed\n";

undef $coro; # second slf_destroy: used to crash here
print "ok 6 - coro freed\n";
