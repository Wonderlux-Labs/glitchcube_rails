# frozen_string_literal: true

# Deterministic, no-wall-clock stand-in for PerformanceModeService::RealClock.
#
# `now` is virtual time the test controls; `sleep` never blocks — it simply
# advances `now` by the requested seconds. That lets a spec drive
# `run_performance_loop` to completion (the loop exits once `now` reaches
# `@end_time`) in microseconds, with no real sleeping and no flaky timing.
#
# Inject it via the constructor or the class seam:
#
#   clock = FakeClock.new(Time.current)
#   PerformanceModeService.new(..., clock: clock)
#   # or, to affect every new service in a spec:
#   PerformanceModeService.clock = clock
#   ... PerformanceModeService.reset_clock! in an after hook
#
class FakeClock
  attr_reader :now

  def initialize(start = Time.current)
    @now = start
  end

  # No real waiting — just move virtual time forward. This is what bounds the
  # performance loop: sleeps accumulate until `now` passes `@end_time`.
  def sleep(seconds)
    @now += seconds
    seconds
  end

  # Manually jump time forward (e.g. to expire a performance immediately).
  def advance(seconds)
    @now += seconds
  end
end
