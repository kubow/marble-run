# Balance

How hard and how varied the level progression is, measured rather than guessed.
Regenerate with:

```sh
godot --headless --fixed-fps 60 --path . -s res://tools/level_stats.gd -- 15
```

Columns: environment mix (modules), number of jumps, modules with difficulty
≥ 2.5 ("hard"), mean module difficulty, speed demands the generator placed
(`brk` = must brake, `bst` = must boost, each telegraphed by a red/green sign),
and two physics runs per level: **no input at all** (a level finished hands-off
asks nothing of the player) and the **autopilot** (steering + braking/boosting
like a careful player — must finish).

Generator v3:

```

lvl diff segs  len   classic tube wires ramps | jumps hard  meanD brk bst | no-input        | autopilot
  1  1.0   10   141       8    2     0     0 |     0    0   0.70   0   0 | finished   96% | finished 23s
  2  2.2   12   201       4    0     3     5 |     3    0   1.17   7   1 | finished   97% | finished 33s
  3  3.4   14   241       8    0     0     6 |     4    2   1.57   9   1 | fell       64% | finished 40s
  4  4.6   16   261       7    0     5     4 |     3    2   1.62   4   1 | fell       44% | finished 41s
  5  5.0   18   359       4    3     0    11 |    11    9   1.94   6   3 | finished   98% | finished 52s
  6  5.4   20   340      11    2     0     7 |     6    4   1.80   7   1 | finished   98% | finished 61s
  7  5.8   22   364      11    0     8     3 |     4    4   1.75  10   3 | fell       81% | finished 65s
  8  6.2   24   455       7    3     5     9 |     9    8   1.88  15   4 | stalled    30% | finished 67s
  9  6.6   26   440      15    0     8     3 |     5    6   1.79   9   2 | fell       13% | finished 80s
 10  7.0   28   446      10    3    11     4 |     3    6   1.84  13   2 | stalled    29% | finished 79s
 11  7.4   30   562       7    0    12    11 |     9    8   1.90  21   2 | finished   99% | finished 81s
 12  7.8   32   541      16    0     5    11 |     9    9   1.92  13   5 | fell       19% | finished 98s
 13  8.0   34   525      11    2    15     6 |     6    6   1.81  11   2 | fell       16% | finished 96s
 14  8.0   36   566      18    3     9     6 |     6   10   1.89  15   2 | fell       10% | finished 97s
 15  8.0   38   689      19    0     6    13 |    10   12   2.01  24   5 | fell       21% | finished 100s
totals: { "classic": 156, "tube": 18, "jumps": 88, "brake": 164, "boost": 34, "wires": 87, "ramps": 99 }
no-input finished 5/15 (lower = more demanding), autopilot finished 15/15
```

## Knobs

| What | Where | v3 value |
|---|---|---|
| Level difficulty curve | `LevelProgression.difficulty_for` | 1, 2.2, 3.4, 4.6, then +0.4/level, max 8 |
| Level length | `LevelProgression.segments_for` | 10 + 2/level, max 40 |
| Demanded skill (brake/boost share) | `TrackGenerator.skill_for` | (difficulty − 1.2) / 3, max 0.9; 0 at level 1 |
| Preferred module difficulty | `TrackGenerator.preferred_difficulty` | 0.7 + 0.45 × difficulty, max 3.5 |
| Environment weights / run lengths | `catalog.json → environments` | classic 4, tube 1 (runs 2–3), wires 2 (3–5), ramps 3 (3–6) |
| Base speed | `catalog.json → track.grade` | −0.085 |
| Endless ramp | `EndlessStream` | starts at 1.5, +0.06 per module, max 7 |

Changing any of these changes generated levels: bump `TrackGenerator.VERSION`
(see README → Changing generation).

## History

| Version | Hands-off finishes (levels 1–12) | Jumps (1–12) | Tube modules (1–12) |
|---|---|---|---|
| v2 | 8 / 12 | 6 | 60 |
| v3 | 5 / 12 | 66 | 13 |
