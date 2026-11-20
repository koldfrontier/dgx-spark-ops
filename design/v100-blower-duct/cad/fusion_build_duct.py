# Fusion 360 build script: straight V100 blower duct (v6).
# Run through the Fusion MCP "script" feature (or Scripts & Add-Ins). It clears the active design and rebuilds it.
#
# Card-end geometry comes from NVIDIA PB-08744-001_v05 Figure 4 (end view, to scale), measured in the embedded
# raster: scale 6.47 px/mm, cross-checked three ways (Fig. 3 shroud height 97 mm at 2.942 px/mm from the 111.15 /
# 266.70 dimensions; bracket slot-tab pitch 20.32 mm). Expect +-0.5 mm on these positions.
# Fan outlet values are ESTIMATES (no Sunon drawing exists): a reference AliExpress kit gives 119 mm from the card
# end to the far edge of the fan; the outlet spans most of the card height (owner's photos).
#
# Coordinates: u = across the card thickness, 0 at the shroud cover face, increasing toward the PCB;
#              v = down the card height, 0 at the shroud top edge.
# Model: X = u, Y = -v (so looking from the fan toward the card you see Figure 4 as drawn), Z = 0 at the card end
#        face, increasing toward the fan.
import adsk.core, adsk.fusion

C = {
    # card end (Figure 4)
    'shroud_u': 36.0, 'shroud_v': 96.6,                         # end-face envelope
    'fin_u0': 4.5, 'fin_u1': 28.1, 'fin_v0': 3.2, 'fin_v1': 93.4,  # fin-stack opening
    # holes and 8-pin pocket: from the proven Printables 1839179 funnel (see NOSE_OUT note), aligned by its holes
    'hole_u': 31.0, 'hole_v': (52.60, 70.36, 88.19),            # 3 tapped M3 holes, pitch 17.8
    'plug_u0': 23.59, 'plug_v0': 19.42, 'plug_v1': 39.42, 'plug_z': 28.0,  # connector (Fig. 4) v 19.1-38.6
    # fan outlet, caliper photos: flared mouth 30 x 108, flare 4 deep, housing 25 thick.
    # Mouth inner opening is an estimate (wall ~1.5-2): 22 x 104.
    'flare_u': 30.0, 'flare_v': 108.0, 'flare_d': 4.0, 'body_u': 25.0,
    'mouth_u': 22.0, 'mouth_v': 104.0,
    'rib_h': 13.15, 'rib_d': 5.5, 'slot_h': 8.0,     # side ribs 26.3 wide from ~5.7 deep; slot block depth
    'fan_cu': 17.1, 'fan_cv': 48.3,      # fan centre: on the fin centre, nudged so the slot stays inside u >= 0
    'fit': 0.3, 'lip_t': 2.0,
    # nose that slides into the shroud end (5-6 mm); reference nose is 6.0 deep
    'nose_d': 6.0,
    # part
    # Length budget (target: no longer than the AliExpress kit, 119 mm from the card end to the fan's far edge;
    # the fan is ~100 mm from its rim to its far edge) -> rim at <= ~19 mm from the card end face.
    # Here: flange 3 + transition 17 + floor 1.8 = rim at 21.8 mm (+5 mm after the first fit: the 12 mm
    # transition left the 8-pin cables too tight).
    'flange_t': 3.0, 'duct_len': 17.0, 'wall': 1.8,
    # cable relief around the 8-pin plug: channel widened in v on both sides, and a 45 deg chamfer on the
    # slot block's outer underside edge above the channel so the cables bend over a ramp, not a square corner
    'plug_dv': 2.0,
    'hole_d': 4.0, 'pocket_d': 5.8, 'skin': 0.8,
}

# Card-side geometry copied from the proven funnel, Printables 1839179
# (2026-08-20-nvidia-tesla-p40-fan-no-controller.stl), sliced and aligned to (u, v) by its three holes
# (hole 1 -> u 31.0, v 52.6). Our Fig. 4 estimate had the nose 3.7 mm too wide on the cover side.
NOSE_OUT = [(9.17, 5.20), (8.50, 6.63), (6.59, 16.86), (6.64, 81.03), (8.88, 91.12), (9.60, 92.36), (11.08, 93.08),
            (24.09, 93.08), (28.59, 89.74), (28.59, 39.42), (23.59, 39.42), (23.59, 19.42), (28.59, 19.42),
            (28.59, 8.35), (23.59, 4.20), (10.42, 4.20)]
