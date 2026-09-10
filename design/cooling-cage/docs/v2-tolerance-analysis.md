# v2 tolerance analysis and change set

All figures below were measured by ray-sampling the solids in Fusion (model v24), not
read off the drawing. Sampling step 0.05 mm on radii, 0.25–0.5 mm on maps.

---

## 1. Button pin cannot be inserted

> **Corrected.** An earlier version of this document blamed print tolerances. That was wrong.
> Your remark that the dovetail prints *loose* is inconsistent with a tight-printer stack, so I
> went back and tested the geometry directly. The pin cannot be inserted on **any** printer at
> **any** squeeze force. It is a geometric impossibility, not a fit problem.

### Measured, as built

| Feature | Value |
|---|---|
| Bore mouth land radius | **2.70 mm**, s = −1.0 → 3.0 |
| Detent chamber radius | 4.00 mm, s = 3.5 → 13.5 |
| Pin shaft radius | 2.45 mm |
| Barb peak radius | **3.65 mm** at s = 4.5 |
| Barb lead-in ramp | 16.7° |
| Leg slot width | 2.25 mm (half-width 1.125) |
| Leg cantilever length | 17.0 mm |

### Why it cannot work

The barb is a **full revolved ring** of radius 3.65, split by the slot. Squeezing the legs
translates each half toward the centreline — which retracts only the material lying *along*
the squeeze axis. The material 90° away, out near the slot at v ≈ ±3.5, does not move inward
at all; it just slides sideways.

I sampled the barb section (10 700 points) and recomputed its envelope for every squeeze
value up to fully closed:

| Squeeze per side | Barb max radius | Passes the 2.70 bore? |
|---|---|---|
| 0.00 mm | 3.669 | no |
| 0.40 mm | 3.569 | no |
| 0.80 mm | 3.513 | no |
| **1.125 mm (legs touching)** | **3.500** | **no** |

> With the slot **completely shut**, the barb still measures **3.50 mm** where it needs
> 2.70 mm. It is **0.80 mm too big and cannot be made smaller by pressing.** That is exactly
> what you felt: a hard stop that does not respond to force.

The 0.175 mm/side "margin" quoted in the v1 design notes was computed on the u-axis only,
where the barb *does* retract. It never checked the rest of the ring.

### Fix

The barb must project **only in the direction the legs flex**. Replace the revolved ring with
two discrete pads on the outer face of each leg, narrow in v, so that squeezing actually
shrinks the envelope.

| Parameter | v1 | **v2** |
|---|---|---|
| Barb form | revolved ring, 360° | **two pads, ±0.8 mm half-width in v** |
| Barb peak radius | 3.65 | **3.45** |
| Bore mouth land radius | 2.70 | **2.90** |
| Leg slot width | 2.25 | **2.60** |
| Pin shaft radius | 2.45 | **2.60** |
| Mouth lead-in chamfer | none | **0.8 mm × 30°** |

The governing point is now the pad's corner at v = 0.8, not its crown. Required squeeze is
`sqrt(R²−w²) − sqrt(M²−w²)`:

| Printer | Required squeeze | Available | Margin |
|---|---|---|---|
| Nominal | 0.57 mm | 1.30 mm | **0.73 mm** |
| Tight (holes −0.2, posts +0.08) | 0.87 mm | 1.20 mm | **0.33 mm** |
| Loose (holes +0.2, posts −0.08) | 0.28 mm | 1.40 mm | 1.12 mm |

Retention holds across the whole range — worst case 0.27 mm/side of engagement against a
0.016 N gravity load. Strain 0.59 %, insertion ≈ 7 N.

Because the fix works at both ends of the tolerance range, **you do not need to measure
anything.** That was the open question at the end of the v1 document; it is now closed.

---

## 2. Arm latch cannot be released

### Measured, as built

