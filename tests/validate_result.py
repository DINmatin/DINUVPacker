from __future__ import annotations

import math
import sys
from pathlib import Path


def parse(path: Path):
    vertices = {}
    indices = []
    scalars = {}
    for raw_line in path.read_text(encoding="ascii").splitlines():
        parts = raw_line.split()
        if not parts:
            continue
        if parts[0] in {"atlas_width", "atlas_height", "atlas_count", "chart_count", "mesh_count"}:
            scalars[parts[0]] = int(parts[1])
        elif parts[0] == "vertex":
            output_index = int(parts[1])
            vertices[output_index] = {
                "xref": int(parts[2]),
                "atlas": int(parts[3]),
                "chart": int(parts[4]),
                "u": float(parts[5]),
                "v": float(parts[6]),
            }
        elif parts[0] == "index":
            indices.append(int(parts[2]))
    return scalars, vertices, indices


def main() -> int:
    path = Path(sys.argv[1])
    scalars, vertices, indices = parse(path)
    assert scalars["atlas_count"] == 1
    assert scalars["mesh_count"] == 1
    assert scalars["chart_count"] == 2
    assert scalars["atlas_width"] > 0 and scalars["atlas_height"] > 0
    assert len(vertices) == 8
    assert len(indices) == 12
    assert {entry["xref"] for entry in vertices.values()} == set(range(8))
    assert {entry["chart"] for entry in vertices.values()} == {0, 1}
    for entry in vertices.values():
        assert entry["atlas"] == 0
        assert math.isfinite(entry["u"]) and math.isfinite(entry["v"])
        assert 0.0 <= entry["u"] <= 1.0
        assert 0.0 <= entry["v"] <= 1.0
    assert all(index in vertices for index in indices)
    print("validated two islands: one atlas, two charts, finite normalized UVs, complete xref/index mapping")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
