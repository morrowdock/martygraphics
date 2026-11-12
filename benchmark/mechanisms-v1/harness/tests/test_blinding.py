# SPDX-License-Identifier: Apache-2.0
"""Section 8 tokens and sides (A-09) against fixed test vectors.

The vectors were computed independently of blinding.py with OpenSSL, key = the 32 bytes 00 01 ... 1f:
  printf '%s' 'MECH-01-r1-arm1:token' | openssl dgst -sha256 -mac HMAC -macopt hexkey:000102...1f
and the commitment with  printf '%s' 000102...1f | openssl dgst -sha256
"""

import unittest

import support  # noqa: F401  (puts harness/ on sys.path)
import blinding

SEED_HEX = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
SEED = bytes(range(32))


class BlindingTest(unittest.TestCase):
    def test_seed_and_commitment(self):
        self.assertEqual(blinding.parse_seed(SEED_HEX + "\n"), SEED)
        self.assertEqual(blinding.commitment(SEED), "6c86c6aac5fb24bcf5d9939cb7d7d5645ce39418f449e03b262dd4fa14b4b92b")
        for bad in (SEED_HEX.upper(), SEED_HEX[:-2], SEED_HEX + "00", "zz" * 32):
            with self.assertRaises(ValueError):
                blinding.parse_seed(bad)

    def test_tokens(self):
        self.assertEqual(blinding.output_token(SEED, "MECH-01", 1, 1), "1eeeaa3ddb85")
        self.assertEqual(blinding.output_token(SEED, "MECH-01", 1, 2), "e6c37e2fdd6e")
        self.assertEqual(blinding.output_token(SEED, "MECH-20", 3, 2), "10025130eda5")
        self.assertEqual(blinding.pair_token(SEED, "MECH-01", 1), "5e49746eea03")

    def test_sides(self):
        # First HMAC bytes: 0x18 (even: Arm 1 is A), 0x4e (even), 0x0b (odd: Arm 1 is B).
        self.assertEqual(blinding.arm_shown_as_a(SEED, "MECH-01", 1), 1)
        self.assertEqual(blinding.arm_shown_as_a(SEED, "MECH-07", 2), 1)
        self.assertEqual(blinding.arm_shown_as_a(SEED, "MECH-12", 3), 2)

    def test_key_is_the_raw_bytes(self):
        with self.assertRaises(ValueError):
            blinding.output_token(SEED_HEX.encode("ascii"), "MECH-01", 1, 1)


if __name__ == "__main__":
    unittest.main()
