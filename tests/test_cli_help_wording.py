#!/usr/bin/env python3
"""Pin user-facing CLI help wording.

PLAN.md "next high-value refactors" #1 — reduce internal-jargon leakage
in user-facing surfaces while keeping governance acronyms (BGS, BISS,
ASM, UCC, UIC, TIC) wherever they label official artifacts.

The `./install.sh --help` text is the most-touched user surface; this
test pins that the visible wording uses plain language ("item" instead
of "target", "set up" instead of "converge", "preflight checks"
instead of "UIC gates") so the next refactor doesn't silently
re-introduce the old vocabulary.
"""
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def _help() -> str:
    r = subprocess.run(
        ["./install.sh", "--help"],
        cwd=REPO, capture_output=True, text=True, timeout=10,
    )
    return r.stdout + r.stderr


class HelpWordingTests(unittest.TestCase):
    def test_help_uses_plain_language(self):
        text = _help()
        # Plain-language vocabulary must be present.
        for word in ("item", "set up", "preflight checks"):
            self.assertIn(word, text, f"missing plain wording: {word!r}")

    def test_help_does_not_leak_internal_jargon(self):
        text = _help()
        # Internal-only terms must not appear in the user-facing help.
        # (Governance acronyms BGS/BISS/ASM/UCC/UIC/TIC are still allowed
        # as official labels but should not appear in the help text.)
        for forbidden in ("converge", "UIC gates", "UIC preference",
                          "UCC_OVERRIDE"):
            self.assertNotIn(forbidden, text,
                             f"jargon leaked to --help: {forbidden!r}")

    def test_help_targets_word_only_in_examples(self):
        # The standalone word "target" is allowed inside example commands
        # (target-overrides.yaml is a real file path) but not as
        # user-facing prose. Cheap proxy: no "target" outside file paths.
        text = _help()
        for line in text.splitlines():
            if "target" in line.lower():
                self.assertTrue(
                    "target-overrides.yaml" in line
                    or "/" in line  # file-path-ish
                    or line.strip().startswith("$0"),
                    f"prose leaks 'target': {line!r}",
                )


if __name__ == "__main__":
    unittest.main()
