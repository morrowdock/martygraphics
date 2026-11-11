# SPDX-License-Identifier: Apache-2.0
"""Synthetic validation of the graders' temporal evidence (mechanisms-v1).

Python standard library only. Deterministic.

The grader evidence is a frame strip: every 3rd frame of the 30 fps video (10 fps), drawn as 256 x 160 thumbnails
(1/5 scale) in labelled contact sheets. This script renders synthetic mechanisms at 30 fps, keeps ONLY the strip
frames, and recovers each answer from those pixels alone:

  V1 rotation direction   (a disk with one marker, and a 4-arm cross, at several rates; negative controls beyond the cap)
  V2 valve timing         (a crank marker and a valve that opens during the intake half-turn of every second turn)
  V3 Geneva dwell         (exact external Geneva kinematics, n = 4 and n = 6)
  V4 short flicker        (a block missing for 1, 2, 3, 6 or 15 video frames, at every phase)

Usage:
  python3 temporal_evidence.py RESULTS.json [PACKET_DIR]

With PACKET_DIR, it also writes the grader validation packets (PNG contact sheets per case, PROMPT.txt, KEY.json).
"""

import json
import math
import struct
import sys
import zlib
from pathlib import Path

FPS = 30
STRIP_STEP = 3                 # every 3rd frame: 10 fps
W, H = 256, 160                # thumbnail size (1/5 of 1280 x 800)
BG, FG, MARK = 24, 210, 60     # grey levels
LABEL_H = 14
COLS, ROWS = 5, 5


# --------------------------------------------------------------------------- drawing

def blank():
    return [bytearray([BG]) * W for _ in range(H)]


def disk(img, cx, cy, r, v):
    r2 = r * r
    for y in range(max(0, int(cy - r)), min(H, int(cy + r) + 2)):
        dy = y + 0.5 - cy
        row = img[y]
        for x in range(max(0, int(cx - r)), min(W, int(cx + r) + 2)):
            dx = x + 0.5 - cx
            if dx * dx + dy * dy <= r2:
                row[x] = v


def rect(img, x0, y0, x1, y1, v):
    for y in range(max(0, int(y0)), min(H, int(y1))):
        row = img[y]
        for x in range(max(0, int(x0)), min(W, int(x1))):
            row[x] = v


def arms(img, cx, cy, r_in, r_out, angle_deg, k, half_width_deg, v):
    """k radial arms (a marker when k = 1). Angles are in screen degrees, counterclockwise positive (y up)."""
    for y in range(max(0, int(cy - r_out)), min(H, int(cy + r_out) + 2)):
        dy = cy - (y + 0.5)
        row = img[y]
        for x in range(max(0, int(cx - r_out)), min(W, int(cx + r_out) + 2)):
            dx = x + 0.5 - cx
            rr = math.hypot(dx, dy)
            if rr < r_in or rr > r_out:
                continue
            phi = math.degrees(math.atan2(dy, dx))
            rel = (phi - angle_deg) % (360.0 / k)
            if rel <= half_width_deg or rel >= 360.0 / k - half_width_deg:
                row[x] = v


# --------------------------------------------------------------------------- measuring (from pixels only)

def orientation(img, cx, cy, r_in, r_out, k, v):
    """Orientation (degrees, counterclockwise) of pixels with value v in an annulus, modulo 360 / k."""
    sx = sy = 0.0
    n = 0
    for y in range(max(0, int(cy - r_out)), min(H, int(cy + r_out) + 2)):
        dy = cy - (y + 0.5)
        row = img[y]
        for x in range(max(0, int(cx - r_out)), min(W, int(cx + r_out) + 2)):
            if row[x] != v:
                continue
            dx = x + 0.5 - cx
            rr = math.hypot(dx, dy)
            if rr < r_in or rr > r_out:
                continue
            phi = math.atan2(dy, dx) * k
            sx += math.cos(phi)
            sy += math.sin(phi)
            n += 1
    if n == 0:
        return None
    return (math.degrees(math.atan2(sy, sx)) / k) % (360.0 / k)


def steps(angles, period):
    """Minimal signed displacement between consecutive orientations, in (-period/2, period/2]."""
    out = []
    for a, b in zip(angles, angles[1:]):
        d = (b - a) % period
        if d > period / 2:
            d -= period
        out.append(d)
    return out


