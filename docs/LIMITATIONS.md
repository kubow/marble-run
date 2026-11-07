# Known limitations

## Not verified

* **No Android device was available.** The debug APK was built, signed and its
  manifest inspected, but installation, startup, touch steering and on-device
  frame rate were not tested. Desktop numbers (Radeon 860M iGPU, level 10,
  autopilot, vsync off): ~0.8 ms/frame Mobile renderer, ~1.05 ms Compatibility
  renderer; ≈ 27k primitives and ≈ 130 draw calls per frame; physics step
  ≈ 0.07 ms. Mid-range phone performance is expected to be fine but is unmeasured.
* **Completability is not proven.** The analytic validator is conservative and
  an autopilot finished 30/30 generated levels with real physics, but a human
  player, a different frame rate, or rare seeds could still produce a section that
  is frustrating or (unlikely) impossible.

## Determinism

* Same seed + same generator version + same catalogue ⇒ same level on the same
  build (tested). Generation uses floating-point geometry for overlap/speed
  checks; on a different CPU architecture or Godot version, a comparison that is
  exactly on a threshold could in principle resolve differently. Seeds are
  integer-exact (SplitMix64 with limb arithmetic).
* Godot's `RandomNumberGenerator` (PCG32) implementation is assumed stable; the
  generator fingerprint does not include the engine version.
* Only the current generator version can be regenerated. A saved track code from
  an older version is regenerated with the new rules (the game warns), and its
  best times stay under the old version key.

## Physics / gameplay

* Wire collision is an approximation: flat contact strips where the marble
  touches each round wire. A marble that climbs far over a side wire leaves the
  strip earlier than it would leave a real round wire.
* Jump validation flies the marble centre ballistically along the track; spin,
  lateral offset and air drag are ignored (margins cover typical cases; the
  physics tests fly real jumps).
* Validation assumes no throttle. A player can boost past curve/crest limits or
  brake before a climb or jump — that is intended as player skill/risk.
* At the end of a tube, a marble riding high on the tube wall comes down onto the
  open track as the profile blends back; at high speed this can throw it off.
* Single-tick vertical velocity blips (≈0.1 m/s, no lift-off) occur when the
  marble crosses triangle edges; joins between modules behave like any internal
  edge (tested).
* Moving sweepers are treated by the validator as blocking their whole sweep, so
  they only threaten a marble that leaves the safe lane.
* Stalling (e.g. after hitting an obstacle before a climb, or braking too much)
  returns the marble to the last checkpoint.
* The camera can pass close to/through a higher track section crossing above
  (minimum vertical clearance is 4 m).

## Endless mode

* The track descends forever; coordinates are not re-centred, so float precision
  degrades after tens of kilometres (far beyond a typical run).
* The merged collision shape (~6k triangles) is rebuilt every time a module is
  added or removed. This is cheap on desktop; not profiled on a phone.
* If no module validates, a steep downhill is forced without the overlap check
  (0 occurrences in 10 000 tested modules).

## Build / platform

* APK size (~27–28 MB) is dominated by the stock Godot engine library. A custom
  export template with unused modules disabled would shrink it substantially.
* arm64-v8a only.
* Built with OpenJDK 27 (non-Gradle export only needs keytool/apksigner); Gradle
  builds need JDK 17.
* With mouse-to-touch emulation on desktop, clicking a HUD button can also start a
  brief steering drag.
* UI is constructed in code rather than in editor scenes; fine for this scope,
  less convenient for visual editing.
* No audio.
* Headless runs print one Jolt warning at level load ("job system exceeded the
  maximum number of jobs … waiting"). It is engine-internal, harmless (Jolt
  waits), predates the v2 changes, and does not appear in windowed runs.

# Future extensions

* More modules: loops, half-pipes, split paths, spinners, moving platforms,
  boost pads; jumps with curves; spiral tubes.
* Tilt (accelerometer) steering option and haptics.
* Ghost replay of the best run (inputs are already applied per physics tick).
* Daily seed, local leaderboard per track code.
* Origin re-centring for endless mode; object pooling for obstacles.
* Custom, size-optimised export templates; armeabi-v7a build.
* Keeping old generator versions callable so historic codes regenerate exactly.
* Audio: rolling sound pitched by speed, impacts, music.
