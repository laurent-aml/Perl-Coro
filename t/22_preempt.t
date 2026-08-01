$|=1;
print "1..11\n";

use Coro qw(async cede cede_pending cede_slice preempt current);
use Time::HiRes ();

sub busy { my $t = Time::HiRes::time + $_[0]; 1 while Time::HiRes::time < $t }

print "ok 1\n";

# a background thread that stays runnable and counts how often it runs
my $ran = 0;
my $bg  = async { while () { ++$ran; cede } };

#############################################################################
# cede_pending only cedes after preempt has been called

$ran = 0;
cede_pending for 1 .. 20;         # no preempt yet => must not cede
print $ran == 0 ? "ok 2\n" : "not ok 2 # bg ran $ran times\n";

preempt;                          # request a cede
cede_pending;                     # ... honoured here
print $ran == 1 ? "ok 3\n" : "not ok 3 # bg ran $ran times\n";

cede_pending for 1 .. 20;         # flag was cleared => must not cede again
print $ran == 1 ? "ok 4\n" : "not ok 4 # bg ran $ran times\n";

# preempt is callable from a (deferred) signal handler
$ran = 0;
{
  local $SIG{ALRM} = sub { preempt };
  Time::HiRes::alarm 0.01;
  cede_pending until $ran;        # spin until the alarm fires and we honour it
  Time::HiRes::alarm 0;
}
print $ran >= 1 ? "ok 5\n" : "not ok 5 # bg ran $ran times\n";

#############################################################################
# cede_slice and the per-coro interval

# default interval is 2ms
print current->cede_interval == 0.002 ? "ok 6\n" : "not ok 6 # ".current->cede_interval."\n";

# set / get, and 0 restores the default
current->cede_interval (0.05);
print current->cede_interval == 0.05 ? "ok 7\n" : "not ok 7\n";
current->cede_interval (0);
print current->cede_interval == 0.002 ? "ok 8\n" : "not ok 8\n";

# a fresh call arms the budget and must NOT cede immediately, even if lots of
# wall-clock time has already passed
current->cede_interval (0.02);
busy 0.05;
$ran = 0;
cede_slice;                       # first call in a while: arm only
print $ran == 0 ? "ok 9\n" : "not ok 9 # bg ran $ran times\n";

# running continuously past the budget forces a cede
busy 0.05;
$ran = 0;
cede_slice;
print $ran == 1 ? "ok 10\n" : "not ok 10 # bg ran $ran times\n";

# a natural reschedule re-arms the budget: cede_slice right after an explicit
# yield must not fire again, even though the wall-clock budget is exceeded
busy 0.05;
cede;                             # natural yield -> budget restarts
$ran = 0;
cede_slice;
print $ran == 0 ? "ok 11\n" : "not ok 11 # bg ran $ran times\n";
