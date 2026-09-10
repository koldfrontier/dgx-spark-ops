# Printability: orientation and support requirements

Model v33. Every figure measured from the exported meshes, not estimated.

> **This document was rewritten on 2026-09-10.** The previous version concluded that no part
> needed support material. That conclusion does not survive re-measurement. Two of its rows were
> wrong, and one of its recommendations made a part worse. What changed and why is at the bottom.

## How this is measured

A bridge proxy — `2 × area / perimeter` on each downward-facing face — cannot tell a **bridge**
(anchored at both ends, prints fine) from a **cantilevered ledge** (anchored on one side, droops).
So the measurement is **unsupported reach** instead.

The part is ray-cast into vertical columns at 1.0 mm spacing and sliced at 0.5 mm. A cell is an
overhang if it has material with nothing directly beneath it and is not on the bed. For each such
cell, a distance transform gives the horizontal distance to the nearest column that *does* carry
material one layer down — the nearest anchor the extruded filament can reach.

```
reach r  =  distance to the nearest anchor
    bridge of span S    ->  midpoint reach = S/2
    cantilever length L ->  tip reach      = L
```

`r < 3 mm` is self-supporting in practice. `r > 10 mm` means either a 20 mm+ bridge or a 10 mm+
cantilever, past the 20 mm span limit this design set for itself.

Validated on a known case: the stacking peg reports ~0 mm² standing on its end, and ~120 mm² at
about 1 mm reach lying on its side, which is right for a plain cylinder.

## Results — all ten parts, as exported

| Part | Build direction | Overhang | r>5 mm | r>10 mm | Worst reach | Support |
|---|---|---|---|---|---|---|
| `01-base-tray` | floor down | 1 112 mm² | 0 | 0 | 1.0 mm | none |
| `02-front-plenum` | back plate down | 11 946 mm² | 2 540 | **997** | **19.0 mm** | **needed** |
| `03-side-fan-arm` | fan collar up | 14 978 mm² | 8 706 | **4 156** | **26.6 mm** | **needed** |
| `04-top-brace` | top face down | 1 494 mm² | 0 | 0 | 5.0 mm | none |
| `05-fan-grille-26mm` | grille face down | 60 mm² | 0 | 0 | 2.0 mm | none |
| `05b-fan-grille-25mm` | grille face down | 60 mm² | 0 | 0 | 2.0 mm | none |
| `06-wedge-key` | on its side | 0 mm² | 0 | 0 | 0.0 mm | none |
| `07-stacking-peg` | on end | 12 mm² | 0 | 0 | 1.0 mm | none |
| `08-button-pin-long` | widest face down | 152 mm² | 0 | 0 | 2.8 mm | none |
| `09-button-pin-short` | oblique | 14 mm² | 0 | 0 | 1.4 mm | none |

**Eight of ten are clean.** The two large parts are not, and no orientation fixes them.

## The arm has no support-free orientation

The arm is a flat plate roughly 166 × 172 mm and 3 mm thick, with the shroud collar standing
9.6 mm off one face and the rails and bosses standing about 27 mm off the other. The plate can
never sit on the bed: something is always underneath it.

What is underneath is not much. Probing the solid — for each point on the plate, is there any
material outboard of it?

```
rows = z 10..170, cols = y 0..150; P = plate with nothing behind it, R = rib behind, . = no plate
z= 10 .PPPPRRRRRRRRRRRRRRRRRRRRRPPPP.
z= 60 PPRPP.....................PPRPP
z= 90 PPRP.......................PRPP
z=120 PPRPPPP.................PPPPRPP
z=150 PPPPPP.P.PPPPPPPPPPPPP.P.PPPPPP
```

Two narrow rails and a band near z = 10-20. That is the entire support available to a 13 000 mm²
plate.

All six axis orientations, measured:

| Build direction | Overhang | r>5 mm | r>10 mm | Worst reach | Footprint × height |
|---|---|---|---|---|---|
| **fan collar up (as exported)** | 14 978 | 8 706 | 4 156 | 26.6 mm | 172 × 166 × 40 |
| fan collar down | 16 473 | 11 531 | 7 832 | 39.2 mm | 172 × 166 × 40 |
| on end, brace end up | 9 756 | 4 815 | 2 494 | 25.5 mm | 40 × 166 × 172 |
| on end, tray end up | 10 132 | 5 883 | 3 618 | 27.1 mm | 40 × 166 × 172 |
| on its side, front up | 10 277 | 6 520 | 3 992 | 42.0 mm | 172 × 40 × 166 |
| on its side, rear up | 10 275 | 6 521 | 3 989 | 41.0 mm | 172 × 40 × 166 |

Standing it on end is the least bad on area but it is a 172 mm tower on a 40 × 166 footprint and
it still needs support. **The files ship it fan-collar-up and it needs support there.** Tree
supports under the plate are enough; the plate itself is flat and 3 mm thick, so it takes support
cleanly and the underside is an internal face nobody sees.

In v1 there was no collar. The plate went straight on the bed, rails up, and the part genuinely
was support-free. **Adding the collar in v2 is what removed that option**, and the v2 analysis
did not catch it.

## The plenum has been re-oriented back

The v2 pass moved the plenum from back-plate-down to upright, on a prediction of 2 mm² beyond
10 mm reach. Measured, upright is far worse:

| Plenum orientation | Overhang | r>5 mm | r>10 mm | Worst reach | Footprint × height |
|---|---|---|---|---|---|
| **back plate down (as exported)** | 11 946 | 2 540 | **997** | **19.0 mm** | 139 × 180 × 66 |
| upright (v2, now reverted) | 17 387 | 9 347 | 6 706 | 40.1 mm | 139 × 66 × 180 |

Back-plate-down is a factor of 6.7 better on area beyond 10 mm reach and halves the worst reach,
and it is a 66 mm tall print instead of 180 mm. It still needs support under the front face.

## What the previous version got wrong

The old analysis is reproducible for **eight of the ten parts**, including its own calibration
case, so the method was right and the implementation was wrong somewhere that only bit the two
large parts. Its arm row reported 189 mm² beyond 5 mm reach where the same orientation measures
8 706; its plenum recommendation predicted 2 mm² beyond 10 mm where the delivered orientation
measures 6 706.

The lesson is the one already in `design-notes.md`, applied to the analysis instead of the model:
a number that says a hard part is easy deserves a second measurement. The arm is a 13 000 mm²
plate held up by two rails. No orientation was ever going to make that free.

## Summary

| Part | Change | Why |
|---|---|---|
| `02-front-plenum` | upright → **back plate down** | 6 706 mm² beyond 10 mm reach becomes 997 |
| `03-side-fan-arm` | unchanged orientation, **support now documented** | no orientation avoids it |
| everything else | unchanged | measures clean |

Worst unsupported reach on the eight support-free parts is **5.0 mm**, on the top brace.
