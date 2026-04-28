#!/usr/bin/env python3
"""Pin the canonical component count across governance docs.

The live UCC manifest tree is the source of truth. Governance docs
(BGS.md, docs/bgs-decision.yaml, docs/biss-classification.md,
docs/bgs-compliance-report.md, docs/setup-state-model.md) must agree.

This test catches the 2026-04-28 audit finding where BGS said 10,
BISS/compliance said 14, and live was 11.
"""
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
UCC = REPO_ROOT / "ucc"

DOCS = [
    REPO_ROOT / "BGS.md",
    REPO_ROOT / "docs" / "bgs-decision.yaml",
    REPO_ROOT / "docs" / "biss-classification.md",
    REPO_ROOT / "docs" / "bgs-compliance-report.md",
    REPO_ROOT / "docs" / "setup-state-model.md",
]


def _live_components() -> set[str]:
    comps = set()
    for f in UCC.rglob("*.yaml"):
        for line in f.read_text().splitlines():
            m = re.match(r"\s*component:\s*(\S+)", line)
            if m:
                comps.add(m.group(1))
    return comps


def test_live_component_count_is_eleven():
    """If this fails, update governance docs to the new count + name set."""
    assert len(_live_components()) == 11, sorted(_live_components())


def test_no_doc_claims_other_counts():
    """Governance docs must not claim 10 or 14 governed components."""
    bad_patterns = [
        re.compile(r"\b10\s+governed\s+components"),
        re.compile(r"\b14\s+governed\s+components"),
        re.compile(r"\b10\s+components\b.*active"),
        re.compile(r"\b14\s+components\b.*active"),
    ]
    offenders = []
    for d in DOCS:
        text = d.read_text()
        for pat in bad_patterns:
            for m in pat.finditer(text):
                offenders.append(f"{d.name}: {m.group(0)!r}")
    assert not offenders, "Stale component counts:\n  " + "\n  ".join(offenders)


if __name__ == "__main__":
    test_live_component_count_is_eleven()
    test_no_doc_claims_other_counts()
    print("PASS")