def judge_direction(angles, period):
    """counterclockwise, clockwise or cannot judge (more than 20 % of moving steps near half a period)."""
    d = [x for x in steps(angles, period) if abs(x) > 0.5]
    if not d:
        return "cannot judge", 0.0
    ambiguous = sum(1 for x in d if abs(x) > 0.45 * period)
    if ambiguous > 0.2 * len(d):
        return "cannot judge", ambiguous / len(d)
    pos = sum(1 for x in d if x > 0)
    return ("counterclockwise" if pos > len(d) / 2 else "clockwise"), ambiguous / len(d)


# --------------------------------------------------------------------------- cases

def strip_frames(seconds):
    return list(range(0, int(round(seconds * FPS)), STRIP_STEP))


def case_rotation(rate_rev_s, ccw, k, seconds=6.0):
    sign = 1 if ccw else -1
    frames = strip_frames(seconds)
    imgs, angles = [], []
    for f in frames:
        t = f / FPS
        a = sign * 360.0 * rate_rev_s * t + 17.0
        img = blank()
        disk(img, 128, 80, 60, FG)
        if k == 1:
            arms(img, 128, 80, 20, 55, a, 1, 14, MARK)
        else:
            arms(img, 128, 80, 8, 55, a, k, 7, MARK)
        imgs.append((t, img))
        angles.append(orientation(img, 128, 80, 8 if k > 1 else 20, 55, k, MARK))
    period = 360.0 / k
    per_sample = 360.0 * rate_rev_s * STRIP_STEP / FPS
    verdict, amb = judge_direction(angles, period)
    truth = "counterclockwise" if ccw else "clockwise"
    within_cap = per_sample <= period / 4 + 1e-9
    res = {
        "truth": truth, "measured": verdict, "ambiguousShare": round(amb, 3),
        "degreesPerStripFrame": round(per_sample, 2), "repeatPeriodDegrees": period,
        "within4x": within_cap,
    }
    if within_cap:
        res["pass"] = verdict == truth
    else:
        # Negative control: no pass/fail. It records what the evidence shows beyond the 4x rule.
        res["pass"] = None
        res["outcome"] = ("correct" if verdict == truth else "cannot judge" if verdict == "cannot judge"
                          else "WRONG direction (aliasing)")
    return res, imgs


def case_valve(rate_rev_s, seconds=16.0):
    """Valve open while the crank is in [0, 180) degrees of every even turn (an intake half-turn)."""
    frames = strip_frames(seconds)
    imgs, crank, opened = [], [], []
    for f in frames:
        t = f / FPS
        a = 360.0 * rate_rev_s * t + 13.0              # crank angle, counterclockwise; 13 degrees off the samples
        cycle = a % 720.0
        is_open = cycle < 180.0
        img = blank()
        disk(img, 80, 80, 50, FG)
        arms(img, 80, 80, 15, 46, a, 1, 14, MARK)
        rect(img, 180, 30 + (24 if is_open else 0), 200, 70 + (24 if is_open else 0), FG)   # valve stem
        imgs.append((t, img))
        crank.append(orientation(img, 80, 80, 15, 46, 1, MARK))
        # measured valve state: is the stem's bottom low?
        opened.append(img[85][190] == FG)
    # unwrap the measured crank angle
    unwrapped = [crank[0]]
    for d in steps(crank, 360.0):
        unwrapped.append(unwrapped[-1] + d)
    starts, ends = [], []
    for i in range(1, len(opened)):
        if opened[i] and not opened[i - 1]:
            starts.append(unwrapped[i] % 720.0)
        if opened[i - 1] and not opened[i]:
            ends.append(unwrapped[i] % 720.0)
    # An opening already in progress at t = 0 has no observed start, so it is not counted.
    per_sample = 360.0 * rate_rev_s * STRIP_STEP / FPS

    def err(x, target):
        # A crank marker repeats every turn, so the phase is compared modulo 360 degrees; which turn of the
        # two-turn cycle is open comes from the count of openings (one per two turns).
        d = (x - target) % 360.0
        return min(d, 360.0 - d)

    open_err = max((err(s, 0.0) for s in starts), default=None)
    close_err = max((err(e, 180.0) for e in ends), default=None)
    cycles = len(starts)
    end_angle = 360.0 * rate_rev_s * (frames[-1] / FPS) + 13.0   # crank angle at the last strip frame
    expected_cycles = sum(1 for c in range(0, 100) if 13.0 < 720.0 * c <= end_angle)
    ok = (open_err is not None and close_err is not None and open_err <= per_sample + 1.0
          and close_err <= per_sample + 1.0 and cycles == expected_cycles)
    return {
        "truth": "opens at crank 0 degrees, closes at 180 degrees, once every two crank turns",
        "measuredOpenErrorDegrees": None if open_err is None else round(open_err, 1),
        "measuredCloseErrorDegrees": None if close_err is None else round(close_err, 1),
        "openingsSeen": cycles, "openingsExpected": expected_cycles,
        "crankDegreesPerStripFrame": round(per_sample, 2), "pass": ok,
    }, imgs