| Feature | Value |
|---|---|
| Arm plate face | x = 73.00 |
| Barb peak | **x = 74.80 at z = 166.00** → protrusion **1.80 mm** |
| Barb ramp | z 172.0 → 166.0, 16.7° |
| Retaining shoulder | z = 165.9 (square drop back to x = 73.00) |
| Tongue slots | y 28.4–29.7 and 38.4–39.7, 1.4 mm wide |
| Tongue | 8.7 mm wide × 3.0 mm thick, root z = 143.5, free end z = 174 |
| Barb distance from root | 22.5 mm |
| **Release window in brace** | **y 31.5–36.75 (5.25), z 167.5–171.5 (4.25), x 75.5–78** |

### Why you can't unlock it

The window exists — but it is aimed at empty air.

> The window spans **z 167.5 → 171.5**. The barb peak is at **z 166.0** and its retaining
> shoulder at **z 165.9**. The bottom edge of the window sits **1.5 mm above the part of the
> barb that has to move.**

Inside the window you can only touch the shallow top of the ramp, where the barb stands
1.35 mm proud instead of 1.80 mm, on a 16.7° slope that cams a flat tool up and out.

Even with a perfect tool, the numbers are bad. Tongue `I = 8.7 × 3.0³/12 = 19.58 mm⁴`.
Pushing at z = 169.5 to move z = 166 by 1.80 mm needs

```
F = 1.80 / 0.11958 = 15.1 N per latch      (2.26 mm of travel at the tool)
```

That is **15 N on each of two latches simultaneously**, while a third hand lifts the brace —
at **1.50 % root strain**, which is the top of PETG's repeated-use allowance. Even if you
could reach it, teardown would craze the tongue roots.

### Fix

Four changes, all on parts you already need to reprint:

| Change | v1 | **v2** |
|---|---|---|
| Window z-span | 167.5–171.5 | **163.5–169.5** (now centred on the barb peak) |
| Window y-span | 31.5–36.75 | **30.5–37.5** (7 mm — fits a 6 mm blade) |
| Barb protrusion | 1.80 | **1.30** |
| Tongue thickness | 3.0 | **2.4** (recess inner face to x = 70.6) |
| Barb top face | 16.7° ramp throughout | **flat push pad, normal to x, z 165.5–167.5** |

Result: **6.6 N per latch, 0.91 % strain**, pushing square on a flat pad you can actually see
and reach. Retention is still ~4× what the joint needs.

---

## 3. Air bypasses around the units

### Measured

Sampling from the DGX side face (x = 60) outward at seven points across the fan opening
found **no arm material at all before x = 70** at six of them.

> The gap between each unit's side panel and the arm plate is **10.0 mm, open on all four
> sides**, across the entire fan discharge.

| | Area |
|---|---|
| Fan bore Ø114 | 10 207 mm² |
| Free bypass path (π × 114 × 10 mm) | **3 580 mm²** |

The bypass path has essentially zero resistance; the intended path goes through the unit's
filtered panel. Air takes the easy route — which is what you are seeing.

### Fix

A **shroud collar on the arm's inner face**, turning the 10 mm open span into a duct:

- Square collar around the Ø114 bore, **124 × 124 mm outer, 2 mm wall**
- Extends from the arm plate at **x = 70 to x = 60.5** (9.5 mm), leaving **0.5 mm** running
  clearance to the unit
- Bypass area drops from 3 580 mm² to **179 mm² — a 95 % reduction**
- Adds ≈ 9.4 cm³ per arm

This is safe for assembly because the arms slide in at step 2, **before** the units drop in at
step 4 — the collar never has to sweep past a unit that is already seated. Printability is
unaffected: the collar walls run parallel to the build direction, no new overhangs.

---

## 4. Units wiggle in the enclosure

### Measured

Tray section at y = 75, tracing what actually touches a unit:

