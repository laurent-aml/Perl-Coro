=head1 NAME

Coro::Atomic - run a critical section without yielding to other coroutines

=head1 SYNOPSIS

   use Coro::Atomic;

   # block form
   my $sum = atomic {
      # no other coro can run until this block finishes; a cede or a
      # blocking call inside here is a fatal error, not a silent yield
      $shared->{a} + $shared->{b};
   };

   # scoped form - the enclosing scope is the section
   {
      scoped_atomic;
      ... critical section ...
   } # released here (also on die / early return)

   # attribute form - e.g. cleanup that must never yield
   sub DESTROY :Atomic {
      ... guaranteed to run to completion without ceding ...
   }

=head1 DESCRIPTION

B<Experimental / unpublished.>  Coro is cooperative, so a coro only ever yields
where it (directly or transitively) calls something that cedes or blocks.  The
catch is that a plain method or sub call does not advertise whether it might
cede somewhere inside, so it is hard to be sure a critical section runs without
interleaving - and cleanup code such as C<DESTROY> can cede at a moment where
that is unsafe.

An C<atomic> section makes the guarantee explicit and enforced: while it is in
effect the running coro B<must not> yield.  Any attempt to - an explicit
C<cede>/C<schedule>, or a blocking primitive such as C<< Coro::Semaphore->down >>
or a condvar wait - is a fatal error rather than a silent yield.

The check sits at Coro's scheduler entry points (so it catches C-level blocking
too) and fires B<deterministically>, before any scheduler state is touched: it
does not depend on whether another coro happens to be runnable, so a stray
C<cede> inside an atomic section is I<always> caught, not merely when something
else is ready to run.  This makes it a reliable assertion for cleanup code such
as C<DESTROY> that must never yield.

The name is deliberately not Coro-specific: an C<atomic> region is one that runs
as a single indivisible step with respect to the other tasks, the same sense the
word carries in software-transactional-memory C<atomic> blocks.

The three forms are equivalent; pick whichever reads best:

=over 4

=item C<< atomic { BLOCK } >>

Run C<BLOCK> as a critical section and return its value (in the caller's
context).  The section is ended when the block returns or dies.

=item C<< scoped_atomic >>

Enter a critical section now; it ends at the exit of the enclosing scope (also on
early return or exception).  The scope is the section's extent, enforced.

=item C<< sub name :Atomic { ... } >>

Wrap a whole subroutine so its body runs as a critical section.  Especially
useful for C<DESTROY> and other cleanup that must not yield.  Requires
C<use Coro::Atomic> to have been loaded (the attribute is installed globally).
The attribute is capitalised because Perl reserves lower-case attribute names
for its own future use (a C<:atomic> attribute would warn under C<use warnings>);
the C<atomic { }> function and C<scoped_atomic> keep the lower-case spelling.

=back

=cut

package Coro::Atomic;

use common::sense;

use Coro ();

use Exporter 'import';

our $VERSION = $Coro::VERSION;

our @EXPORT    = qw(atomic);
our @EXPORT_OK = qw(atomic scoped_atomic);

# scoped_atomic is an XSUB (Coro::State, package Coro::Atomic) - it has to be,
# because it attaches its release to the scope of whoever called it, so putting a
# perl wrapper in front would bind it to the wrapper's scope instead.

# helper: run $code in the given call context, holding the atomic section for
# the duration (this sub's scope releases it even if $code dies).
sub _run_atomic {
   my $code = shift;
   scoped_atomic;

   if (wantarray) {
      my @r = $code->(@_);
      return @r;
   } elsif (defined wantarray) {
      my $r = $code->(@_);
      return $r;
   } else {
      $code->(@_);
      return;
   }
}

=head1 FUNCTIONS

=over 4

=item scoped_atomic

Enter an atomic section that lasts from the call to the end of the enclosing
scope - including on early return or exception:

   {
      scoped_atomic;
      ... critical section ...
   } # released here

The extent of the section is fixed by where the call appears: it is exactly the
enclosing scope, and that is enforced rather than merely conventional.  Nothing
is returned and nothing has to be kept alive, so the section cannot be made to
outlive the scope it is written in - reading the code is enough to know where it
ends.

Sections nest; each call releases exactly its own level.  Modelled on
C<Coro::Multicore::scoped_disable>.

=item atomic { BLOCK }

=cut

sub atomic(&) {
   &_run_atomic;
}

=back

=cut

# --- the :atomic code attribute --------------------------------------------
# Installed globally: using Attribute::Handlers (a core module) from within
# package UNIVERSAL installs the recognizer (UNIVERSAL::MODIFY_CODE_ATTRIBUTES)
# for every package, so any code that has loaded Coro::Atomic may write
# `sub foo :atomic { ... }`.  The handler redefines the sub to run its body in
# an atomic section.
{
   package UNIVERSAL;

   use Attribute::Handlers;

   sub Atomic :ATTR(CODE) {
      my (undef, $glob, $orig) = @_;

      no warnings 'redefine';
      *$glob = sub { Coro::Atomic::_run_atomic ($orig, @_) };
   }
}

1;

=head1 SEE ALSO

L<Coro>, L<Coro::Multicore>.

=cut
