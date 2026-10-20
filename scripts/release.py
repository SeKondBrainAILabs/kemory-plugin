#!/usr/bin/env python3
"""Changelog fragments: each PR adds changes/<topic>.md instead of editing
CHANGELOG.md, so two open PRs never conflict over the same lines.

  python3 scripts/release.py --check     validate the fragments (check.sh runs this)
  python3 scripts/release.py X.Y.Z       fold them into CHANGELOG.md as ## [X.Y.Z],
                                         bump every manifest, delete the fragments

A fragment is one or more "### <Category>" headings, each followed by its
bullets, written exactly as they should read in the changelog.
"""
import argparse
import datetime
import json
import pathlib
import re
import sys

# The order sections appear in within a release.
CATEGORIES = ("Upgrading", "Added", "Changed", "Fixed", "Removed", "Notes")
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
MANIFESTS = (
    "plugin/.claude-plugin/plugin.json",
    "plugin/.grok-plugin/plugin.json",
    "plugins/cursor/.cursor-plugin/plugin.json",
)
MARKETPLACES = (".claude-plugin/marketplace.json", ".cursor-plugin/marketplace.json")


def fragments(root):
    return sorted(p for p in (root / "changes").glob("*.md") if p.name != "README.md")


def parse(path):
    """Return {category: [lines]} for one fragment, or raise ValueError."""
    sections, current = {}, None
    for n, line in enumerate(path.read_text().splitlines(), 1):
        heading = re.match(r"^#+\s*(.*?)\s*$", line)
        if heading:
            if not line.startswith("### ") or heading.group(1) not in CATEGORIES:
                raise ValueError(f"{path.name}:{n}: expected '### <{'|'.join(CATEGORIES)}>', got {line!r}")
            current = sections.setdefault(heading.group(1), [])
        elif current is None:
            if line.strip():
                raise ValueError(f"{path.name}:{n}: text before the first '### <Category>' heading")
        else:
            current.append(line)
    if not sections:
        raise ValueError(f"{path.name}: no '### <Category>' heading")
    for category, lines in sections.items():
        if not any(l.startswith("- ") for l in lines):
            raise ValueError(f"{path.name}: '### {category}' has no '- ' bullet")
    return {c: "\n".join(lines).strip("\n") for c, lines in sections.items()}


def check(root):
    errors = []
    for path in fragments(root):
        try:
            parse(path)
        except ValueError as e:
            errors.append(str(e))
    # A hand-written section here is what the fragments replace, and the
    # release would publish it under the wrong heading.
    if re.search(r"^## \[Unreleased\]", (root / "CHANGELOG.md").read_text(), re.M):
        errors.append("CHANGELOG.md has an [Unreleased] section; put the entry in changes/<topic>.md")
    return errors


def key(version):
    return tuple(int(x) for x in version.split("."))


def release(root, version, date):
    errors = check(root)
    if errors:
        raise SystemExit("\n".join(errors))
    if not VERSION.match(version):
        raise SystemExit(f"version {version!r} is not X.Y.Z")
    current = json.loads((root / MANIFESTS[0]).read_text())["version"]
    if key(version) <= key(current):
        raise SystemExit(f"version {version} is not past the current {current}")
    paths = fragments(root)
    if not paths:
        raise SystemExit("no fragments in changes/; nothing to release")

    merged = {}
    for path in paths:
        for category, text in parse(path).items():
            merged.setdefault(category, []).append(text)
    body = "\n\n".join(
        f"### {c}\n" + "\n".join(merged[c]) for c in CATEGORIES if c in merged
    )

    changelog = root / "CHANGELOG.md"
    text = changelog.read_text()
    first = re.search(r"^## \[", text, re.M)
    at = first.start() if first else len(text)
    section = f"## [{version}] — {date}\n\n{body}\n\n"
    changelog.write_text(text[:at] + section + text[at:])

    # Every host reads its own manifest and gates updates on the version
    # string, so all of them move together.
    for rel in MANIFESTS:
        bump(root / rel, lambda d: d.__setitem__("version", version))

    def bump_entry(d):
        for entry in d["plugins"]:
            if entry["name"] == "kemory":
                entry["version"] = version

    for rel in MARKETPLACES:
        bump(root / rel, bump_entry)
    for path in paths:
        path.unlink()
    return [p.name for p in paths]


def bump(path, change):
    data = json.loads(path.read_text())
    change(data)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("version", nargs="?")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--date", default=datetime.date.today().isoformat())
    parser.add_argument("--root", default=pathlib.Path(__file__).resolve().parent.parent, type=pathlib.Path)
    args = parser.parse_args()
    if args.check:
        errors = check(args.root)
        print("\n".join(errors) if errors else f"{len(fragments(args.root))} fragment(s) ok")
        return 1 if errors else 0
    if not args.version:
        parser.error("give a version, or --check")
    used = release(args.root, args.version, args.date)
    print(f"{args.version}: folded {', '.join(used)} into CHANGELOG.md and bumped the manifests")
    return 0


if __name__ == "__main__":
    sys.exit(main())
