from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    path = Path(sys.argv[1])
    atlas_count = chart_count = output_vertices = output_indices = None
    vertices: dict[int, int] = {}
    indices: list[int] = []
    for line in path.read_text(encoding="ascii").splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "atlas_count":
            atlas_count = int(parts[1])
        elif parts[0] == "chart_count":
            chart_count = int(parts[1])
        elif parts[0] == "mesh":
            output_vertices, output_indices = map(int, parts[3:5])
        elif parts[0] == "vertex":
            vertices[int(parts[1])] = int(parts[3])
        elif parts[0] == "index":
            indices.append(int(parts[2]))

    assert atlas_count == 1 and chart_count == 1
    assert output_vertices == 6 and output_indices == 6
    assert len(vertices) == 6 and len(indices) == 6
    referenced_unatlased = [index for index in indices if vertices[index] == -1]
    referenced_atlased = [index for index in indices if vertices[index] == 0]
    assert len(referenced_unatlased) == 3
    assert len(referenced_atlased) == 3
    print("validated degenerate auto unwrap: valid chart retained and zero-area triangle isolated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