def geneva_star_angle(alpha_deg, n):
    """Star rotation (degrees, positive = same sense as the driver's alpha) for one external Geneva cycle.

    alpha is the driver angle from the line of centres, wrapped to (-180, 180]. The star turns only while
    |alpha| <= 90 - 180/n. Returns the star's progress in this cycle, from -180/n to +180/n.
    """
    half = 90.0 - 180.0 / n
    r = math.sin(math.pi / n)
    if alpha_deg < -half:
        return -180.0 / n
    if alpha_deg > half:
        return 180.0 / n
    a = math.radians(alpha_deg)
    return math.degrees(math.atan2(r * math.sin(a), 1.0 - r * math.cos(a)))


def case_geneva(n, driver_rev_s=0.25, seconds=16.0):
    frames = strip_frames(seconds)
    imgs, drv, star = [], [], []
    for f in frames:
        t = f / FPS
        a_total = 360.0 * driver_rev_s * t - 90.0          # driver angle, counterclockwise; starts mid-dwell
        cycles = math.floor((a_total + 180.0) / 360.0)
        alpha = a_total - 360.0 * cycles                    # in (-180, 180]
        star_progress = cycles * (360.0 / n) + geneva_star_angle(alpha, n) + 180.0 / n
        star_angle = -star_progress + 10.0                   # external Geneva: opposite sense
        img = blank()
        disk(img, 70, 80, 45, FG)
        arms(img, 70, 80, 12, 42, a_total, 1, 12, MARK)     # driver pin marker
        disk(img, 185, 80, 55, FG)
        arms(img, 185, 80, 8, 52, star_angle, n, 6, MARK)   # star slots as n arms
        imgs.append((t, img))
        drv.append(orientation(img, 70, 80, 12, 42, 1, MARK))
        star.append(orientation(img, 185, 80, 8, 52, n, MARK))
    dd = steps(star, 360.0 / n)
    moving = [abs(x) > 0.05 for x in dd]     # dwell frames are pixel-identical, so their displacement is 0
    motion_share = sum(moving) / len(moving)
    truth_share = (180.0 - 360.0 / n) / 360.0
    # step size: sum of displacement over each run of motion
    runs, cur = [], 0.0
    for m, x in zip(moving, dd):
        if m:
            cur += x
        elif cur:
            runs.append(cur)
            cur = 0.0
    full_runs = [abs(x) for x in runs[1:]] if len(runs) > 1 else [abs(x) for x in runs]
    step_ok = all(abs(x - 360.0 / n) <= 3.0 for x in full_runs) and len(full_runs) > 0
    drv_dir, _ = judge_direction(drv, 360.0)
    star_dir, star_amb = judge_direction(star, 360.0 / n)
    opposite = {drv_dir, star_dir} == {"clockwise", "counterclockwise"}
    tol = (STRIP_STEP / FPS) * driver_rev_s * 1.0 + 0.02
    peak = 360.0 * driver_rev_s * (math.sin(math.pi / n) / (1 - math.sin(math.pi / n))) * STRIP_STEP / FPS
    return {
        "truth": "step %.0f degrees per driver turn, motion share %.3f, star turns opposite to the driver" % (360.0 / n, truth_share),
        "measuredMotionShare": round(motion_share, 3), "tolerance": round(tol, 3),
        "measuredSteps": [round(x, 1) for x in full_runs],
        "driverDirection": drv_dir, "starDirection": star_dir, "starAmbiguousShare": round(star_amb, 3),
        "starPeakDegreesPerStripFrame": round(peak, 2), "starRepeatPeriodDegrees": 360.0 / n,
        "within4x": peak <= (360.0 / n) / 4 + 1e-9,
        "pass": abs(motion_share - truth_share) <= tol and step_ok and opposite,
    }, imgs


