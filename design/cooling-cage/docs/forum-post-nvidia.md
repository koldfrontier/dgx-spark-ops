**Title:** DGX Spark Dual Cooler — screwless modular cage, three 120 mm fans (CAD + files, CC BY 4.0)

---

Two Sparks on a desk generate more heat than one desk wants to deal with, and the stock
orientation makes it worse: sat flat and side by side, each unit's intakes end up either facing
the other unit or facing the desk. I wanted them close enough to keep a QSFP stacking cable short
without one of them breathing the other's exhaust, so I designed an active cage around them and
have been printing and assembling it over the last stretch.

The short version: both units stand **on edge and mirrored** — one flipped end-for-end so both
filtered bottom panels face outward. That matters because the bottom panel is the single largest
intake either unit has, and standing them this way puts a fan directly on it. It also produces a
convenient coincidence: 50.5 + 19 + 50.5 mm of unit and gap is 120 mm, exactly one fan frame, so
the whole cage sizes itself off standard 120 mm hardware.

Three 120 mm fans, and each does something different:

- **Two side fans** blow inward through each unit's filtered bottom panel.
- **One front fan** pressurises a sealed plenum that feeds both front intake strips. Its Ø114
  throat opens into the plenum through a 45° diffuser chamfer rather than a straight step.
- Inside that plenum, a **hollow centre duct** takes air from two ram scoops placed at r = 38–58 mm
  from the fan axis — inside the blade annulus but clear of the Ø42 hub wake — and jets it down the
  19 mm gap between the units through two 3 × 112 mm slots.

That centre duct is the part I'm least certain about. Dead air between two hot inner panels was the
thing I most wanted to eliminate, but the duct is a calculated design, not a measured one. I sized
the scoops to sit in the working part of the blade sweep and left the exit slots deliberately
**tapeable** so an A/B test is trivial: tape them, rerun the same load, compare. If anyone runs
that test I'd genuinely like the numbers, mine or not.

Everything exhausts rearward, and the rear is kept deliberately clear — the port strip, the QSFP
DAC and its bend radius all stay accessible. Allow about 95 mm behind the cage for the cable, 120 mm
is comfortable. All three fan leads are channelled inside the cage and exit together through a
single gland at the back, outboard of the exhaust footprint and below the port strip, so nothing
sits in the hot stream. Every restriction on that route clears a 14 × 8 mm fan connector.

**There is not one screw, heat-set insert or drop of glue in it.** That was a hard constraint, not
a flourish. Anything requiring a hardware kit is something the next person has to source and
mis-order; dovetails, snap latches and one printed wedge key make it reproducible by anyone with a
printer and a spool. Ten unique parts, 15 printed pieces, roughly 580 g of PETG at 20 % infill.
Largest part is 176 × 220 mm, so a 248 × 250 mm bed (P1S and similar) covers it.

On supports: eight of the ten parts print with nothing, worst unsupported reach 5 mm. The side fan
arm and the front plenum both need it. The arm is a 166 × 172 mm plate 3 mm thick with a fan shroud
collar on one face and rails on the other, so the plate cannot touch the bed in any orientation —
I measured all six and the best of them still leaves 2 500 mm² beyond 10 mm of unsupported reach.
Tree supports under the plate handle it and the underside is an internal face. I mention it because
an earlier version of these files claimed no part needed support, which was wrong, and I'd rather
say so than have someone find out on the bed.

PETG specifically, because every latch, hook and pin leg is a printed spring and the strain figures
assume E ≈ 2000 MPa. The flexures run 0.63–1.08 % strain against PETG's ~1.5–2 % repeated-use
allowance, so there's at least 1.5× margin on each. Four perimeters minimum — thin walls halve the
strength of every snap feature in the design.

One consequence of mirroring worth mentioning: the two power buttons end up at opposite ends of the
front face, and both are behind the plenum. Each gets a captive printed push-pin running in a guided
tube, retained by a snap barb so it can't fall out.

One more thing worth flagging for anyone with a GX10 specifically: the four rubber feet on the
bottom panel land on the fan shroud collar, because that panel is the face pointing out into the
side fan. The collar's top wall is notched at both ends to clear them. My reference model of the
unit has no feet on it, so no amount of interference checking was going to find that — it turned
up on the bench.

Files are up — Fusion source, STEP, print-oriented STLs, a 3MF, and a 10-page illustrated assembly
guide, under CC BY 4.0:

**https://github.com/koldfrontier/dgx-spark-ops** → `design/cooling-cage/`

Fan hardware is nothing exotic: any standard 120 × 120 fan with a 105 mm hole pitch fits. I've used
Thermalright TL-C12C (25 mm) and NZXT F120 (26 mm) — there are two grille variants, one per
thickness, and you print whichever matches, since the clamp pads preload the fan against its sealing
land. A cheap AC→DC voltage controller with a 4-port splitter runs all three.

Still open, and where I'd welcome input: the centre duct's real contribution, latch and hook
stiffness in practice versus calculated, whether the arm can be reshaped to print support-free
again, and a rear exhaust attachment to route the outflow up or sideways while keeping port access
— designed for, not yet built. If you print it, please open an issue with what you find.
