# Architecture: how tracks are generated

## Layers

| Layer | Files | Depends on |
|---|---|---|
| Hashing / seeds | `scripts/util/hash64.gd` | — |
| Module library | `resources/modules/catalog.json`, `scripts/generation/track_spec.gd`, `track_module_def.gd`, `module_catalog.gd` | hashing (fingerprint) |
| Generation rules | `track_generator.gd`, `reachability_validator.gd`, `overlap_grid.gd`, `generator_config.gd`, `level_definition.gd`, `track_placement.gd` | module library |
| Rendering + collision | `scripts/track/track_mesh_builder.gd`, `track_view.gd`, `track_decor.gd`, `moving_obstacle.gd` | generation output |
| Tracking | `scripts/track/track_tracker.gd` | placements |
| Physics control | `scripts/physics/marble.gd`, `marble_mesh.gd` | — |
| Game flow | `scripts/game/*.gd` (`game.gd`, `track_session.gd`, `level_progression.gd`, `follow_camera.gd`, `steer_input.gd`, `autopilot.gd`, `app.gd`) | everything above |
| Persistence | `scripts/persistence/save_data.gd` | — |
| UI | `scripts/ui/*.gd` | game flow |

Generation never touches the scene tree, so it runs headless in tests and can be
reused by tools.

## Modules

A module is defined **analytically in local space**: the entry connector is the
origin, forward is −Z, up is +Y. The centreline is a function of horizontal arc
length `s ∈ [0, L]`:

* heading `yaw(s)` — `arc`: eased arc `turn·(t − sin 2πt / 2π)`; `s`: lane-shift
  S-bend `A/2·(1 − cos 2πt)`; otherwise 0;
* height `y(s) = grade·s + elevation·smootherstep(t) − wave·sin²(π·n·t)`;
* banking proportional to curvature, cross-section width/wall/dish blended by a
  window that is 0 at both ends.

Every one of these functions has, at `t = 0` and `t = 1`: zero curvature, zero
bank, slope == the shared `grade`, and the standard profile. Therefore the last
cross-section ring of any module equals the first ring of any other module placed
at its exit. Connectors are **yaw-only** transforms (`exit_transform`); the shared
grade is implied. Modules are assembled by multiplying connector transforms — no
module assumes a size.

Module parameters (length, turn, elevation, wave, width/wall scale, dish, bank,
difficulty, tier, weight, min entry speed, obstacle layouts, jump geometry,
colour) live in `catalog.json`. The 12 required module kinds are present (straight, gentle/sharp
left/right, downhill, uphill, wavy, S-curve, funnel/bowl, narrow bridge, static
and moving obstacle segments) plus `start`, `finish`, `straight_long`,
`downhill_steep`.

## Environments

`catalog.json → environments` defines four environments: `classic` (trough),
`tube`, `wires` and `ramps` (trough, jump modules boosted). Each has a tier, a
weight, the module types it allows and per-type weight boosts. The generator
keeps an environment for a run of 3–6 modules (`environment_run`), then picks the
next one from the RNG; a new run of a styled environment must change style.

A placement stores its environment and **style** (`trough`, `tube`, `wires`).
Style is applied *inside* a module: the cross-section blends from the standard
trough profile to the style over the first 12 % (tube) or 30 % (wires — a long,
~18° funnel with raised walls) of the module, and back at the end. Blending
happens only where the neighbour has a different style (`blend_in`/`blend_out`),
so a run of tube or wire modules is continuous, and every connector between two
different styles is the standard ring.

* **tube**: the 15 collision points are blended onto a nearly closed circle
  (radius 1.1 m, 4° gap at the top); faces point inwards. Rendered with a
  translucent, double-sided material, opaque at the bottom.
