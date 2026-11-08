// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The component definitions shipped with MartyGraphics, as JSON text (Foundation-only, no bundle resources, so the
/// library loads the same way on iOS and macOS). `MGSolidLibrary.builtIn` registers them in this order; a component
/// may only use components listed before it. To add one: write the JSON, check it with
/// `marty-solid component check FILE.json`, then add it here in a reviewed pull request (the tests compile every
/// entry at its defaults).
public enum MGSolidBuiltInComponents {
    public static let sources: [String] = [spurPair, planetaryStage, sliderCrank, propeller, housingBase, shaftWithBearing, fanStage,
                                           mannequin, centrifugalCompressor, microTurbojet]

    static let spurPair = #"""
    {"v": 1, "kind": "component", "id": "spurPair", "title": "Spur gear pair",
     "about": "Pinion (input) driving a wheel at the standard centre distance; the wheel turns -pinionTeeth/wheelTeeth per pinion turn.",
     "params": {
      "pinionTeeth": {"default": 12, "min": 12, "max": 100, "integer": true},
      "wheelTeeth": {"default": 36, "min": 12, "max": 200, "integer": true},
      "module": {"default": 2, "min": 0.5, "max": 10, "about": "tooth size in mm (pitch diameter / teeth)"},
      "width": {"default": 10, "min": 2, "max": 100, "about": "face width in mm"}
     },
     "parts": [
      {"id": "pinion", "name": "Pinion (input)", "material": "brass",
       "shape": [{"gear": {"teeth": {"param": "pinionTeeth"}, "module": {"param": "module"}, "width": {"param": "width"},
                           "bore": {"mul": [1.5, {"param": "module"}]}}},
                 {"shaft": {"radius": {"mul": [1.5, {"param": "module"}]}, "z0": {"mul": [-2, {"param": "module"}]},
                            "length": {"add": [{"param": "width"}, {"mul": [4, {"param": "module"}]}]}}}],
       "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}},
      {"id": "wheel", "name": "Wheel (output)", "material": "brushedSteel",
       "at": [{"mul": [0.5, {"param": "module"}, {"add": [{"param": "pinionTeeth"}, {"param": "wheelTeeth"}]}]}, 0, 0],
       "shape": [{"gear": {"teeth": {"param": "wheelTeeth"}, "module": {"param": "module"}, "width": {"param": "width"},
                           "bore": {"mul": [1.5, {"param": "module"}]}}},
                 {"shaft": {"radius": {"mul": [1.5, {"param": "module"}]}, "z0": {"mul": [-2, {"param": "module"}]},
                            "length": {"add": [{"param": "width"}, {"mul": [4, {"param": "module"}]}]}}}],
       "joint": {"revolute": [0, 0, 1]}}
     ],
     "constraints": [{"gearMesh": {"a": "pinion", "b": "wheel"}}],
     "anchors": {"input": "pinion", "output": "wheel"}}
    """#

    static let planetaryStage = #"""
    {"v": 1, "kind": "component", "id": "planetaryStage", "title": "Planetary gear stage",
     "about": "Sun (input), planets on a carrier (output) and a fixed ring of sunTeeth + 2 planetTeeth; carrier turns sun/(sun+ring) per sun turn.",
     "params": {
      "sunTeeth": {"default": 24, "min": 12, "max": 80, "integer": true},
      "planetTeeth": {"default": 18, "min": 12, "max": 60, "integer": true},
      "planets": {"default": 3, "min": 2, "max": 6, "integer": true, "about": "(2 sunTeeth + 2 planetTeeth) / planets must be whole"},
      "module": {"default": 2, "min": 0.5, "max": 10, "about": "tooth size in mm"},
      "width": {"default": 12, "min": 2, "max": 100, "about": "face width in mm"}
     },
     "checks": {
      "spacing": {"int": {"div": [{"mul": [2, {"add": [{"param": "sunTeeth"}, {"param": "planetTeeth"}]}]}, {"param": "planets"}]}},
      "planetsClear": {"lt": [{"add": [{"param": "planetTeeth"}, 2.5]},
                              {"mul": [{"add": [{"param": "sunTeeth"}, {"param": "planetTeeth"}]}, {"sin": {"div": [180, {"param": "planets"}]}}]}]}
     },
     "parts": [
      {"id": "sun", "name": "Sun gear (input)", "material": "brass",
       "shape": [{"gear": {"teeth": {"param": "sunTeeth"}, "module": {"param": "module"}, "width": {"param": "width"},
                           "bore": {"mul": [1.5, {"param": "module"}]}}},
                 {"shaft": {"radius": {"mul": [1.5, {"param": "module"}]}, "z0": {"mul": [-6, {"param": "module"}]},
                            "length": {"add": [{"param": "width"}, {"mul": [6, {"param": "module"}]}]}}}],
       "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}, "explode": [0, 0, 30], "explodeWindow": [0.2, 0.8]},
      {"id": "ring", "name": "Ring gear (fixed)", "material": "darkSteel",
       "shape": {"ringGear": {"teeth": {"add": [{"param": "sunTeeth"}, {"mul": [2, {"param": "planetTeeth"}]}]},
                              "module": {"param": "module"}, "width": {"param": "width"},
                              "outer": {"mul": [{"param": "module"}, {"add": [{"mul": [0.5, {"param": "sunTeeth"}]}, {"param": "planetTeeth"}, 4]}]}}},
       "explode": [0, 0, 15], "explodeWindow": [0.3, 0.9]},
      {"id": "carrier", "name": "Planet carrier (output)", "material": "anodized.blue",
       "shape": [{"carrier": {"arms": {"param": "planets"},
                              "radius": {"mul": [0.5, {"param": "module"}, {"add": [{"param": "sunTeeth"}, {"param": "planetTeeth"}]}]},
                              "hub": {"mul": [0.25, {"param": "module"}, {"param": "sunTeeth"}]},
                              "boss": {"mul": [2.5, {"param": "module"}]}, "armWidth": {"mul": [3.5, {"param": "module"}]},
                              "thickness": {"mul": [2.5, {"param": "module"}]},
                              "z0": {"add": [{"param": "width"}, {"mul": [0.5, {"param": "module"}]}]}}},
                 {"shaft": {"radius": {"mul": [0.15, {"param": "module"}, {"param": "sunTeeth"}]},
                            "z0": {"add": [{"param": "width"}, {"mul": [3, {"param": "module"}]}]},
                            "length": {"mul": [6, {"param": "module"}]}}}],
       "joint": {"revolute": [0, 0, 1]}, "explode": [0, 0, 60], "explodeWindow": [0, 0.6]},
      {"id": "planet", "name": "Planet gear", "parent": "carrier", "material": "brushedSteel",
       "at": [{"mul": [0.5, {"param": "module"}, {"add": [{"param": "sunTeeth"}, {"param": "planetTeeth"}]}]}, 0, 0],
       "repeat": {"count": {"param": "planets"}, "axis": [0, 0, 1]},
       "shape": [{"gear": {"teeth": {"param": "planetTeeth"}, "module": {"param": "module"}, "width": {"param": "width"},
                           "bore": {"mul": [1.2, {"param": "module"}]}}},
                 {"shaft": {"radius": {"mul": [1.2, {"param": "module"}]}, "z0": 0,
                            "length": {"add": [{"param": "width"}, {"mul": [3, {"param": "module"}]}]}}}],
       "joint": {"revolute": [0, 0, 1]}, "explode": [0, 0, -20], "explodeWindow": [0.1, 0.7]}
     ],
     "constraints": [
      {"gearMesh": {"a": "sun", "b": "planet", "carrier": "carrier"}},
      {"gearMesh": {"a": "ring", "b": "planet", "carrier": "carrier"}},
      {"fixed": "ring"}
     ],
     "anchors": {"input": "sun", "output": "carrier"}}
    """#

    static let sliderCrank = #"""
    {"v": 1, "kind": "component", "id": "sliderCrank", "title": "Slider-crank",
     "about": "Crank (input) turning, rod pushing a piston along +X on a frame; stroke = 2 radius.",
     "params": {
      "radius": {"default": 18, "min": 8, "max": 100, "about": "crank radius in mm (half the stroke)"},
      "rod": {"default": 62, "min": 30, "max": 400, "about": "connecting rod length in mm"},
      "piston": {"default": 14, "min": 5, "max": 60, "about": "piston radius in mm"}
     },
     "checks": {
      "rodLength": {"lt": [{"add": [{"mul": [2, {"param": "radius"}]}, {"mul": [0.85, {"param": "piston"}]}, 6]}, {"param": "rod"}]}
     },
     "parts": [
      {"id": "frame", "name": "Frame", "material": "darkSteel",
       "at": [{"mul": [0.5, {"add": [{"param": "rod"}, 10]}]}, 0, {"neg": {"add": [{"param": "piston"}, 6]}}],
       "shape": {"box": {"size": [{"add": [{"param": "rod"}, {"mul": [2, {"param": "radius"}]}, 50]},
                                  {"add": [{"mul": [2, {"param": "piston"}]}, 32]}, 6], "chamfer": 1}}},
      {"id": "crank", "name": "Crank (input)", "material": "brushedSteel",
       "shape": [{"shaft": {"radius": 6, "length": {"add": [{"param": "piston"}, 9]}, "z0": {"neg": {"add": [{"param": "piston"}, 3]}}}},
                 {"box": {"size": [{"add": [{"param": "radius"}, 12]}, 12, 6], "chamfer": 1,
                          "at": [{"mul": [0.5, {"param": "radius"}]}, 0, -3]}},
                 {"shaft": {"radius": 4, "length": 10, "z0": 0, "at": [{"param": "radius"}, 0, 0]}}],
       "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}},
      {"id": "piston", "name": "Piston", "material": "aluminum",
       "shape": {"shaft": {"radius": {"param": "piston"}, "length": {"mul": [1.7, {"param": "piston"}]},
                           "z0": {"mul": [-0.85, {"param": "piston"}]}, "rot": [0, 1, 0, 90]}},
       "joint": {"prismatic": [1, 0, 0]},
       "drive": {"crankSlider": {"crank": "crank", "radius": {"param": "radius"}, "rod": {"param": "rod"}}}},
      {"id": "rod", "name": "Connecting rod", "parent": "piston", "material": "anodized.orange",
       "shape": {"box": {"size": [{"param": "rod"}, 8, 4], "chamfer": 1, "at": [{"mul": [-0.5, {"param": "rod"}]}, 0, 5]}},
       "joint": {"revolute": [0, 0, 1]},
       "drive": {"crankRod": {"crank": "crank", "radius": {"param": "radius"}, "rod": {"param": "rod"}}}}
     ],
     "anchors": {"input": "crank", "output": "piston"}}
    """#

    static let propeller = #"""
    {"v": 1, "kind": "component", "id": "propeller", "title": "Propeller",
     "about": "Hub (input) with N airfoil blades, steep at the hub and flatter at the tip; turns leading edge first, thrust toward +Z.",
     "params": {
      "blades": {"default": 3, "min": 2, "max": 8, "integer": true},
      "span": {"default": 110, "min": 20, "max": 1000, "about": "blade length in mm"},
      "chord": {"default": 34, "min": 5, "max": 400, "about": "blade width at the root in mm"},
      "pitch": {"default": -40, "min": -80, "max": 80, "about": "root blade angle, degrees (negative = thrust +Z)"},
      "twist": {"default": 28, "min": -60, "max": 60, "about": "extra angle at the tip, degrees"},
      "hub": {"default": 12, "min": 4, "max": 200, "about": "hub radius in mm"}
     },
     "parts": [
      {"id": "hub", "name": "Hub and shaft (input)", "material": "darkSteel",
       "shape": [{"shaft": {"radius": {"param": "hub"}, "length": {"mul": [2.5, {"param": "hub"}]}, "z0": {"mul": [-1.25, {"param": "hub"}]}}},
                 {"shaft": {"radius": {"mul": [0.42, {"param": "hub"}]}, "length": {"mul": [3.4, {"param": "hub"}]},
                            "z0": {"mul": [-4.6, {"param": "hub"}]}}}],
       "joint": {"revolute": [0, 0, -1]}, "drive": {"input": 1}},
      {"id": "blade", "name": "Blade", "parent": "hub", "material": "aluminum",
       "repeat": {"count": {"param": "blades"}, "axis": [0, 0, 1]},
       "shape": {"blade": {"span": {"param": "span"}, "chord": {"param": "chord"}, "tipChord": {"mul": [0.47, {"param": "chord"}]},
                           "pitch": {"param": "pitch"}, "twist": {"param": "twist"}, "root": {"mul": [0.83, {"param": "hub"}]}, "camber": 0.04}},
       "explode": [0, 0, 30]}
     ],
     "anchors": {"input": "hub"}}
    """#

    static let housingBase = #"""
    {"v": 1, "kind": "component", "id": "housingBase", "title": "Housing base",
     "about": "Fixed round base plate with a centre bore and N bolts; its top face is at z = 0.",
     "params": {
      "radius": {"default": 84, "min": 20, "max": 1000, "about": "plate radius in mm"},
      "thickness": {"default": 7.5, "min": 2, "max": 100},
      "bore": {"default": 8, "min": 1, "max": 500, "about": "centre hole radius in mm"},
      "bolts": {"default": 6, "min": 3, "max": 12, "integer": true}
     },
     "checks": {"bore": {"lt": [{"add": [{"param": "bore"}, 1]}, {"mul": [0.6, {"param": "radius"}]}]}},
     "parts": [
      {"id": "base", "name": "Housing base", "material": "aluminum",
       "shape": {"plate": {"radius": {"param": "radius"}, "thickness": {"param": "thickness"}, "z0": {"neg": {"param": "thickness"}},
                           "chamfer": {"mul": [0.15, {"param": "thickness"}]}, "holes": [[0, 0, {"param": "bore"}]]}},
       "explode": [0, 0, -20], "explodeWindow": [0, 0.4]},
      {"id": "bolt", "name": "Bolt", "parent": "base", "material": "blackOxide",
       "at": [{"mul": [0.88, {"param": "radius"}]}, 0, 0], "repeat": {"count": {"param": "bolts"}, "axis": [0, 0, 1]},
       "shape": [{"hex": {"acrossFlats": {"mul": [0.085, {"param": "radius"}]}, "length": {"mul": [0.05, {"param": "radius"}]}, "z0": 0}},
                 {"shaft": {"radius": {"mul": [0.03, {"param": "radius"}]}, "length": {"param": "thickness"},
                            "z0": {"neg": {"param": "thickness"}}}}]}
     ],
     "anchors": {"frame": "base"}}
    """#

    static let shaftWithBearing = #"""
    {"v": 1, "kind": "component", "id": "shaftWithBearing", "title": "Shaft in two bearings",
     "about": "Driven shaft (input) along +Z from z = 0 to length, held by two fixed flanged bearings.",
     "params": {
      "radius": {"default": 6, "min": 1, "max": 200, "about": "shaft radius in mm"},
      "length": {"default": 80, "min": 10, "max": 2000},
      "bearingWidth": {"default": 12, "min": 2, "max": 400}
     },
     "checks": {"bearingsApart": {"lt": [{"mul": [2, {"param": "bearingWidth"}]}, {"mul": [0.8, {"param": "length"}]}]}},
     "parts": [
      {"id": "shaft", "name": "Shaft (input)", "material": "polishedSteel",
       "shape": {"shaft": {"radius": {"param": "radius"}, "length": {"param": "length"}, "z0": 0, "chamfer": {"mul": [0.1, {"param": "radius"}]}}},
       "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}},
      {"id": "lowerBearing", "name": "Lower bearing", "material": "bronze",
       "shape": [{"tube": {"inner": {"mul": [1.05, {"param": "radius"}]}, "outer": {"mul": [2.4, {"param": "radius"}]},
                           "length": {"param": "bearingWidth"}, "z0": {"mul": [0.1, {"param": "length"}]}}},
                 {"tube": {"inner": {"mul": [2.3, {"param": "radius"}]}, "outer": {"mul": [3.4, {"param": "radius"}]},
                           "length": {"mul": [0.3, {"param": "bearingWidth"}]}, "z0": {"mul": [0.1, {"param": "length"}]}}}],
       "explode": [0, 0, -15]},
      {"id": "upperBearing", "name": "Upper bearing", "material": "bronze",
       "shape": [{"tube": {"inner": {"mul": [1.05, {"param": "radius"}]}, "outer": {"mul": [2.4, {"param": "radius"}]},
                           "length": {"param": "bearingWidth"}, "z0": {"sub": [{"mul": [0.9, {"param": "length"}]}, {"param": "bearingWidth"}]}}},
                 {"tube": {"inner": {"mul": [2.3, {"param": "radius"}]}, "outer": {"mul": [3.4, {"param": "radius"}]},
                           "length": {"mul": [0.3, {"param": "bearingWidth"}]},
                           "z0": {"sub": [{"mul": [0.9, {"param": "length"}]}, {"mul": [0.3, {"param": "bearingWidth"}]}]}}}],
       "explode": [0, 0, 15]}
     ],
     "anchors": {"input": "shaft"}}
    """#

    static let fanStage = #"""
    {"v": 1, "kind": "component", "id": "fanStage", "title": "Ducted fan stage",
     "about": "Driven hub (input) with a blade row of N airfoils inside a fixed casing; axis +Z, leading edges toward -Z.",
     "params": {
      "blades": {"default": 18, "min": 6, "max": 48, "integer": true},
      "root": {"default": 60, "min": 10, "max": 1000, "about": "hub radius in mm"},
      "span": {"default": 90, "min": 10, "max": 2000, "about": "blade length in mm"},
      "chord": {"default": 40, "min": 5, "max": 500},
      "stagger": {"default": 35, "min": 0, "max": 70, "about": "chord angle from the axis at the root, degrees"},
      "twist": {"default": 15, "min": -15, "max": 15, "about": "extra stagger at the tip, degrees"}
     },
     "parts": [
      {"id": "hub", "name": "Hub (input)", "material": "titanium",
       "shape": {"shaft": {"radius": {"param": "root"}, "length": {"mul": [1.4, {"param": "chord"}]}, "z0": {"mul": [-0.7, {"param": "chord"}]}}},
       "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}},
      {"id": "rotor", "name": "Blade row", "parent": "hub", "material": "titanium",
       "shape": {"bladeRow": {"count": {"param": "blades"}, "span": {"param": "span"}, "chord": {"param": "chord"},
                              "root": {"mul": [0.98, {"param": "root"}]}, "stagger": {"param": "stagger"}, "twist": {"param": "twist"},
                              "thickness": 0.08, "sections": 6, "chordSamples": 12}}},
      {"id": "casing", "name": "Casing", "material": "aluminum",
       "shape": {"tube": {"inner": {"add": [{"param": "root"}, {"param": "span"}, 2]}, "outer": {"add": [{"param": "root"}, {"param": "span"}, 8]},
                          "length": {"mul": [1.6, {"param": "chord"}]}, "z0": {"mul": [-0.8, {"param": "chord"}]}}},
       "explode": [0, 0, 40]}
     ],
     "anchors": {"input": "hub"}}
    """#

    static let mannequin = #"""
    {"v": 1, "kind": "component", "id": "mannequin", "title": "Schematic human figure (mannequin)",
     "about": "Smooth schematic adult 1.75 m tall, facing -Y, feet at z = 0, left side +X; shoulder and elbow joints held at the given angles.",
     "params": {
      "leftShoulder": {"default": 10, "min": 4, "max": 170, "about": "left arm raised out to the side, degrees from hanging"},
      "rightShoulder": {"default": 10, "min": 4, "max": 170, "about": "right arm raised out to the side, degrees from hanging"},
      "leftElbow": {"default": 15, "min": 0, "max": 150, "about": "left forearm bent forward, degrees"},
      "rightElbow": {"default": 15, "min": 0, "max": 150, "about": "right forearm bent forward, degrees"}
     },
     "parts": [
      {"id": "body", "name": "Torso and pelvis", "material": "plastic.white", "smooth": 50, "at": [0, 125, 1340],
       "shape": [{"revolvedProfile": {"points": [[0, -175], [40.2, -167], [74.2, -144.2], [97, -110.2], [105, -70], [105, 70], [97, 110.2], [74.2, 144.2], [40.2, 167], [0, 175]], "rot": [0, 1, 0, 90], "at": [0, -125, -390]}},
                 {"revolvedProfile": {"points": [[0, 990], [70, 995], [98, 1020], [104, 1080], [100, 1150], [106, 1210], [0, 1225]], "at": [0, -125, -1340]}},
                 {"revolvedProfile": {"points": [[0, 1165], [72, 1176], [110, 1212], [124, 1270], [125, 1340], [119, 1405], [102, 1460], [66, 1494], [0, 1505]], "at": [0, -125, -1340]}},
                 {"revolvedProfile": {"points": [[0, -210], [23, -205.4], [42.4, -192.4], [55.4, -173], [60, -150], [60, 150], [55.4, 173], [42.4, 192.4], [23, 205.4], [0, 210]], "rot": [0, 1, 0, 90], "at": [0, -120, 92]}},
                 {"shaft": {"radius": 42, "length": 110, "z0": 135, "at": [0, -125, 0]}}]},
      {"id": "skull", "name": "Head", "parent": "body", "material": "plastic.white", "smooth": 50, "at": [0, -125, 312],
       "shape": [{"revolvedProfile": {"points": [[0, -107], [52, -101], [80, -76], [92, -27], [91, 28], [80, 74], [52, 102], [0, 111]]}},
                 {"revolvedProfile": {"points": [[0, 0], [12, 3], [17, 12], [13, 24], [0, 28]], "rot": [1, 0, 0, 90], "at": [0, -80, -8]}}]},
      {"id": "upperArmL", "name": "Left upper arm", "parent": "body", "material": "plastic.white", "smooth": 50, "at": [205, -125, 90], "rot": [0, -1, 0, {"param": "leftShoulder"}], "joint": {"revolute": [0, -1, 0]}, "drive": {"input": 0},
       "shape": [{"revolvedProfile": {"points": [[0, -56], [28, -48.5], [48.5, -28], [56, 0], [48.5, 28], [28, 48.5], [0, 56]]}},
                 {"revolvedProfile": {"points": [[0, -12], [36, -20], [49, -48], [46, -150], [40, -262], [30, -290], [0, -300]]}}]},
      {"id": "lowerArmL", "name": "Left forearm", "parent": "upperArmL", "material": "plastic.white", "smooth": 50, "at": [0, 0, -300], "rot": [-1, 0, 0, {"param": "leftElbow"}], "joint": {"revolute": [-1, 0, 0]}, "drive": {"input": 0},
       "shape": [{"revolvedProfile": {"points": [[0, -42], [21, -36.4], [36.4, -21], [42, 0], [36.4, 21], [21, 36.4], [0, 42]]}},
                 {"revolvedProfile": {"points": [[0, -10], [34, -18], [41, -55], [37, -170], [30, -245], [20, -262], [0, -268]]}}]},
      {"id": "handL", "name": "Left hand", "parent": "lowerArmL", "material": "plastic.white", "smooth": 50, "at": [0, 0, -268],
       "shape": [{"revolvedProfile": {"points": [[0, 4], [24, -6], [35, -45], [33, -110], [24, -158], [0, -178]]}}]},
      {"id": "upperArmR", "name": "Right upper arm", "parent": "body", "material": "plastic.white", "smooth": 50, "at": [-205, -125, 90], "rot": [0, 1, 0, {"param": "rightShoulder"}], "joint": {"revolute": [0, 1, 0]}, "drive": {"input": 0},
       "shape": [{"revolvedProfile": {"points": [[0, -56], [28, -48.5], [48.5, -28], [56, 0], [48.5, 28], [28, 48.5], [0, 56]]}},
                 {"revolvedProfile": {"points": [[0, -12], [36, -20], [49, -48], [46, -150], [40, -262], [30, -290], [0, -300]]}}]},
      {"id": "lowerArmR", "name": "Right forearm", "parent": "upperArmR", "material": "plastic.white", "smooth": 50, "at": [0, 0, -300], "rot": [-1, 0, 0, {"param": "rightElbow"}], "joint": {"revolute": [-1, 0, 0]}, "drive": {"input": 0},
       "shape": [{"revolvedProfile": {"points": [[0, -42], [21, -36.4], [36.4, -21], [42, 0], [36.4, 21], [21, 36.4], [0, 42]]}},
                 {"revolvedProfile": {"points": [[0, -10], [34, -18], [41, -55], [37, -170], [30, -245], [20, -262], [0, -268]]}}]},
      {"id": "handR", "name": "Right hand", "parent": "lowerArmR", "material": "plastic.white", "smooth": 50, "at": [0, 0, -268],
       "shape": [{"revolvedProfile": {"points": [[0, 4], [24, -6], [35, -45], [33, -110], [24, -158], [0, -178]]}}]},
      {"id": "legL", "name": "Left leg", "material": "plastic.white", "smooth": 50, "at": [95, 0, 880],
       "shape": [{"revolvedProfile": {"points": [[0, -72], [36, -62.4], [62.4, -36], [72, 0], [62.4, 36], [36, 62.4], [0, 72]]}},
                 {"revolvedProfile": {"points": [[0, -20], [60, -40], [76, -90], [70, -250], [56, -390], [0, -420]]}},
                 {"revolvedProfile": {"points": [[0, -50], [25, -43.3], [43.3, -25], [50, 0], [43.3, 25], [25, 43.3], [0, 50]], "at": [0, 0, -420]}},
                 {"revolvedProfile": {"points": [[0, -440], [44, -452], [52, -500], [44, -660], [34, -760], [26, -800], [0, -812]]}}]},
      {"id": "footL", "name": "Left foot", "parent": "legL", "material": "plastic.white", "smooth": 50, "at": [0, 0, -880],
       "shape": [{"revolvedProfile": {"points": [[0, 0], [30, 8], [44, 40], [46, 120], [40, 196], [24, 236], [0, 250]], "rot": [1, 0, 0, 90], "at": [0, 40, 46]}}]},
      {"id": "legR", "name": "Right leg", "material": "plastic.white", "smooth": 50, "at": [-95, 0, 880],
       "shape": [{"revolvedProfile": {"points": [[0, -72], [36, -62.4], [62.4, -36], [72, 0], [62.4, 36], [36, 62.4], [0, 72]]}},
                 {"revolvedProfile": {"points": [[0, -20], [60, -40], [76, -90], [70, -250], [56, -390], [0, -420]]}},
                 {"revolvedProfile": {"points": [[0, -50], [25, -43.3], [43.3, -25], [50, 0], [43.3, 25], [25, 43.3], [0, 50]], "at": [0, 0, -420]}},
                 {"revolvedProfile": {"points": [[0, -440], [44, -452], [52, -500], [44, -660], [34, -760], [26, -800], [0, -812]]}}]},
      {"id": "footR", "name": "Right foot", "parent": "legR", "material": "plastic.white", "smooth": 50, "at": [0, 0, -880],
       "shape": [{"revolvedProfile": {"points": [[0, 0], [30, 8], [44, 40], [46, 120], [40, 196], [24, 236], [0, 250]], "rot": [1, 0, 0, 90], "at": [0, 40, 46]}}]}
     ],
     "anchors": {"back": "body", "head": "skull", "leftShoulder": "upperArmL", "rightShoulder": "upperArmR", "leftHand": "handL", "rightHand": "handR", "leftFoot": "footL", "rightFoot": "footR"},
     "anchorAbout": {"back": "Origin on the back surface at chest height; +Y points out of the back, so a shape from y = 0 outward touches the torso.",
      "head": "Centre of the head; world axes.",
      "leftShoulder": "Left shoulder joint; turns with the arm, local -Z runs down the upper arm.",
      "rightShoulder": "Right shoulder joint; turns with the arm, local -Z runs down the upper arm.",
      "leftHand": "Left wrist; local -Z runs along the hand, +Z up the forearm.",
      "rightHand": "Right wrist; local -Z runs along the hand, +Z up the forearm.",
      "leftFoot": "Centre of the left sole, on the floor; world axes.",
      "rightFoot": "Centre of the right sole, on the floor; world axes."}}
    """#

    static let centrifugalCompressor = #"""
    {"v": 1, "kind": "component", "id": "centrifugalCompressor", "title": "Centrifugal compressor stage",
     "about": "Impeller (input) with N backswept vanes and N splitters on a disc, in a vaned diffuser ring; axis +Z, air enters at -Z, leaves outward.",
     "params": {
      "diameter": {"default": 100, "min": 30, "max": 1000, "about": "impeller tip diameter in mm"},
      "vanes": {"default": 7, "min": 4, "max": 12, "integer": true, "about": "main vanes; as many shorter splitter vanes sit between them"},
      "diffuserVanes": {"default": 12, "min": 6, "max": 12, "integer": true},
      "bore": {"default": 4, "min": 0.5, "max": 70, "about": "shaft hole radius in mm, below 0.075 diameter"}
     },
     "checks": {"bore": {"lt": [{"param": "bore"}, {"mul": [0.075, {"param": "diameter"}]}]}},
     "parts": [
      {"id": "impeller", "name": "Impeller hub and disc (input)", "material": "titanium", "smooth": 40, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1},
       "shape": {"revolvedProfile": {"points": [[{"param": "bore"}, {"mul": [-0.3, {"param": "diameter"}]}], [{"mul": [0.09, {"param": "diameter"}]}, {"mul": [-0.3, {"param": "diameter"}]}], [{"mul": [0.098, {"param": "diameter"}]}, {"mul": [-0.27, {"param": "diameter"}]}], [{"mul": [0.112, {"param": "diameter"}]}, {"mul": [-0.205, {"param": "diameter"}]}], [{"mul": [0.138, {"param": "diameter"}]}, {"mul": [-0.14, {"param": "diameter"}]}], [{"mul": [0.18, {"param": "diameter"}]}, {"mul": [-0.085, {"param": "diameter"}]}], [{"mul": [0.25, {"param": "diameter"}]}, {"mul": [-0.042, {"param": "diameter"}]}], [{"mul": [0.35, {"param": "diameter"}]}, {"mul": [-0.018, {"param": "diameter"}]}], [{"mul": [0.5, {"param": "diameter"}]}, {"mul": [-0.006, {"param": "diameter"}]}], [{"mul": [0.5, {"param": "diameter"}]}, {"mul": [0.03, {"param": "diameter"}]}], [{"mul": [0.3, {"param": "diameter"}]}, {"mul": [0.045, {"param": "diameter"}]}], [{"mul": [0.14, {"param": "diameter"}]}, {"mul": [0.085, {"param": "diameter"}]}], [{"param": "bore"}, {"mul": [0.1, {"param": "diameter"}]}]], "closed": true}}},
      {"id": "vane", "name": "Impeller vane", "parent": "impeller", "material": "titanium", "repeat": {"count": {"param": "vanes"}, "axis": [0, 0, 1]},
       "shape": [{"extrudedProfile": {"points": [[{"mul": [0.0701, {"param": "diameter"}]}, {"mul": [0.008, {"param": "diameter"}]}], [{"mul": [0.1192, {"param": "diameter"}]}, {"mul": [0.0074, {"param": "diameter"}]}], [{"mul": [0.1685, {"param": "diameter"}]}, {"mul": [0.0044, {"param": "diameter"}]}], [{"mul": [0.2179, {"param": "diameter"}]}, {"mul": [-0.0025, {"param": "diameter"}]}], [{"mul": [0.2665, {"param": "diameter"}]}, {"mul": [-0.0147, {"param": "diameter"}]}], [{"mul": [0.2626, {"param": "diameter"}]}, {"mul": [-0.0302, {"param": "diameter"}]}], [{"mul": [0.2148, {"param": "diameter"}]}, {"mul": [-0.0182, {"param": "diameter"}]}], [{"mul": [0.1669, {"param": "diameter"}]}, {"mul": [-0.0115, {"param": "diameter"}]}], [{"mul": [0.1186, {"param": "diameter"}]}, {"mul": [-0.0086, {"param": "diameter"}]}], [{"mul": [0.0699, {"param": "diameter"}]}, {"mul": [-0.008, {"param": "diameter"}]}]], "depth": {"mul": [0.156, {"param": "diameter"}]}, "z0": {"mul": [-0.16, {"param": "diameter"}]}}},
                 {"extrudedProfile": {"points": [[{"mul": [0.2504, {"param": "diameter"}]}, {"mul": [-0.0099, {"param": "diameter"}]}], [{"mul": [0.286, {"param": "diameter"}]}, {"mul": [-0.0215, {"param": "diameter"}]}], [{"mul": [0.3214, {"param": "diameter"}]}, {"mul": [-0.0374, {"param": "diameter"}]}], [{"mul": [0.3556, {"param": "diameter"}]}, {"mul": [-0.0581, {"param": "diameter"}]}], [{"mul": [0.3876, {"param": "diameter"}]}, {"mul": [-0.0837, {"param": "diameter"}]}], [{"mul": [0.3776, {"param": "diameter"}]}, {"mul": [-0.0962, {"param": "diameter"}]}], [{"mul": [0.3464, {"param": "diameter"}]}, {"mul": [-0.0712, {"param": "diameter"}]}], [{"mul": [0.3139, {"param": "diameter"}]}, {"mul": [-0.0516, {"param": "diameter"}]}], [{"mul": [0.2803, {"param": "diameter"}]}, {"mul": [-0.0364, {"param": "diameter"}]}], [{"mul": [0.2454, {"param": "diameter"}]}, {"mul": [-0.0251, {"param": "diameter"}]}]], "depth": {"mul": [0.106, {"param": "diameter"}]}, "z0": {"mul": [-0.11, {"param": "diameter"}]}}},
                 {"extrudedProfile": {"points": [[{"mul": [0.3733, {"param": "diameter"}]}, {"mul": [-0.0715, {"param": "diameter"}]}], [{"mul": [0.3989, {"param": "diameter"}]}, {"mul": [-0.0946, {"param": "diameter"}]}], [{"mul": [0.4229, {"param": "diameter"}]}, {"mul": [-0.1221, {"param": "diameter"}]}], [{"mul": [0.4446, {"param": "diameter"}]}, {"mul": [-0.1537, {"param": "diameter"}]}], [{"mul": [0.463, {"param": "diameter"}]}, {"mul": [-0.1891, {"param": "diameter"}]}], [{"mul": [0.4488, {"param": "diameter"}]}, {"mul": [-0.1965, {"param": "diameter"}]}], [{"mul": [0.4308, {"param": "diameter"}]}, {"mul": [-0.1619, {"param": "diameter"}]}], [{"mul": [0.4103, {"param": "diameter"}]}, {"mul": [-0.1319, {"param": "diameter"}]}], [{"mul": [0.3875, {"param": "diameter"}]}, {"mul": [-0.1058, {"param": "diameter"}]}], [{"mul": [0.3626, {"param": "diameter"}]}, {"mul": [-0.0833, {"param": "diameter"}]}]], "depth": {"mul": [0.066, {"param": "diameter"}]}, "z0": {"mul": [-0.07, {"param": "diameter"}]}}}]},
      {"id": "splitter", "name": "Splitter vane", "parent": "impeller", "material": "titanium", "rot": [0, 0, 1, {"div": [180, {"param": "vanes"}]}], "repeat": {"count": {"param": "vanes"}, "axis": [0, 0, 1]},
       "shape": [{"extrudedProfile": {"points": [[{"mul": [0.2504, {"param": "diameter"}]}, {"mul": [-0.0099, {"param": "diameter"}]}], [{"mul": [0.286, {"param": "diameter"}]}, {"mul": [-0.0215, {"param": "diameter"}]}], [{"mul": [0.3214, {"param": "diameter"}]}, {"mul": [-0.0374, {"param": "diameter"}]}], [{"mul": [0.3556, {"param": "diameter"}]}, {"mul": [-0.0581, {"param": "diameter"}]}], [{"mul": [0.3876, {"param": "diameter"}]}, {"mul": [-0.0837, {"param": "diameter"}]}], [{"mul": [0.3776, {"param": "diameter"}]}, {"mul": [-0.0962, {"param": "diameter"}]}], [{"mul": [0.3464, {"param": "diameter"}]}, {"mul": [-0.0712, {"param": "diameter"}]}], [{"mul": [0.3139, {"param": "diameter"}]}, {"mul": [-0.0516, {"param": "diameter"}]}], [{"mul": [0.2803, {"param": "diameter"}]}, {"mul": [-0.0364, {"param": "diameter"}]}], [{"mul": [0.2454, {"param": "diameter"}]}, {"mul": [-0.0251, {"param": "diameter"}]}]], "depth": {"mul": [0.106, {"param": "diameter"}]}, "z0": {"mul": [-0.11, {"param": "diameter"}]}}},
                 {"extrudedProfile": {"points": [[{"mul": [0.3733, {"param": "diameter"}]}, {"mul": [-0.0715, {"param": "diameter"}]}], [{"mul": [0.3989, {"param": "diameter"}]}, {"mul": [-0.0946, {"param": "diameter"}]}], [{"mul": [0.4229, {"param": "diameter"}]}, {"mul": [-0.1221, {"param": "diameter"}]}], [{"mul": [0.4446, {"param": "diameter"}]}, {"mul": [-0.1537, {"param": "diameter"}]}], [{"mul": [0.463, {"param": "diameter"}]}, {"mul": [-0.1891, {"param": "diameter"}]}], [{"mul": [0.4488, {"param": "diameter"}]}, {"mul": [-0.1965, {"param": "diameter"}]}], [{"mul": [0.4308, {"param": "diameter"}]}, {"mul": [-0.1619, {"param": "diameter"}]}], [{"mul": [0.4103, {"param": "diameter"}]}, {"mul": [-0.1319, {"param": "diameter"}]}], [{"mul": [0.3875, {"param": "diameter"}]}, {"mul": [-0.1058, {"param": "diameter"}]}], [{"mul": [0.3626, {"param": "diameter"}]}, {"mul": [-0.0833, {"param": "diameter"}]}]], "depth": {"mul": [0.066, {"param": "diameter"}]}, "z0": {"mul": [-0.07, {"param": "diameter"}]}}}]},
      {"id": "diffuser", "name": "Diffuser ring", "material": "darkSteel", "explode": [0, 0, {"mul": [0.25, {"param": "diameter"}]}],
       "shape": [{"tube": {"inner": {"mul": [0.515, {"param": "diameter"}]}, "outer": {"mul": [0.8, {"param": "diameter"}]}, "length": {"mul": [0.035, {"param": "diameter"}]}, "z0": 0}},
                 {"tube": {"inner": {"mul": [0.775, {"param": "diameter"}]}, "outer": {"mul": [0.8, {"param": "diameter"}]}, "length": {"mul": [0.075, {"param": "diameter"}]}, "z0": {"mul": [-0.075, {"param": "diameter"}]}}}]},
      {"id": "diffuserVane", "name": "Diffuser vane", "parent": "diffuser", "material": "aluminum", "repeat": {"count": {"param": "diffuserVanes"}, "axis": [0, 0, 1]},
       "shape": {"extrudedProfile": {"points": [[{"mul": [0.5424, {"param": "diameter"}]}, {"mul": [0.0014, {"param": "diameter"}]}], [{"mul": [0.682, {"param": "diameter"}]}, {"mul": [0.3109, {"param": "diameter"}]}], [{"mul": [0.7261, {"param": "diameter"}]}, {"mul": [0.2874, {"param": "diameter"}]}], [{"mul": [0.5476, {"param": "diameter"}]}, {"mul": [-0.0014, {"param": "diameter"}]}], [{"mul": [0.5422, {"param": "diameter"}]}, {"mul": [-0.0053, {"param": "diameter"}]}]], "depth": {"mul": [0.071, {"param": "diameter"}]}, "z0": {"mul": [-0.07, {"param": "diameter"}]}}}}
     ],
     "anchors": {"input": "impeller", "frame": "diffuser"}}
    """#
    static let microTurbojet = #"""
    {"v": 1, "kind": "component", "id": "microTurbojet", "title": "Micro turbojet engine (schematic)",
     "about": "Small jet engine, JetCat class: intake, centrifugal compressor, diffuser, annular combustor, axial turbine, nozzle. Rotation solved; thrust not modelled.",
     "params": {
      "diameter": {"default": 110, "min": 60, "max": 300, "about": "casing outer diameter in mm"},
      "length": {"default": 280, "min": 120, "max": 900, "about": "intake to nozzle exit in mm (check fits)"},
      "cutaway": {"default": 0, "min": 0, "max": 1, "integer": true, "about": "1 opens a 90 degree window in the casing"}
     },
     "checks": {"bore": {"lt": [{"mul": [0.04, {"param": "diameter"}]}, {"mul": [0.0465, {"param": "diameter"}]}]}, "fits": {"lt": [{"add": [{"mul": [0.1, {"param": "length"}]}, {"mul": [0.26, {"param": "diameter"}]}]}, {"mul": [0.38, {"param": "length"}]}]}},
     "parts": [
      {"id": "intakeLip", "name": "Intake lip", "material": "aluminum", "smooth": 40, "shape": {"revolvedProfile": {"points": [[{"mul": [0.3, {"param": "diameter"}]}, {"mul": [0.06, {"param": "length"}]}], [{"mul": [0.31, {"param": "diameter"}]}, {"mul": [0.03, {"param": "length"}]}], [{"mul": [0.35, {"param": "diameter"}]}, {"mul": [0.008, {"param": "length"}]}], [{"mul": [0.42, {"param": "diameter"}]}, 0], [{"mul": [0.48, {"param": "diameter"}]}, {"mul": [0.006, {"param": "length"}]}], [{"mul": [0.5, {"param": "diameter"}]}, {"mul": [0.02, {"param": "length"}]}], [{"mul": [0.5, {"param": "diameter"}]}, {"mul": [0.06, {"param": "length"}]}]], "closed": true}}},
      {"id": "impeller", "name": "Compressor impeller (turns with the shaft)", "material": "titanium", "smooth": 40, "at": [0, 0, {"add": [{"mul": [0.06, {"param": "length"}]}, {"mul": [0.19, {"param": "diameter"}]}]}], "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}, "shape": [{"revolvedProfile": {"points": [[{"mul": [0.04, {"param": "diameter"}]}, {"mul": [-0.186, {"param": "diameter"}]}], [{"mul": [0.0558, {"param": "diameter"}]}, {"mul": [-0.186, {"param": "diameter"}]}], [{"mul": [0.06076, {"param": "diameter"}]}, {"mul": [-0.1674, {"param": "diameter"}]}], [{"mul": [0.06944, {"param": "diameter"}]}, {"mul": [-0.1271, {"param": "diameter"}]}], [{"mul": [0.08556, {"param": "diameter"}]}, {"mul": [-0.0868, {"param": "diameter"}]}], [{"mul": [0.1116, {"param": "diameter"}]}, {"mul": [-0.0527, {"param": "diameter"}]}], [{"mul": [0.155, {"param": "diameter"}]}, {"mul": [-0.02604, {"param": "diameter"}]}], [{"mul": [0.217, {"param": "diameter"}]}, {"mul": [-0.01116, {"param": "diameter"}]}], [{"mul": [0.31, {"param": "diameter"}]}, {"mul": [-0.00372, {"param": "diameter"}]}], [{"mul": [0.31, {"param": "diameter"}]}, {"mul": [0.0186, {"param": "diameter"}]}], [{"mul": [0.186, {"param": "diameter"}]}, {"mul": [0.0279, {"param": "diameter"}]}], [{"mul": [0.0868, {"param": "diameter"}]}, {"mul": [0.0527, {"param": "diameter"}]}], [{"mul": [0.04, {"param": "diameter"}]}, {"mul": [0.062, {"param": "diameter"}]}]], "closed": true}}, {"bladeRow": {"count": 7, "root": {"mul": [0.0682, {"param": "diameter"}]}, "span": {"mul": [0.2418, {"param": "diameter"}]}, "chord": {"mul": [0.186, {"param": "diameter"}]}, "tipChord": {"mul": [0.1364, {"param": "diameter"}]}, "z": {"mul": [-0.0806, {"param": "diameter"}]}, "stagger": 35, "twist": -35, "thickness": 0.1, "sections": 4, "chordSamples": 8}}]},
      {"id": "diffuser", "name": "Diffuser and shaft tunnel", "material": "darkSteel", "at": [0, 0, {"add": [{"mul": [0.06, {"param": "length"}]}, {"mul": [0.19, {"param": "diameter"}]}]}], "shape": [{"tube": {"inner": {"mul": [0.3193, {"param": "diameter"}]}, "outer": {"mul": [0.4464, {"param": "diameter"}]}, "length": {"mul": [0.0217, {"param": "diameter"}]}, "z0": 0}}, {"bladeRow": {"count": 12, "root": {"mul": [0.3286, {"param": "diameter"}]}, "span": {"mul": [0.1054, {"param": "diameter"}]}, "chord": {"mul": [0.0372, {"param": "diameter"}]}, "z": {"mul": [-0.0186, {"param": "diameter"}]}, "thickness": 0.3, "sections": 2, "chordSamples": 6}}, {"tube": {"inner": {"mul": [0.09, {"param": "diameter"}]}, "outer": {"mul": [0.11, {"param": "diameter"}]}, "z0": {"mul": [0.0217, {"param": "diameter"}]}, "length": {"sub": [{"mul": [0.64, {"param": "length"}]}, {"mul": [0.2117, {"param": "diameter"}]}]}}}]},
      {"id": "combustor", "name": "Annular combustor (ring)", "material": "nickelAlloy", "shape": [{"tube": {"inner": {"mul": [0.36, {"param": "diameter"}]}, "outer": {"mul": [0.375, {"param": "diameter"}]}, "length": {"mul": [0.3, {"param": "length"}]}, "z0": {"mul": [0.38, {"param": "length"}]}}}, {"tube": {"inner": {"mul": [0.15, {"param": "diameter"}]}, "outer": {"mul": [0.165, {"param": "diameter"}]}, "length": {"mul": [0.3, {"param": "length"}]}, "z0": {"mul": [0.38, {"param": "length"}]}}}, {"tube": {"inner": {"mul": [0.165, {"param": "diameter"}]}, "outer": {"mul": [0.36, {"param": "diameter"}]}, "length": {"mul": [0.015, {"param": "length"}]}, "z0": {"mul": [0.38, {"param": "length"}]}}}]},
      {"id": "nozzleGuideVanes", "name": "Turbine nozzle guide vanes", "material": "nickelAlloy", "shape": [{"tube": {"inner": {"mul": [0.11, {"param": "diameter"}]}, "outer": {"mul": [0.155, {"param": "diameter"}]}, "length": {"mul": [0.05, {"param": "length"}]}, "z0": {"mul": [0.7, {"param": "length"}]}}}, {"tube": {"inner": {"mul": [0.335, {"param": "diameter"}]}, "outer": {"mul": [0.35, {"param": "diameter"}]}, "length": {"mul": [0.05, {"param": "length"}]}, "z0": {"mul": [0.7, {"param": "length"}]}}}, {"bladeRow": {"count": 13, "root": {"mul": [0.15, {"param": "diameter"}]}, "span": {"mul": [0.19, {"param": "diameter"}]}, "chord": {"mul": [0.07, {"param": "diameter"}]}, "z": {"mul": [0.725, {"param": "length"}]}, "stagger": -40, "camber": -0.05, "thickness": 0.12, "sections": 3, "chordSamples": 8}}]},
      {"id": "turbineWheel", "name": "Turbine wheel (turns with the shaft)", "material": "nickelAlloy", "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}, "shape": [{"shaft": {"radius": {"mul": [0.15, {"param": "diameter"}]}, "length": {"mul": [0.04, {"param": "length"}]}, "z0": {"mul": [0.76, {"param": "length"}]}}}, {"bladeRow": {"count": 23, "root": {"mul": [0.145, {"param": "diameter"}]}, "span": {"mul": [0.185, {"param": "diameter"}]}, "chord": {"mul": [0.05, {"param": "diameter"}]}, "z": {"mul": [0.78, {"param": "length"}]}, "stagger": 40, "camber": 0.06, "thickness": 0.12, "sections": 3, "chordSamples": 8}}]},
      {"id": "nozzle", "name": "Exhaust nozzle and tail cone", "material": "darkSteel", "smooth": 40, "at": [0, 0, {"param": "length"}], "shape": [{"revolvedProfile": {"points": [[{"mul": [0.46, {"param": "diameter"}]}, {"mul": [-0.16, {"param": "length"}]}], [{"mul": [0.5, {"param": "diameter"}]}, {"mul": [-0.16, {"param": "length"}]}], [{"mul": [0.4, {"param": "diameter"}]}, 0], [{"mul": [0.37, {"param": "diameter"}]}, 0]], "closed": true}}, {"revolvedProfile": {"points": [[0, {"mul": [-0.19, {"param": "length"}]}], [{"mul": [0.16, {"param": "diameter"}]}, {"mul": [-0.18, {"param": "length"}]}], [{"mul": [0.15, {"param": "diameter"}]}, {"mul": [-0.16, {"param": "length"}]}], [0, {"mul": [-0.05, {"param": "length"}]}]]}}]},
      {"id": "shaft", "name": "Shaft (input)", "material": "polishedSteel", "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}, "shape": {"shaft": {"radius": {"mul": [0.04, {"param": "diameter"}]}, "z0": {"add": [{"mul": [0.06, {"param": "length"}]}, {"mul": [0.035, {"param": "diameter"}]}]}, "length": {"sub": [{"mul": [0.74, {"param": "length"}]}, {"mul": [0.035, {"param": "diameter"}]}]}, "chamfer": {"mul": [0.004, {"param": "diameter"}]}}}},
      {"id": "frontBearing", "name": "Front bearing", "material": "bronze", "shape": {"tube": {"inner": {"mul": [0.042, {"param": "diameter"}]}, "outer": {"mul": [0.088, {"param": "diameter"}]}, "length": {"mul": [0.04, {"param": "length"}]}, "z0": {"add": [{"mul": [0.06, {"param": "length"}]}, {"mul": [0.26, {"param": "diameter"}]}]}}}},
      {"id": "rearBearing", "name": "Rear bearing", "material": "bronze", "shape": {"tube": {"inner": {"mul": [0.042, {"param": "diameter"}]}, "outer": {"mul": [0.088, {"param": "diameter"}]}, "length": {"mul": [0.04, {"param": "length"}]}, "z0": {"mul": [0.62, {"param": "length"}]}}}},
      {"id": "casing", "name": "Casing", "material": "aluminum", "smooth": 40, "at": [0, 0, {"mul": [0.5, {"param": "length"}]}], "shape": {"revolvedProfile": {"points": [[{"mul": [0.46, {"param": "diameter"}]}, {"mul": [-0.44, {"param": "length"}]}], [{"mul": [0.5, {"param": "diameter"}]}, {"mul": [-0.44, {"param": "length"}]}], [{"mul": [0.5, {"param": "diameter"}]}, {"mul": [0.34, {"param": "length"}]}], [{"mul": [0.46, {"param": "diameter"}]}, {"mul": [0.34, {"param": "length"}]}]], "closed": true, "sweep": {"sub": [360, {"mul": [90, {"param": "cutaway"}]}]}}}}
     ],
     "anchors": {"intake": "intakeLip", "exhaust": "nozzle", "mount": "casing", "input": "shaft", "compressor": "impeller", "turbine": "turbineWheel"},
     "anchorAbout": {
      "intake": "Centre of the intake plane (z = 0) on the engine axis; +Z points downstream, toward the exhaust.",
      "exhaust": "Centre of the nozzle exit (z = length) on the axis; +Z points out of the nozzle, the jet direction.",
      "mount": "Engine axis at mid-length (z = length / 2); world axes of the engine, +Z downstream.",
      "input": "Shaft on the axis; turns about +Z, one turn per input turn.",
      "compressor": "Impeller disc plane on the axis; turns about +Z with the shaft.",
      "turbine": "Turbine wheel on the axis (frame at z = 0); turns about +Z with the shaft."}}
    """#
}