def case_flicker(missing_frames, offset, seconds=4.0):
    start = 45 + offset                                         # video frame where the block disappears
    frames = strip_frames(seconds)
    imgs, seen_gap = [], False
    for f in frames:
        t = f / FPS
        img = blank()
        present = not (start <= f < start + missing_frames)
        if present:
            rect(img, 100, 50, 156, 110, FG)
        imgs.append((t, img))
        if img[80][128] != FG:
            seen_gap = True
    expected = missing_frames >= STRIP_STEP
    return {
        "truth": "block missing for %d video frame(s) (%.3f s) from frame %d" % (missing_frames, missing_frames / FPS, start),
        "gapSeenInStrip": seen_gap, "guaranteed": expected,
        # Shorter than one strip step (0.1 s): out of scope; recorded as a control, not scored.
        "pass": seen_gap if expected else None,
        **({} if expected else {"outcome": "seen" if seen_gap else "not seen"}),
    }, imgs


# --------------------------------------------------------------------------- PNG contact sheets

FONT = {  # 3 x 5 bitmap font
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
    "8": "111101111101111", "9": "111101111001111", ".": "000000000000010", "t": "010111010010011",
    "=": "000111000111000", "s": "011100010001110", " ": "000000000000000",
}


def text(sheet, sw, x0, y0, s, scale=2, v=235):
    x = x0
    for ch in s:
        bits = FONT[ch]
        for j in range(5):
            for i in range(3):
                if bits[j * 3 + i] == "1":
                    for yy in range(scale):
                        for xx in range(scale):
                            sheet[(y0 + j * scale + yy) * sw + x + i * scale + xx] = v
        x += 4 * scale


def png(path, width, height, gray):
    raw = b"".join(b"\x00" + bytes(gray[y * width:(y + 1) * width]) for y in range(height))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    Path(path).write_bytes(data)


