# Design notes

Engineering rationale, the numbers behind the snap features, and how the design was verified.
Model v33. Everything here was measured against the solid model in Fusion.

**v1 was printed and assembled. Nothing since v1 has been printed** — every figure below for v2
and later is CAD verification, not experience.

## Thermal concept

The units are metal-shelled passive heat spreaders with two internal blowers exhausting rearward,
plus filtered intakes along both long edges of the front face and a filtered intake in the bottom
panel. Standing them on edge exposes the bottom panel to a side fan, which is the largest single
intake either unit has.

- Two side fans blow inward through each unit's filtered bottom panel.
- The front fan pressurises a sealed plenum. Its Ø114 throat opens into the plenum through a 45°
  diffuser chamfer, and two mouth windows feed the units' front intakes.
- A hollow centre duct in the 19 mm gap between the units takes air from two ram scoops sited at
  r = 38–58 mm from the fan axis — inside the blade annulus, clear of the Ø42 hub wake — and
  exits through two 3 × 112 mm slots that jet down each hot inner panel.

The centre duct is a calculated design, not a measured one. Its two exit slots are tapeable, so
an A/B test is easy: tape them, run the same load, compare.

## Fastening

Nothing is screwed. Five mechanisms carry the whole assembly.

| Joint | Mechanism | Numbers |
|---|---|---|
| Arm → tray | 45° half-dovetail, slides in from the rear | 0.12 mm clearance both flanks, 150 mm travel, hard stop at the front |
| Arm → brace | Two cantilever latch barbs into catch pockets | 1.30 mm barb, 0.63 % strain at release, 4.6 N per latch to release, 0.90 mm retained engagement |
| Grille → collar | Four cantilever hooks, 18 × 1.3 × 10 mm, 1.5 mm barb | 1.08 % strain, 2.8 N per hook, ~11 N to click on |
| Plenum → brace | Tusk tenon through a mortise, locked by a wedge key | 0.65 mm of taper available for tightening |
| Button pin → tube | Split shaft, two spring legs, two-pad snap barb | 0.45 mm squeeze needed against 1.20 mm available |

PETG at E ≈ 2000 MPa throughout. Repeated-use strain allowance for PETG is roughly 1.5–2 %, so
every flexure has at least 1.5× margin.

The dovetail clearance, the latch geometry and the pin barb are all v2 values. What they replaced
and why is in [`v2-tolerance-analysis.md`](v2-tolerance-analysis.md) — the v1 pin could not be
inserted at any force, and the v1 latch could not be released at all.

### Button pins

Each unit's front power button is behind the plenum, so each gets a captive printed push-pin
running in a guided tube. Bore profile:

| Distance from mouth | Bore radius | Enclosed |
|---|---|---|
| −0.5 → 2.5 mm | 2.90 mm, with a 38° lead-in funnel | yes |
| 3.0 → 14.0 mm | 4.00 mm (detent chamber) | yes |
| 14.5 mm → end | 2.70 mm | yes |

The barb is **two pads on the outer face of each leg**, limited to |v| ≤ 0.80 mm and crowning at
r = 3.35 — not a revolved ring. That distinction is the whole point: squeezing the legs translates
each half toward the centreline, which retracts material lying along the squeeze axis and does
nothing to material 90° away. A ring cannot be squeezed through its own bore; two pads can.

With the legs fully closed the barb envelope measures 2.159 mm against a 2.90 mm mouth. Required
squeeze is 0.45 mm of the 1.20 mm available, and on a tight printer ≈0.73 mm of 1.10 mm.

Long pin: 20.5° off the button axis, 6.0 mm free stroke, presses at +2.50 mm.
Short pin: 28.7° off axis, 5.0 mm free stroke, presses at +2.25 mm.

## Holding the units still

Each unit is a 150 mm slab. Three constraints hold it:

| Constraint | Position | Where it bears |
|---|---|---|
| Inboard | x = 9.5 (tray centre wall) | z 6–30 |
| Outboard | x = 60.4 (arm shroud collar frame) | y 13.0–15.5 and 135.0–137.5, z 21.0–23.5 and 143.0–145.5 |
| Top corners | x = 60.4 (brace capture ribs) | z 152–158 |

```
left-right play = 60.4 - 9.5 - 50.5 = 0.40 mm
```

Before v2 the outboard face was unconstrained above z = 8 and the unit could slide the full gap
to the arm plate. The shroud collar does double duty here: it is primarily an air seal, and the
lateral datum falls out of it for free.

The collar also cut bypass around each fan discharge from 3 580 mm² to 143 mm², a 96 % reduction.
And it is the reason the arm no longer has a support-free print orientation — see below.

## Clearance for the unit's feet