* **wires**: rendered as three round hexagonal wires with brackets. Collision is
  three narrow flat strips on the wire surfaces facing the marble — round wire
  meshes made the marble chatter between three convex prisms and lose a lot of
  speed. The side wires leave 1.4 cm of play, so the marble rests on the bottom
  wire; lateral grip is `0.5 × dx/dy` g of the side-wire contact geometry.
  Inside the funnel the side wires flare out to the funnel walls, and the wire
  strips start 8 cm below the funnel floor and rise to it while the floor sinks
  away, so the marble never meets the leading edge of either surface (a flush
  edge kicked it up at speed).
* **jumps** (`jump`, `jump_big`): a parabolic kicker up to the lip, an air gap
  with no geometry, and a landing whose slope is steepest at the start, with
  wider, taller walls. Collision is split into two strips at the gap.

Collision strips are keyed (`surface`, `w0`, `w1`, `w2`); at a connector each
strip that starts at the entry reuses the previous module's last ring of the
strip with the same key.

## Seeds

* Level seed: `level_seed(n) = splitmix64(MASTER_SEED ^ splitmix64(n))`,
  `MASTER_SEED = 0x4D4152424C450001`. SplitMix64 is implemented with 16-bit limbs
  (`Hash64.mul/add/shr`) so it never relies on signed overflow; values are checked
  against Python reference values in `tests/test_hash.gd`.
* Each generation creates its **own** `RandomNumberGenerator` seeded with the
  64-bit seed. Candidate lists are built in catalogue file order; the overlap grid
  is only queried by key, never iterated.
* Track code shown in the HUD: `SEEDHEX-DIFFICULTY-SEGMENTS`, e.g.
  `94DF7E97AD170C8E-3-14`. Entering it reproduces the level.

## Generation loop (LEVEL mode)

```
place start
while placed < segment_count and attempts < budget (60 × segments):
    try up to 8 weighted random candidates (no repeats), then deterministic
    fallbacks [straight, gentle turn back toward heading 0, downhill, …]
    if nothing fits: backtrack (remove last module)
place finish (backtracking until it fits — start+finish always fits)
assign checkpoints
```

Candidate weights: `weight × gaussian(difficulty − preferred)`, preferred rising
with target difficulty; turns that push the net heading past ±70° are
down-weighted, turns back are up-weighted; past ±150° they are rejected.

A candidate is accepted only if all constraints pass:

1. **Sequencing** — after a module with difficulty ≥ 3 the next must be ≤ 2
   (recovery); the sum of the last three difficulties is capped.
2. **Reachability** (`ReachabilityValidator`, below).
3. **Overlap** — every centreline sample (≈ 0.8 m apart) is checked against all
   earlier modules except the direct predecessor: horizontal clearance
   `r_a + r_b + 0.6 m` unless the vertical separation is ≥ 4 m.

Termination: attempts are bounded by the budget; the finish loop only removes
modules. Measured over 1000 seeds (generator v3): max 68 attempts, ≈ 20 ms mean / 33 ms
max per level on desktop, 0 short levels.

## Reachability validator

The validator integrates speed along each module's samples for a rolling sphere:

```
v_next = sqrt(v² − 2·g·(5/7)·Δy) − c·Δs
```

with an effective loss `c` calibrated against Jolt (`test_calibrate_terminal_speed`
measures ≈ 0.10; the validator uses 0.10). It tracks a **pessimistic** speed
(`c × 1.5`, plus a 50 % speed loss after obstacle modules) and an **optimistic**
speed (`c × 0.5`), and rejects a module when:

* pessimistic speed < 1 m/s anywhere or below the module's `min_entry_speed` (stall);
* optimistic `v²·κ` exceeds what banking + walls can hold
  (`g·(sin bank + 0.5·wall_ratio)`);
* optimistic speed would leave the surface on a crest (`v²·|κ_v| > 0.7·g·cosθ`) —
  no jumps are designed, so none are allowed;
* slope is outside [−0.75, +0.25]; optimistic speed > 14 m/s, or > 9 m/s on a narrow
  section;
