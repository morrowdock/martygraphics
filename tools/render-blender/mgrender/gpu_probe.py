# SPDX-License-Identifier: Apache-2.0
"""Run inside Blender: print the Cycles GPU device that render.py would use."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mgrender.device import select_device  # noqa: E402

info = select_device()
print("MG_GPU " + info["summary"], flush=True)
