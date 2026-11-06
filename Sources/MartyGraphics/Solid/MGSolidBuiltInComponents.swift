// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The component definitions shipped with MartyGraphics, as JSON text (Foundation-only, no bundle resources, so the
/// library loads the same way on iOS and macOS). `MGSolidLibrary.builtIn` registers them in this order; a component
/// may only use components listed before it. To add one: write the JSON, check it with
/// `marty-solid component check FILE.json`, then add it here in a reviewed pull request (the tests compile every
/// entry at its defaults).
public enum MGSolidBuiltInComponents {
    public static let sources: [String] = [spurPair, planetaryStage, sliderCrank, propeller, housingBase, shaftWithBearing, fanStage]

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
}