NOSE_IN = [(11.12, 6.20), (23.05, 6.14), (26.62, 9.41), (26.59, 17.42), (21.59, 17.42), (21.59, 41.41),
           (26.59, 41.42), (26.59, 88.69), (23.54, 91.20), (11.58, 91.11), (11.00, 90.79), (8.61, 80.54),
           (8.58, 17.04), (10.26, 7.67)]
FLANGE = [(6.21, 2.88), (5.01, 5.52), (2.97, 16.54), (3.01, 81.43), (5.44, 92.47), (7.01, 95.15), (10.23, 96.74),
          (25.50, 96.54), (30.03, 93.08), (35.46, 92.81), (36.19, 92.08), (36.46, 90.79), (36.46, 41.42),
          (36.19, 40.42), (35.46, 39.68), (34.46, 39.42), (23.59, 39.42), (23.59, 19.42), (31.82, 19.22),
          (32.12, 16.44), (31.86, 6.46), (24.90, 0.57), (9.15, 0.57)]


# Fan mouth profile (half-width in mm vs depth behind the rim), from a cut-out end-profile photo
# (silhouette at 18.8 px/mm, rim = 30 mm): a curved bell, not a square lip.
FLARE = [(0.0, 15.0), (0.6, 14.85), (1.1, 14.3), (1.5, 13.9), (1.9, 13.6), (2.3, 13.25), (2.6, 13.15),
         (3.6, 12.7), (4.7, 12.55)]


PRINT_POSE = True   # end the timeline with a move into the print orientation


def cm(v):
    return v / 10.0


