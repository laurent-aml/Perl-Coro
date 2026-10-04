package Alt::Coro::GT;

our $VERSION = 6.5702;

1;

__END__

=head1 NAME

Alt::Coro::GT - Coro for green threads, on top of the execstate interface

=head1 SYNOPSIS

   # this replaces the Coro you have, so it refuses to install silently
   PERL_ALT_INSTALL=OVERWRITE cpanm Alt::Coro::GT

   # or stage it somewhere harmless and look at it first
   PERL_ALT_INSTALL=/tmp/alt-coro cpanm Alt::Coro::GT

   # afterwards nothing changes for the caller
   use Coro;

=head1 DESCRIPTION

This is an L<Alt> distribution: an alternative implementation of Coro. It
installs the real C<Coro>, C<Coro::State> and the rest of the C<Coro::*>
modules, so installing it B<replaces> whichever Coro you currently have.
Only C<Alt::Coro::GT> is indexed on CPAN; the modules it ships under the
C<Coro> namespace are not, and it will not install at all unless you ask it
to - see L</INSTALLING>.

It follows upstream Coro 6.57 by Marc A. Lehmann, and is a drop-in
replacement for it: same API, same module names, same versions. The C<GT>
is for green threads, which is what the fork exists to support - it is the
Coro half of a green-thread stack whose other halves are a perl exposing an
interpreter execution-state API and L<Coro::Multicore>.

=head1 WHAT IS DIFFERENT

Relative to upstream Coro 6.57:

=over 4

=item Green threads on core's execstate API

The interpreter execution state - the set of per-thread registers a context
switch has to save and restore - is reached through an "execstate" interface
offered as a capability ladder: level 1 register save/load, level 2 the stack
lifecycle, level 3 the pad primitives, level 4 the JMPENV transfer registers.
F<State.xs> uses the perl's own API where the perl provides one and falls back
to its own copy otherwise, so the register list is no longer duplicated here
for every perl release.

=item Cooperative preemption

C<cede_pending>, C<preempt> and C<cede_slice>, so a long-running thread can be
asked to yield from the outside instead of having to poll the scheduler itself.

=item Coro::Atomic

Critical sections that must not yield, spelled C<atomic { }>, C<scoped_atomic>
or the C<:Atomic> attribute. A transfer inside one croaks, so a section that
must not be interleaved fails loudly rather than interleaving quietly.

=item CoroAPI revision 4

Adds C<atomic_count>, so an XS module can ask from C whether the running thread
is inside such a section. L<Coro::Multicore> needs this on the paths where it
would otherwise hand the interpreter to another thread or suspend for an
offload, and uses it from 1.0701 onwards.

=item Coro::EV as a Coro::Multicore watcher

L<Coro::EV> can register itself as Coro::Multicore's wakeup-pipe watcher, so
that module no longer requires L<AnyEvent> to be loaded.

=item Windows: the assembler backend

On Windows the assembler backend is now the default where the machine has one
(x86, x86_64) and the compiler takes GNU-style inline asm - MinGW, not MSVC.
Everything else keeps fibers. Besides being faster and leaner it is the only
backend that supports Coro::Multicore's release/acquire needs. 32-bit ARM and
arm64-on-Windows stay off by default but are selectable with C<CORO_INTERFACE=a>;
aarch64 is implemented but untested, pending an aarch64 Strawberry Perl.

=item Fixes

Three crashes:

=over 4

=item *

Stack corruption when C<safe_cancel> unwinds a thread that had used C<local>.
The scope
stack was left before the context stack was unwound, so inner-frame save-stack
entries - a localised hash element, a C<SAVEt_CLEARSV> - were processed while
the pad was still at the innermost frame's depth, leaving an outer frame's pad
slot stale. That wrecks refcounts and asserts or segfaults inside
C<Perl_leave_scope> on perls carrying the 5.24 save-stack handling. Seen with
C<< ->safe_cancel >> of a thread blocked in a condvar.

=item *

A segfault when C<safe_cancel> cancels a thread blocked inside an SLF call
that armed an C<on_destroy> callback, reachable through L<Coro::Semaphore> and
L<Coro::Channel>.

=item *

A segfault when any XSUB taking a C<Coro::State> is handed a hash that is not a
coro. The argument probe checked the SV was a hash and then read its magic
without first checking there was any, so a blessed object standing in for a
coro - or a bare C<{}> - dereferenced NULL before the C<Coro::State object
required> croak could happen. Non-hashes were never affected.

=back

And two smaller ones: an abort on a C<-DDEBUGGING> perl when registering an
enterleave hook that takes no argument, and building with a C23 compiler and
with gcc in C<-std=c99> mode.

=back

F<Changes> carries the full history; entries belonging to this fork are marked
C<(fork)>.

=head1 INSTALLING

Per the L<Alt> guidelines this distribution will not install unless you say so,
because doing it replaces a module you may not have meant to replace. Set
C<PERL_ALT_INSTALL> when building:

=over 4

=item C<PERL_ALT_INSTALL=OVERWRITE>

Install over the Coro already in C<@INC>. This is what you want to actually use
it.

=item C<PERL_ALT_INSTALL=/some/path>

Install under that path instead, as a C<DESTDIR>, to inspect the result before
committing to it.

=item unset

The build runs and the tests run, but C<make install> stages into a directory
named F<no-install-alt> and touches nothing real.

=back

=head1 DEVIATIONS FROM THE ALT GUIDELINES

Two, both deliberate.

=over 4

=item The modules keep their C<$VERSION>

The guidelines say not to declare C<$VERSION> in the modules providing the
alternate, so that the alternate does not satisfy a version requirement on the
original. That rule assumes an alternate which is not necessarily
API-compatible, and applying it here would cause the substitution it exists to
prevent: this fork tracks a specific upstream release and is pinned by name and
version across a stack. A CPAN client resolving, say, C<< Coro => 6.44 >> checks
the installed version first, finds 6.5702, is satisfied, and leaves the tree
alone. With no C<$VERSION> the same client concludes Coro is missing, resolves
C<Coro> through the index - which points at the original distribution, not this
one - and installs upstream Coro straight over the fork.

Indexing is a separate matter and is handled the documented way, with
C<no_index>, which is what keeps PAUSE from indexing C<Coro> and C<Coro::*> to
this distribution. C<$VERSION> plays no part in that.

=item C<use Alt::Coro::GT;> is in three modules, not all of them

The guidelines suggest loading the Alt module from the alternates, so it shows
up in C<%INC> and you can see which Coro you got. That is done in C<Coro>,
C<Coro::State> and C<Coro::MakeMaker> - every entry point that is loaded
standalone - rather than in all 23 modules, to keep the diff against upstream
small enough to rebase onto future Coro releases.

=back

=head1 SEE ALSO

L<Coro> for the module itself, L<Alt> for what an Alt distribution is,
L<Coro::Multicore> for the other half of the stack.

=head1 AUTHOR

Laurent Aml <laurent.aml@gmail.com>

Coro itself is by Marc A. Lehmann <schmorp@schmorp.de>; this distribution is a
fork of it and not a replacement for the original in any sense other than the
technical one described above.

=head1 LICENSE

Same terms as Coro itself: this library is free software, you can redistribute
it and/or modify it under the same terms as Perl itself.

=cut
