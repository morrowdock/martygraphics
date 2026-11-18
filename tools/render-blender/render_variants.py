# SPDX-License-Identifier: Apache-2.0
"""Render aspect variants from one verified GLB and manifest."""
import argparse
import os
from pathlib import Path
import subprocess

from mgrender import manifest
from mgrender.ffmpeg import supports_encoder


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--blender", default=os.environ.get("BLENDER", "blender"))
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--preset", choices=("preview", "hero"), default="preview")
    parser.add_argument("--samples", type=int)
    parser.add_argument("--turntable", action="store_true")
    parser.add_argument("--alpha", action="store_true", help="also render a portrait RGBA master")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--busy-wait", type=int)
    parser.add_argument("--no-motion-blur", action="store_true")
    args = parser.parse_args()
    try:
        manifest.verify(args.manifest)
    except (manifest.ExportError, OSError, ValueError, KeyError) as exc:
        parser.exit(1, f"export refused: {exc}\n")
    if not supports_encoder(args.ffmpeg, "h264_nvenc"):
        parser.exit(1, f"NVENC unavailable: {args.ffmpeg} must expose the h264_nvenc encoder\n")
    render = Path(__file__).with_name("render.py").resolve()
    command = [args.blender, "-b", "--factory-startup", "-P", str(render), "--", str(args.manifest.resolve())]
    options = ["--preset", args.preset, "--camera", "auto", "--no-burn-in", "--ffmpeg", args.ffmpeg]
    for value, flag in ((args.samples, "--samples"), (args.busy_wait, "--busy-wait")):
        if value is not None:
            options.extend([flag, str(value)])
    for enabled, flag in ((args.turntable, "--turntable"), (args.resume, "--resume"),
                          (args.no_motion_blur, "--no-motion-blur")):
        if enabled:
            options.append(flag)
    variants = [("16x9", "1080p", "--nvenc"), ("1x1", "1:1", "--nvenc"), ("9x16", "9:16", "--nvenc")]
    if args.alpha:
        variants.append(("alpha", "9:16", "--alpha"))
    for name, resolution, output_flag in variants:
        result = subprocess.run(command + [str(args.out.resolve() / name), "--resolution", resolution,
                                           output_flag] + options)
        if result.returncode:
            return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
