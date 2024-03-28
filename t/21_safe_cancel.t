$|=1;
print "1..10\n";

use EV;
use AnyEvent;
#use AnyEvent::Strict;
use Coro;
use Guard;

my $wakeup = AE::cv;
my $lock = AE::cv;
my $ref;
my $coro = async {
  my $guard = guard {
    print "ok 6 - guard called\n";
  };
  # Somehow, necessary to reproduce the problem.
  # We've seen refcnt errors as well... so maybe related.
  $ref = $wakeup;

  my $timer = AE::timer 1, 0, sub { $wakeup->(1); };
  print "ok 2 - coro waiting\n";
  $wakeup->recv;
  print "notok 10 - coro cancelled\n";
  exit 1;
};
$coro->on_destroy(sub {
  print "ok 7 - enter destroy\n";
  $lock->send;
  print "ok 8 - leave destroy\n";
});

print "ok 1 - coro created\n";

Coro::cede;
print "ok 3 - coro ready\n";

$coro->safe_cancel();
print "ok 4 - coro cancelled\n";

$coro->join();
print "ok 5 - coro joined\n";

# Segfault here.
$lock->recv;
print "ok 9 - coro destroyed notified\n";

$coro = undef;
print "ok 10 - coro freed\n";