* in a tube, curves may use 2 g of grip and crests are allowed (the ceiling
  holds the marble); on wires the grip is the side-wire geometry above;
* **jumps**: at the lip both the pessimistic and the optimistic speed are flown
  ballistically from the lip's slope; each must land at least 0.4 m past the
  start of the landing and at least 2 m before the module end. The speed kept
  along the landing surface (normal component lost) plus the height gained to a
  common restart ring continues the integration; the pessimistic speed loses a
  further 15 %;
* an obstacle row leaves no lane ≥ 0.25 m of free centre space (moving sweepers
  are treated as blocking their full sweep), or consecutive lanes require more
  than half the available steering acceleration at the optimistic speed.

### Skill demands (generator v3)

At difficulty 1 everything above must hold **hands-off**. Above that,
`TrackGenerator.skill_for(difficulty)` (0 … 0.9) lets the validator accept a
section the marble would *not* survive on its own if the player can fix the
speed in the run-up (the previous module plus the distance into this one):

* too fast for a curve, crest, narrow section or the speed cap → accepted if
  braking at `4.0 × skill` m/s² over 60 % of the run-up reaches 95 % of the safe
  speed; the optimistic speed is then capped to it and the pessimistic speed
  assumes over-braking to 80 %;
* a jump has a take-off window (`jump_window`, e.g. 3.8–9.2 m/s for `jump`);
  arriving too fast needs braking as above, too slow needs boosting at
  `2.3 × skill` m/s² over 60 % of the run-up.

Each accepted demand is stored on the placement as a speed limit
`Vector3(s, v_min, v_max)`. The game puts a red (brake) or green (boost) sign
8 m before it and shows BRAKE!/BOOST! when the current speed won't make it; the
autopilot uses the same `Autopilot.speed_advice` to brake/boost. Boost is 3.5 N
along the track (up to 15 m/s); brake is 6 N against the motion and never
reverses.

This is deliberately conservative and still **does not prove** a level is
completable. `tests/test_physics.gd` additionally drives an autopilot through 30
generated levels with real physics (30/30 finished) and `test_endless.gd` runs 90 s
of streamed endless track.

## Collision and seams

All active modules are merged into one `ConcavePolygonShape3D`. When a module is
added, its first collision ring is replaced by the previous module's last ring so
joins share bit-identical vertices (raw mismatch before snapping is < 1 mm). Jolt
then treats the joint like any internal mesh edge. `test_joins_have_no_seams` rolls
over 12 consecutive joins: the marble never lifts more than 0.4 mm off the floor.
Obstacles are separate convex bodies; sweepers are `AnimatableBody3D` driven by
the physics-tick game clock.

## Endless mode

`TrackGenerator.create_endless(seed)` returns an `EndlessStream` with its own RNG
(a separate seed, so it can never affect level generation). `TrackSession` keeps
10 modules ahead and 3 behind (never deleting the active checkpoint), rebuilds the
merged collision after each change (≈ 6k triangles), and recycles module
`MeshInstance3D` nodes. The stream never backtracks (modules may already be
visible); if nothing validates it forces `downhill_steep`, which drops below
earlier track — 0 forced placements in 10 000 tested modules. Target difficulty
rises by 0.04 per module up to 7. Only the last 8 placements and the overlap
samples of active modules are kept in memory.

## Versioning

`TrackGenerator.VERSION` plus `FINGERPRINTS[VERSION]`: an FNV-1a 64 hash of the
canonical catalogue JSON, generator constants and validator constants. The test
`test_generator_version_fingerprint` fails if anything changes without bumping the
version and recording the new fingerprint; `test_golden_levels` pins the logical
hash of levels 1–5 and 10. Saves record the generator version with the last
played track, and best times are keyed `v<version>:L<n>` so times from different
generator versions never mix.

To change generation: edit, run tests, bump `VERSION`, add the printed fingerprint
to `FINGERPRINTS`, and update `GOLDEN` in `tests/test_generation.gd`.
