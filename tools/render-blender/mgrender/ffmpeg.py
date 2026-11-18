# SPDX-License-Identifier: Apache-2.0
"""Blender-free ffmpeg encoder discovery."""
import subprocess


def supports_encoder(ffmpeg, encoder):
    try:
        result = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return False
    return any(line.split()[1:2] == [encoder] for line in result.stdout.splitlines())