def sheets(imgs, folder):
    folder.mkdir(parents=True, exist_ok=True)
    per = COLS * ROWS
    sw, sh = COLS * W, ROWS * (H + LABEL_H)
    names = []
    for s in range(0, len(imgs), per):
        sheet = bytearray([0]) * (sw * sh)
        for i, (t, img) in enumerate(imgs[s:s + per]):
            cx, cy = (i % COLS) * W, (i // COLS) * (H + LABEL_H)
            for y in range(H):
                sheet[(cy + y) * sw + cx:(cy + y) * sw + cx + W] = img[y]
            text(sheet, sw, cx + 4, cy + H + 2, "t=%.2f s" % t)
        name = "sheet-%02d.png" % (s // per + 1)
        png(folder / name, sw, sh, sheet)
        names.append(name)
    return names


# --------------------------------------------------------------------------- main

def main(argv):
    if len(argv) not in (1, 2):
        print(__doc__)
        return 2
    out = Path(argv[0])
    packet_dir = Path(argv[1]) if len(argv) == 2 else None
    results, packets = [], []

    def add(group, cid, params, res_imgs, question=None, answer=None, accept=None, in_scope=True):
        res, imgs = res_imgs
        results.append({"group": group, "id": cid, "params": params, **res})
        if packet_dir is not None and question:
            names = sheets(imgs, packet_dir / cid)
            packets.append({"id": cid, "inScope": in_scope, "sheets": names, "question": question,
                            "answer": answer, "accept": accept or [answer]})

    rot_q = ("The large light disk carries a dark marker (or dark arms). Seen as drawn, does the disk turn "
             "clockwise or counterclockwise? Answer clockwise, counterclockwise or cannot judge.")
    for rate in (0.25, 1.0, 2.5):
        for ccw in (True, False):
            cid = "V1-marker-%sr-%s" % (rate, "ccw" if ccw else "cw")
            r = case_rotation(rate, ccw, 1)
            add("V1 rotation direction", cid, {"revPerSecond": rate, "k": 1}, r, rot_q, r[0]["truth"])
    for rate in (0.25, 0.6):
        cid = "V1-cross-%sr-ccw" % rate
        r = case_rotation(rate, True, 4)
        add("V1 rotation direction", cid, {"revPerSecond": rate, "k": 4}, r, rot_q, r[0]["truth"])
    for rate, k in ((5.0, 1), (6.0, 1), (2.0, 4)):
        cid = "V1-control-beyond-cap-%sr-k%d" % (rate, k)
        r = case_rotation(rate, True, k)
        add("V1 rotation direction (negative control: beyond the cap)", cid, {"revPerSecond": rate, "k": k}, r,
            rot_q, "cannot judge", ["cannot judge", "counterclockwise"], in_scope=False)

    valve_q = ("The left disk is a crank with a dark marker (angle 0 = marker pointing right; it turns counterclockwise). "
               "The bar on the right is a valve: low means open. At which crank angle does the valve open and at which "
               "does it close, and how many crank turns are there per opening? Answer as: open <deg>, close <deg>, "
               "turns per opening <n>; or cannot judge.")
    for rate in (0.25, 1.0):
        cid = "V2-valve-%sr" % rate
        add("V2 valve timing", cid, {"crankRevPerSecond": rate}, case_valve(rate), valve_q,
            "open 0, close 180, turns per opening 2")

    gen_q = ("Left: a driver disk with a dark pin marker. Right: a slotted wheel (dark arms). Does the slotted wheel "
             "stop and go? If yes: how many degrees does it turn per driver turn, what share of the time does it move, "
             "and does it turn the same way as the driver or the opposite way? Or answer cannot judge.")
    for n in (4, 6):
        cid = "V3-geneva-n%d" % n
        r = case_geneva(n)
        add("V3 Geneva dwell", cid, {"slots": n, "driverRevPerSecond": 0.25}, r, gen_q,
            "stop and go, %d degrees per driver turn, moves %.0f %% of the time, opposite way"
            % (360 // n, 100 * (180.0 - 360.0 / n) / 360.0))

    fl_q = "Does the light block disappear at any time? If yes, at what time (seconds)? Or answer cannot judge."
    for k in (1, 2, 3, 6, 15):
        for off in range(STRIP_STEP):
            cid = "V4-flicker-%df-o%d" % (k, off)
            r = case_flicker(k, off)
            want_packet = off == 1 or k >= 3
            ans = ("yes, at about %.1f s" % ((45 + off) / FPS)) if r[0]["gapSeenInStrip"] else "no (gap not in the evidence)"
            add("V4 short flicker", cid, {"missingVideoFrames": k, "phase": off}, r,
                fl_q if want_packet else None, ans, in_scope=k >= STRIP_STEP)

    summary = {}
    for r in results:
        g = summary.setdefault(r["group"], {"cases": 0, "pass": 0, "controls": 0})
        if r["pass"] is None:
            g["controls"] += 1
            continue
        g["cases"] += 1
        g["pass"] += 1 if r["pass"] else 0
    doc = {
        "kind": "martygraphics.benchmark.temporal-validation/1",
        "benchmark": "mechanisms-v1",
        "evidence": {"videoFps": FPS, "stripFps": FPS / STRIP_STEP, "thumbnail": [W, H], "sheet": [COLS, ROWS],
                     "rule": "adequate when a visible feature moves at most 1/4 of its repeat period between strip frames"},
        "summary": summary,
        "allPass": all(r["pass"] for r in results if r["pass"] is not None),
        "cases": results,
    }
    out.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    if packet_dir is not None:
        key = {"scoring": {"pass": "at least 90 % of inScope packets correct and no wrong direction on an inScope rotation packet; "
                                   "cannot judge on an inScope packet is not correct; packets with inScope false are reported, not scored",
                           "tolerance": {"valveDegrees": 45, "genevaSharePoints": 10, "genevaStepDegrees": 10, "flickerSeconds": 0.2}},
               "packets": packets}
        (packet_dir / "KEY.json").write_text(json.dumps(key, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary), "allPass:", doc["allPass"])
    return 0 if doc["allPass"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