| Side | Support |
|---|---|
| Underneath | rails at z = 8 (the unit's bottom face) |
| Inboard (centre wall) | z = 6 → **30** — 22 mm of a 150 mm-tall unit |
| **Outboard** | z = 6 → **8** — **2 mm** |

Above z = 30 there is nothing on either side. Each unit is a 150 mm slab standing in a 22 mm
socket, open on the outboard face.

> Slop at the top of the centre wall is amplified to the top of the unit by
> `(158 − 8) / (30 − 8) = ` **6.8×**. Half a millimetre of fit clearance becomes **3.4 mm of
> sway** at the top; a millimetre becomes 6.8 mm.

### Fix — two parts, both needed

**A. Capture ribs on the brace underside.** The brace already spans z 150–180 and the units
top out at z = 158, so there is 8 mm of overlap doing nothing. Add ribs forming a **51.5 mm
slot (0.5 mm clearance per side), 6 mm deep, at z 152–158**, straddling each unit's top edge.
This kills the lever arm at the end where all the movement is.

**B. Sprung pads on the arm collar.** Two per arm, at **z = 45 and z = 135**, cantilever
12 × 8 × 1.6 mm with **0.6 mm interference**, pressing the unit inboard against the centre
wall. `F = 5.7 N` each — enough preload to take up clearance without needing a tight fit.

Together these constrain the unit at the bottom (existing rails), the middle (pads) and the
top (ribs), with no screws and no change to the drop-in assembly order.

---

## 5. Dovetail is too loose

You reported the arm-to-tray slide as very loose. The design clearance is **0.30 mm**, which is
generous for a dovetail even on a perfect machine — a 110 mm tongue with 0.3 mm of play will
always rattle. This is a design value, not a printing artefact.

| Parameter | v1 | **v2** |
|---|---|---|
| Dovetail sliding clearance | 0.30 mm | **0.15 mm** |

0.15 mm still slides freely in PETG over 150 mm of travel but takes out most of the play. If
it ends up stiff on your machine, opening it back to 0.20 mm is a one-parameter change.

This is also the only calibration datum available, and it is worth stating what it does and
does not tell us: a loose dovetail rules out a printer running *tight*, which is what sent me
back to re-check §1. It does not pin down the exact offset, which is why the §1 fix above is
sized to work across the full tolerance range rather than at one assumed value.

---

# Verification — all five changes applied and measured

Model saved as **v25**. Every number below was re-measured from the modified solids, not
predicted.

## 1. Pin insertion — was impossible, now passes

The barb is now two pads limited to **|v| ≤ 0.80 mm**, crown **r = 3.35** with a flat land over
s 4.5–5.5, lead-in ramp unchanged at 16.7°. Bore mouth opened to **r = 2.90** with a 38° funnel.

Re-running the same squeeze simulation that condemned the old design:

| | v1 | **v2** |
|---|---|---|
| Barb radius, legs fully closed | 3.500 mm | **2.159 mm** |
| Mouth radius | 2.70 mm | **2.90 mm** |
| Squeeze needed to clear | impossible | **0.45 mm** |
| Squeeze available | 1.125 mm | **1.20 mm** |
| Margin | −0.80 mm (hard stop) | **+0.75 mm** |

Engagement at rest is 0.45 mm per side against a 0.016 N load. On a tight printer the required
squeeze rises to ≈0.73 mm against 1.10 mm available — still passes.

## 2. Latch release — was unreachable, now a flat pad in the open

| | v1 | **v2** |
|---|---|---|
| Barb protrusion | 1.80 mm | **1.30 mm** |
| Contact surface | 16.7° ramp (cams tool out) | **flat pad, z 166.0–167.5, normal to x** |
| Window z-span | 167.5–171.5 (above the barb) | **163.5–171.5** |
| Window y-span | 5.25 mm | **7.0 mm** |
| Tongue thickness | 3.0 mm | **2.4 mm** |
| Straight-line access to pad | none | **clear, z 166.25–171.75** |
| Release force | 15.1 N per latch | **4.6 N per latch** |
| Root strain at release | 1.50 % (at PETG limit) | **0.63 %** |
| Retention engagement | 1.30 mm | **0.90 mm** |

Cutting the window initially removed the catch lip — engagement went to zero. Caught it on the
verification scan and restored the lip; it now measures 0.90 mm on all four latches.

## 3. Bypass — shroud collar fitted

124 × 124 mm square collar, 2 mm wall, from the arm plate at x = 70 out to **x = 60.4**,
leaving 0.4 mm running clearance to the unit.

| | v1 | **v2** |
|---|---|---|
| Bypass area | 3 580 mm² | **143 mm²** |
| Reduction | — | **96 %** |
| Arm volume | 115.5 cm³ | 124.9 cm³ |

## 4. Unit retention — corrected after your feedback

My first pass assumed the units were **rocking** about their base, which is why I raised the
tray centre walls from z 30 to z 52 — tall inboard support shortens the lever arm. You corrected
that: the units slide **left to right**, and rib height is irrelevant.

That changes the answer. A rigid box resting on flat rails translates sideways; it does not need
tall support to be stopped, only a positive stop at any height. The added rib height bought
nothing and cost duct flow, so it is **removed** — the centre walls are back to z = 30 and the
centre channel is full 19 mm again over its whole height.

What actually stops the sideways motion is the shroud collar from §3, which turned out to do
double duty:

| Constraint | Position | Where it bears |
|---|---|---|
| Outboard | **x = 60.4** (collar frame) | rectangular frame on the unit's side panel: y 13.0–15.5 and 135.0–137.5, z 21.0–23.5 and 143.0–145.5 |
| Inboard | **x = 9.5** (tray centre wall) | z 6–30 |
| Top corners | x = 60.4 (brace ribs) | z 152–158 |

```
left-right play = 60.4 - 9.5 - 50.5 = 0.40 mm
```

Before v2 the outboard face was unconstrained above z = 8, so the unit could slide the full
gap to the arm plate. **0.40 mm** is what remains, set by the collar's running clearance.

If 0.40 mm still reads as loose in the hand, the lever is that clearance and nothing else —
taking the collar to x = 60.25 halves it. I left it at 0.40 because the unit has to drop 150 mm
past that frame during assembly and a tighter running fit risks scraping.

## 5. Dovetail — tightened

| Flank | v1 | **v2** |
|---|---|---|
| Inboard vertical | 0.30 mm | **0.12 mm** |
| 45° dovetail face | 0.28 mm normal | **0.12 mm normal** |

## Whole-assembly checks

| Check | Result |
|---|---|
| Interference, 20 occurrences | **3 pairs, 0.3074 cm³** — identical to baseline, all intended grille preload |
| Arm 1 slide −Y | clear over 150 mm |
| Arm 2 slide +Y | clear over 150 mm |
| Plenum drop | clear over 60 mm |
| Both units drop | clear over 60 mm |
| Top brace drop | clear over 40 mm |
| Printability, 6-direction sweep | every part support-free; **worst bridge 10.87 mm** (was 12.8) |

No new interference anywhere, and no assembly path regressed.

## Still outstanding

- **Print files regenerated.** As of model **v33** the STLs, the 3MF, the STEP and the f3d in
  `print/` and `cad/` are all exported from the current solids. The STEP was additionally found
  to have been incomplete in every previous release — Fusion's STEP export only writes visible
  occurrences, and only three or four of the ten parts happened to be switched on. It now carries
  all ten.
- The centre duct is back to a full 19 mm channel over its whole height — the ribs that would
  have narrowed it are gone, so the tape A/B test is unaffected by v2.

## What v2 did not catch

Two faults survived this analysis and were found later. Both are documented elsewhere; they are
listed here because they belong to the v2 change set.

**The shroud collar fouls the unit's rubber feet.** The GX10 has four feet on its bottom panel,
which is the face that looks outward into the side fans. The reference model has no feet, so
interference analysis could not see it. The collar's top wall now stops short at both ends,
leaving material only over y 38.0-112.0. See the README and `design-notes.md`.

**The shroud collar removed the arm's support-free print orientation.** In v1 the arm plate went
straight onto the bed with its rails pointing up. The collar put 9.6 mm of structure on the other
face, so the plate can no longer touch the bed in any orientation, and it is a 13 000 mm² panel
carried by two narrow rails. The v2 printability pass reported this as 25 mm² beyond 10 mm reach;
re-measured it is 4 156 mm². The same pass moved the plenum onto a worse orientation on a
prediction that also did not hold. Both are re-measured in `printability-analysis.md`; the plenum
has been re-exported and the arm now ships with support documented.

The pattern in both is the same one §1 of this document was written about: a number that made a
hard problem look easy, taken at face value.