The GX10 has four rubber feet on its bottom panel, which is the face that looks outward into the
side fans, so the feet land on the collar. The collar's top wall sits 18-20 mm in from the panel
edge while the bottom and side walls sit at 13-15 mm; the feet fall in that 5 mm band and foul
only the top.

The top wall is therefore cut away at both ends, leaving it over y 38.0–112.0 only, mirrored
about y = 75 so both arms clear at both ends. The reference model of the unit has no feet
modelled, which is why interference analysis never caught this.

**The foot dimensions were never measured.** The notch is sized from the collar geometry with
deliberate over-cut, since over-cutting costs nothing here and under-cutting leaves the part
fouling.

## Verification

**Interference.** Full-assembly interference analysis returns three pairs totalling 0.3074 cm³,
all of which are the intended 0.2 mm preload of each grille's four clamp pads against its fan.
No unintended contact anywhere. This figure is the baseline: anything else is a new bug.

**Assembly paths.** Every part stepped along its insertion path with a full interference check at
each step:

| Part | Motion | Result |
|---|---|---|
| Side fan arms ×2 | slide from the rear | clear 150 mm |
| Front plenum | drop −Z | clear 60 mm |
| Units ×2 | drop −Z | clear 60 mm |
| Fans ×3 | push into collar | clear 45 mm each |
| Top brace | drop −Z | clear to 5 mm, then the arm latches cam |
| Wedge key | thread +X | clear 32 mm |
| Grilles ×3 | clip on | clear to 15 mm, then the hooks ride and snap |
| Stacking pegs ×4 | press in | clear to home |

The arms slide in at step 2, before the units drop in at step 4, so the collar never has to sweep
past a seated unit.

**Printability.** Measured as unsupported reach, not overhang area. Eight parts are support-free
with a worst reach of 5.0 mm; the side fan arm and the front plenum both need support and no
orientation avoids it. Full measurements, the six-orientation sweep for the arm, and what the
earlier analysis got wrong are in
[`printability-analysis.md`](printability-analysis.md).

**Mesh quality.** Exported mesh volumes match the CAD solids to within 0.04 cm³ on every part.
**Eight of the ten meshes are watertight and 2-manifold. Two are not:**
`08-button-pin-long` has four edges shared by four faces and two shared by six;
`09-button-pin-short` has eight and eight. That is the coincident-face signature, and both pins
were heavily reworked in v2. Whether the B-reps are non-manifold or only the tessellation has not
been checked. Slicers will repair these silently and by their own rules, which is not what you
want on the one part that already failed once.

## Print plate grouping

The 3MF places every part in a 250 mm grid, one cell per intended plate:

| Plate | Contents |
|---|---|
| 1 | Base tray |
| 2 | Front plenum |
| 3 | Side fan arm (1 of 2) |
| 4 | Side fan arm (2 of 2) |
| 5 | Top brace + wedge key + 4 pegs + both button pins |
| 6–8 | Fan grille ×3, 25 mm variant |
| 9–11 | Fan grille ×3, 26 mm variant (alternate — print one set or the other) |

The grilles are 135 mm square, so only one fits a 248 × 250 mm bed at a time.

## Things that are still open

- **Nothing since v1 has been printed.** Everything above about v2 and later is CAD verification.
- The two non-manifold pin meshes.
- The centre duct's effectiveness is unproven — see the A/B test note above.
- Latch, hook and pin-leg stiffness are calculated, not measured.
- The arm and the plenum need support material. A design fix for the arm — sacrificial ribs or a
  chamfered transition behind the plate — has not been attempted.
- The rear exhaust attachment (routing exhaust to top, left or right while keeping port access)
  is designed for but not built. It must mount to the **top brace**, not the tray ears: nothing
  on the ears may exceed 17 mm in height or the arms cannot be fitted.
- Allow at least 95 mm behind the cage for the QSFP DAC bend radius; 120 mm is comfortable.

## Design rules learned the hard way

Four classes of bug in this project were invisible in the viewport and passed the checks that
were run against them:

1. **Feature order.** Joining material into a region that already has holes through it refills
   those holes. Re-cut any bore after a later join crosses it.
2. **Off-axis features.** Anything whose axis is not a global axis must be built on a
   construction plane perpendicular to *its own* axis. Lofting between global-axis planes
   produces oblique cylinders — elliptical in true section, with smeared shoulders that will not
   retain a snap feature.
3. **Reference geometry is not the real thing.** The unit's reference model has no rubber feet,
   so no amount of interference analysis was ever going to find the collar fouling them.
4. **A fix in one dimension can break another.** The shroud collar solved the air bypass and the
   lateral play at once, and silently removed the arm's only support-free print orientation.

And the general ones: **verify fits by sampling the solid, not by eye** — a missing tube wall that
left a snap pin completely unretained passed every interference check that was run against it.
**And re-measure any result that says a hard part is easy.** The claim that a 13 000 mm² plate
held up by two rails printed support-free stood for two releases.
