#!/usr/bin/env python3
"""Export ABI and three actual on-chain metadata simulations. Python standard library only.

Run from any directory with Foundry and the pinned solc available. No RPC, keys,
FFI, filesystem cheatcodes, third-party Python modules or deployment required.
Use --check to verify committed exports without rewriting them.
"""

import argparse
import base64
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def forge(*args):
    result = subprocess.run(
        ["forge", *args], cwd=ROOT, text=True, capture_output=True, check=True
    )
    return result.stdout


def decode_uri(uri, prefix):
    if not uri.startswith(prefix):
        raise ValueError(f"Expected {prefix}")
    return base64.b64decode(uri[len(prefix):], validate=True).decode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check committed artifacts without modifying them")
    args = parser.parse_args()
    artifacts = {}
    for contract, output in [
        ("src/SqueekCompanion.sol:SqueekCompanion", "docs/abi/SqueekCompanion.json"),
        ("src/interfaces/ISqueekCore.sol:ISqueekCore", "docs/abi/SqueekCore.reads.json"),
    ]:
        abi = json.loads(forge("inspect", contract, "abi", "--json"))
        artifacts[output] = json.dumps(abi, indent=2) + "\n"

    output = forge("test", "--match-contract", "MetadataTest", "--match-test", "testPreviewMetadata", "-vv", "--color", "never")
    previews = dict(re.findall(r"PREVIEW_(RUNNING|NAPPING|SLEEPING)=(\S+)", output))
    if set(previews) != {"RUNNING", "NAPPING", "SLEEPING"}:
        raise ValueError("The Solidity preview test did not emit all three states")
    images = set()
    markers = {
        "RUNNING": ({"open-eyes", "motion-lines", "wheel"}, "#f8d99c"),
        "NAPPING": ({"closed-eyes", "zzz", "stars"}, "#24365b"),
        "SLEEPING": ({"closed-eyes", "moon", "stars"}, "#10172e"),
    }
    for state, uri in previews.items():
        decoded = decode_uri(uri, "data:application/json;base64,")
        metadata = json.loads(decoded)
        assert metadata["name"] == "_Squeek Companion #100"
        assert len(metadata["attributes"]) == 3
        traits = {a["trait_type"]: a["value"] for a in metadata["attributes"]}
        assert traits == {"state": state, "squeek_block": 42, "mint_block": 20_000_000}
        assert type(traits["squeek_block"]) is int and type(traits["mint_block"]) is int
        svg = decode_uri(metadata["image"], "data:image/svg+xml;base64,")
        tree = ET.fromstring(svg)
        assert tree.tag == "{http://www.w3.org/2000/svg}svg"
        assert tree.attrib["viewBox"] == "0 0 320 360"
        ids = {element.attrib.get("id") for element in tree.iter()}
        required, background = markers[state]
        assert required <= ids
        assert tree[2].attrib["fill"] == background
        assert ">42</text>" in svg
        assert state in svg
        assert "<script" not in svg and "href=" not in svg
        images.add(svg)
        name = state.lower()
        artifacts[f"docs/previews/{name}.svg"] = svg + "\n"
        artifacts[f"docs/previews/{name}.json"] = json.dumps(metadata, indent=2) + "\n"
    assert len(images) == 3, "All states must have different artwork"

    mismatches = []
    for relative, content in artifacts.items():
        path = ROOT / relative
        if args.check:
            if not path.exists() or path.read_text() != content:
                mismatches.append(relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    if mismatches:
        raise SystemExit("Artifacts need regeneration: " + ", ".join(mismatches))
    print(f"{'Checked' if args.check else 'Exported'} {len(artifacts)} ABI/metadata/SVG files; JSON, Base64, XML and three distinct states validated.")


if __name__ == "__main__":
    main()
