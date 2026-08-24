# Design notes

Engineering rationale, the numbers behind the snap features, and how the design was verified.
Everything here was measured against the solid model in Fusion; none of it has been printed yet.

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
| Arm → tray | 45° half-dovetail, slides in from the rear | 0.3 mm clearance, 150 mm travel, hard stop at the front |
| Arm → brace | Two cantilever latch barbs into catch pockets | 1.40 mm deflection, 0.66 % strain, 5.1 N each, ~15 N to seat |
| Grille → collar | Four cantilever hooks, 18 × 1.3 × 10 mm, 1.5 mm barb | 1.08 % strain, 2.8 N per hook, ~11 N to click on |
| Plenum → brace | Tusk tenon through a mortise, locked by a wedge key | 0.65 mm of taper available for tightening |
| Button pin → tube | Split shaft, two spring legs, three-section snap barb | 0.63 % strain, ~1.9 N to snap in, ~2.85 N pull-out |

PETG at E ≈ 2000 MPa throughout. Repeated-use strain allowance for PETG is roughly 1.5–2 %, so
every flexure has at least 1.5× margin.

### Button pins

Each unit's front power button is behind the plenum, so each gets a captive printed push-pin
running in a guided tube. Bore profile, measured by ray-sampling the solid at eight angles every
0.5 mm along the axis:

| Distance from mouth | Bore radius | Enclosed |
|---|---|---|
| −0.5 → 2.5 mm | 2.70 mm | yes |
| 3.0 → 14.0 mm | 4.00 mm (detent chamber) | yes |
| 14.5 mm → end | 2.70 mm | yes |

That gives a square 1.30 mm shoulder at s = 3.0. The pin's barb reaches r = 3.65, so it engages
0.95 mm per side and cannot be pulled back through the mouth without compressing both legs
0.95 mm — which the 2.2 mm slot allows, with 0.3 mm to spare before the halves touch.

Long pin: 20.5° off the button axis, 6.0 mm free stroke, presses at +2.50 mm.
Short pin: 28.7° off axis, 5.0 mm free stroke, presses at +2.25 mm.

Worst-case gravity on the long pin is 0.0055 N against 2.85 N of retention — a 520× margin.

## Verification

**Interference.** Full-assembly interference analysis returns three pairs totalling 0.3074 cm³,
all of which are the intended 0.2 mm preload of each grille's four clamp pads against its fan.
No unintended contact anywhere.

**Assembly paths.** Every part was stepped along its insertion path in 2 mm increments with a
full interference check at each step:

| Part | Motion | Result |
|---|---|---|
| Side fan arms ×2 | slide −Y from the rear | clear 150 mm |
| Front plenum | drop −Z | clear 60 mm |
| Units ×2 | drop −Z | clear 60 mm |
| Fans ×3 | push into collar | clear 45 mm each |
| Top brace | drop −Z | clear to 5 mm, then the arm latches cam |
| Wedge key | thread +X | clear 32 mm |
| Grilles ×3 | clip on | clear to 15 mm, then the hooks ride and snap |
| Stacking pegs ×4 | press in | clear to home |

**Printability.** Six-direction overhang sweep on every part, 45° threshold, using true outward
face normals. For each overhanging face the effective bridge span was computed as 2 × area ÷
perimeter:

| Part | Best direction | Overhang | Needs real support | Worst bridge |
|---|---|---|---|---|
| Base tray | floor down | 0 mm² | 0 | — |
| Front plenum | back plate down | 8983 mm² | 0 | 12.4 mm |
| Side fan arm | plate down | 394 mm² | 0 | 3.5 mm |
| Top brace | top face down | 1517 mm² | 0 | 10 mm |
| Fan grille | grille face down | 60 mm² | 0 | 1.3 mm |
| Wedge key, pegs, pins | — | 0–12 mm² | 0 | — |

No face anywhere exceeds a 20 mm span, so no part needs support material.

**Mesh quality.** All ten exported meshes are watertight and 2-manifold, and their computed
volumes match the CAD solids to 0.1 cm³.

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

- **Nothing has been printed.** All of the above is CAD verification.
- The centre duct's effectiveness is unproven — see the A/B test note above.
- Latch, hook and pin-leg stiffness are calculated, not measured.
- The rear exhaust attachment (routing exhaust to top, left or right while keeping port access)
  is designed for but not built. It must mount to the **top brace**, not the tray ears: nothing
  on the ears may exceed 17 mm in height or the arms cannot be fitted.
- Allow at least 95 mm behind the cage for the QSFP DAC bend radius; 120 mm is comfortable.

## Design rules learned the hard way

Two classes of bug in this model were invisible in the viewport and passed interference checks:

1. **Feature order.** Joining material into a region that already has holes through it refills
   those holes. Re-cut any bore after a later join crosses it.
2. **Off-axis features.** Anything whose axis is not a global axis must be built on a
   construction plane perpendicular to *its own* axis. Lofting between global-axis planes
   produces oblique cylinders — elliptical in true section, with smeared shoulders that will not
   retain a snap feature.

And the general one: **verify fits by sampling the solid, not by eye.** A missing tube wall that
left a snap pin completely unretained passed every interference check that was run against it.
