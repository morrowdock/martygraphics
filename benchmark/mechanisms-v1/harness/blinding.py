# SPDX-License-Identifier: Apache-2.0
"""Section 8 tokens and sides for mechanisms-v1, with the OQ-09 encoding (AMENDMENTS.md).

- The seed is 32 bytes from the operating system's random source. `BLINDING-SEED.txt` holds it as 64 lowercase hex
  characters (surrounding whitespace is ignored).
- The commitment is the SHA-256 (lowercase hex) of that 64-character hex string as ASCII bytes.
- Every HMAC-SHA256 uses the **32 raw seed bytes** as the key and the **UTF-8 bytes** of the message.
- Output token: the first 12 hex characters of HMAC(seed, "<question id>-r<r>-arm<a>:token").
- Pair token: the first 12 hex characters of HMAC(seed, "<pair id>:pair"), with pair id "<question id>-r<r>".
- Side: Arm 1 is A if the first byte of HMAC(seed, "<pair id>:side") is even, otherwise Arm 1 is B.

The order permutation of section 8 step 4 belongs to the packer and is not used by the scoring.
"""

import hashlib
import hmac
import re


def parse_seed(text):
    """The 32 seed bytes from the 64-character lowercase hex text."""
    value = text.strip()
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ValueError("the seed must be 64 lowercase hex characters")
    return bytes.fromhex(value)


def commitment(seed):
    return hashlib.sha256(seed.hex().encode("ascii")).hexdigest()


def _digest(seed, message):
    if len(seed) != 32:
        raise ValueError("the seed must be 32 bytes")
    return hmac.new(seed, message.encode("utf-8"), hashlib.sha256).digest()


def output_token(seed, question, run, arm):
    return _digest(seed, "%s-r%d-arm%d:token" % (question, run, arm)).hex()[:12]


def pair_token(seed, question, run):
    return _digest(seed, "%s-r%d:pair" % (question, run)).hex()[:12]


def arm_shown_as_a(seed, question, run):
    """1 if Arm 1 is A in this pair's preference packet, else 2."""
    return 1 if _digest(seed, "%s-r%d:side" % (question, run))[0] % 2 == 0 else 2