def run(_context: str):
    app = adsk.core.Application.get()
    design = adsk.fusion.Design.cast(app.activeProduct)
    tl = design.timeline
    if tl.count:
        tl.moveToBeginning()
        tl.deleteAllAfterMarker()
    for i in range(design.userParameters.count - 1, -1, -1):
        design.userParameters.item(i).deleteMe()
    root = design.rootComponent
    feats = root.features
    NEW = adsk.fusion.FeatureOperations.NewBodyFeatureOperation

    def plane(z):
        if z == 0:
            return root.xYConstructionPlane
        pi = root.constructionPlanes.createInput()
        pi.setByOffset(root.xYConstructionPlane, adsk.core.ValueInput.createByReal(cm(z)))
        p = root.constructionPlanes.add(pi)
        p.isLightBulbOn = False
        return p

    def sk_rect(z, u0, u1, v0, v1):
        sk = root.sketches.add(plane(z))
        a = sk.modelToSketchSpace(adsk.core.Point3D.create(cm(u0), cm(-v1), cm(z)))
        b = sk.modelToSketchSpace(adsk.core.Point3D.create(cm(u1), cm(-v0), cm(z)))
        sk.sketchCurves.sketchLines.addTwoPointRectangle(a, b)
        sk.isVisible = False
        return sk

    def sk_circle(z, u, v, d):
        sk = root.sketches.add(plane(z))
        c = sk.modelToSketchSpace(adsk.core.Point3D.create(cm(u), cm(-v), cm(z)))
        sk.sketchCurves.sketchCircles.addByCenterRadius(c, cm(d / 2))
        sk.isVisible = False
        return sk

    def sk_poly(z, pts):
        sk = root.sketches.add(plane(z))
        p3 = [sk.modelToSketchSpace(adsk.core.Point3D.create(cm(u), cm(-v), cm(z))) for u, v in pts]
        lines = sk.sketchCurves.sketchLines
        first = prev = lines.addByTwoPoints(p3[0], p3[1])
        for p in p3[2:]:
            prev = lines.addByTwoPoints(prev.endSketchPoint, p)
        lines.addByTwoPoints(prev.endSketchPoint, first.startSketchPoint)
        sk.isVisible = False
        return sk

    def prism_uz(name, pts, v0, v1):
        # polygon in the (u, z) section, extruded along v from v0 to v1
        sk = root.sketches.add(root.xZConstructionPlane)
        p3 = [sk.modelToSketchSpace(adsk.core.Point3D.create(cm(u), 0, cm(z))) for u, z in pts]
        lines = sk.sketchCurves.sketchLines
        first = prev = lines.addByTwoPoints(p3[0], p3[1])
        for p in p3[2:]:
            prev = lines.addByTwoPoints(prev.endSketchPoint, p)
        lines.addByTwoPoints(prev.endSketchPoint, first.startSketchPoint)
        sk.isVisible = False
        ei = feats.extrudeFeatures.createInput(sk.profiles.item(0), NEW)
        ei.setSymmetricExtent(adsk.core.ValueInput.createByReal(cm(400)), True)
        b = feats.extrudeFeatures.add(ei).bodies.item(0)
        b.name = name
        us = [p[0] for p in pts]
        zs = [p[1] for p in pts]
        lim = box(name + ' limit', min(us) - 1, max(us) + 1, v0, v1, min(zs) - 1, max(zs) + 1)
        oc = adsk.core.ObjectCollection.create()
        oc.add(lim)
        ci = feats.combineFeatures.createInput(b, oc)
        ci.operation = adsk.fusion.FeatureOperations.IntersectFeatureOperation
        feats.combineFeatures.add(ci)
        return b

    def extrude(sk, z0, z1, name):
        e = feats.extrudeFeatures.addSimple(sk.profiles.item(0), adsk.core.ValueInput.createByReal(cm(z1 - z0)), NEW)
        b = e.bodies.item(0)
        b.name = name
        return b

    def box(name, u0, u1, v0, v1, z0, z1):
        return extrude(sk_rect(z0, u0, u1, v0, v1), z0, z1, name)

    def cyl(name, u, v, d, z0, z1):
        return extrude(sk_circle(z0, u, v, d), z0, z1, name)

    def loft(name, r0, z0, r1, z1):
        li = feats.loftFeatures.createInput(NEW)
        li.loftSections.add(sk_rect(z0, *r0).profiles.item(0))
        li.loftSections.add(sk_rect(z1, *r1).profiles.item(0))
        li.isSolid = True
        b = feats.loftFeatures.add(li).bodies.item(0)
        b.name = name
        return b

    def combine(target, tools, op):
        oc = adsk.core.ObjectCollection.create()
        for t in tools:
            oc.add(t)
        ci = feats.combineFeatures.createInput(target, oc)
        ci.operation = op
        ci.isKeepToolBodies = False
        feats.combineFeatures.add(ci)
        return target

    JOIN = adsk.fusion.FeatureOperations.JoinFeatureOperation
    CUT = adsk.fusion.FeatureOperations.CutFeatureOperation

    w, t, L, fit = C['wall'], C['flange_t'], C['duct_len'], C['fit']
    zf = t + L                      # fan mouth plane
    inner = NOSE_IN
    # transition starts from the bounding box of the nose airway (the plug keep-out trims its notch corner)
    fin = (min(p[0] for p in inner), max(p[0] for p in inner), min(p[1] for p in inner), max(p[1] for p in inner))
    cu, cv = C['fan_cu'], C['fan_cv']

    def centred(du, dv):
        return (cu - du / 2, cu + du / 2, cv - dv / 2, cv + dv / 2)

    def grow(r, d):
        return (r[0] - d, r[1] + d, r[2] - d, r[3] + d)

    mouth = centred(C['mouth_u'], C['mouth_v'])
    groove = grow(centred(C['flare_u'], C['flare_v']), fit)          # the flare slides in here
    slot_u = (cu - C['body_u'] / 2 - fit, cu + C['body_u'] / 2 + fit)  # opening between the retaining lips
    zg = zf + w                     # floor between the transition and the groove; the fan rim seats on it
    zt = zg + C['slot_h']           # top of the slide-in block
    neck = FLARE[-1][0]             # narrowest point of the slot (dovetail retention)
    gd = neck

    # solid envelope: flange + transition shell + T-slot block. The fan slides in along +v from the card-top end
    # (v < 0, open) and stops against the end wall at the far end.
    body = extrude(sk_poly(0, FLANGE), 0, t, 'duct')
    shell = loft('shell', grow(fin, w), t, grow(mouth, w), zf)
    blk = box('slot block', groove[0] - w, groove[1] + w, groove[2], groove[3] + w, zf, zt)
    nd = C['nose_d']
    nose = extrude(sk_poly(-nd, NOSE_OUT), -nd, 0.01, 'nose')
    combine(body, [shell, blk, nose], JOIN)

    # airway: nose + flange follow the nose outline, then the lofted transition to the fan mouth
    air = extrude(sk_poly(-nd - 1, inner), -nd - 1, t, 'air')
    air_n = box('air flange', *fin, t - 0.01, t + 0.01)
    combine(air, [air_n], JOIN)
    air_t = loft('air transition', fin, t, mouth, zf)
    air_f = box('air floor', *mouth, zf - 0.01, zg + 0.01)
    combine(air, [air_t, air_f], JOIN)
    # NB: between the nose outline and the transition's start rectangle there is a small ledge at the chamfers
    # and the plug-side step; the plug keep-out below trims the step region of the transition.

    # keep-outs: 8-pin plug corner, screw-driver pockets above the 3 holes. The airway is shrunk around each
    # keep-out by 'skin' (pockets) or 'wall' (plug) so a wall remains between them and the air.
    pz = min(C['plug_z'], t + L)    # plug channel runs the whole (short) transition
    pv0, pv1 = C['plug_v0'] - C['plug_dv'], C['plug_v1'] + C['plug_dv']
    plug_g = box('plug grow', C['plug_u0'] - w, 80, pv0 - w, pv1 + w, 0, pz + w)
    pock_g = [cyl('pocket grow %d' % i, C['hole_u'], v, C['pocket_d'] + 2 * C['skin'], t, zf)
              for i, v in enumerate(C['hole_v'])]
    combine(air, [plug_g] + pock_g, CUT)

    # T-slot: flare groove (open at the v < 0 end), lip opening for the 25 mm housing, and the far end wall kept
    # only at groove depth so the peg on the fan's end face clears it.
    # slot section = fan mouth profile + fit: bell flare, neck at 4.7 deep, rib relief above
    right = [(cu + h + fit, zg + d) for d, h in FLARE]
    right += [(cu + FLARE[-1][1] + fit, zg + C['rib_d']), (cu + C['rib_h'] + fit, zg + C['rib_d']),
              (cu + C['rib_h'] + fit, zt + 1)]
    left = [(2 * cu - u, z) for u, z in reversed(right)]
    grv = prism_uz('groove', right + left, groove[2] - 20, groove[3])
    lips = None
    peg = box('peg clearance', groove[0], groove[1], groove[3] - 0.01, groove[3] + w + 1, zg + gd, zt + 1)

    plug = box('plug', C['plug_u0'], 80, pv0, pv1, 0, pz)
    # 45 deg ramp from the groove's outer edge at the fan floor plane, outward and up; it stays outside the groove
    g1 = groove[1]
    ramp = prism_uz('cable ramp', [(g1, pz - 0.01), (g1 + 40, pz - 0.01), (g1 + 40, pz + 40)], pv0, pv1)
    pock = [cyl('pocket %d' % i, C['hole_u'], v, C['pocket_d'], t, zt + 1) for i, v in enumerate(C['hole_v'])]
    holes = [cyl('hole %d' % i, C['hole_u'], v, C['hole_d'], -1, t + 0.5) for i, v in enumerate(C['hole_v'])]
    combine(body, [air, grv, peg, plug, ramp] + pock + holes, CUT)

    for k, v in C.items():
        if isinstance(v, tuple):
            continue
        design.userParameters.add(k, adsk.core.ValueInput.createByString('%s mm' % v), 'mm', 'fusion_build_duct.py C[]')

    if root.bRepBodies.count != 1:
        raise Exception('expected 1 body, got %d' % root.bRepBodies.count)
    bb = body.boundingBox
    print('design bbox mm: u %.1f..%.1f  v %.1f..%.1f  z %.1f..%.1f' % (
        bb.minPoint.x * 10, bb.maxPoint.x * 10, -bb.maxPoint.y * 10, -bb.minPoint.y * 10,
        bb.minPoint.z * 10, bb.maxPoint.z * 10))

    if PRINT_POSE:
        # Print pose: slot axis (v) vertical, closed slot end on the bed, open end up. The slot's dovetail profile
        # and the flange holes then lie in the XY plane (most accurate). Model +Y (= -v) becomes +Z.
        import math

        def move(m):
            oc = adsk.core.ObjectCollection.create()
            oc.add(body)
            mi = feats.moveFeatures.createInput2(oc)
            mi.defineAsFreeMove(m)
            feats.moveFeatures.add(mi)

        rot = adsk.core.Matrix3D.create()
        rot.setToRotation(math.pi / 2, adsk.core.Vector3D.create(1, 0, 0), adsk.core.Point3D.create(0, 0, 0))
        move(rot)
        b2 = body.boundingBox
        tr = adsk.core.Matrix3D.create()
        tr.translation = adsk.core.Vector3D.create(-(b2.minPoint.x + b2.maxPoint.x) / 2,
                                                   -(b2.minPoint.y + b2.maxPoint.y) / 2, -b2.minPoint.z)
        move(tr)
        bb = body.boundingBox
        print('print pose bbox mm: x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f' % (
            bb.minPoint.x * 10, bb.maxPoint.x * 10, bb.minPoint.y * 10, bb.maxPoint.y * 10,
            bb.minPoint.z * 10, bb.maxPoint.z * 10))
    print('bodies:', root.bRepBodies.count, '| volume cm3: %.2f' % body.volume)
    app.activeViewport.fit()
