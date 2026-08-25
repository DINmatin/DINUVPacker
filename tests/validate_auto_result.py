from __future__ import annotations

import math
import sys
from pathlib import Path


def main() -> int:
    path = Path(sys.argv[1])
    atlas_count = chart_count = input_vertices = output_vertices = output_indices = None
    vertices = []
    indices = []
    for line in path.read_text(encoding="ascii").splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "atlas_count":
            atlas_count = int(parts[1])
        elif parts[0] == "chart_count":
            chart_count = int(parts[1])
        elif parts[0] == "mesh":
            input_vertices, output_vertices, output_indices = map(int, parts[2:5])
        elif parts[0] == "vertex":
            vertices.append((int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]), float(parts[5]), float(parts[6])))
        elif parts[0] == "index":
            indices.append(int(parts[2]))

    assert atlas_count == 1
    assert chart_count is not None and chart_count >= 2
    assert input_vertices == 9
    assert output_vertices is not None and output_vertices > input_vertices
    assert output_indices == 36 and len(indices) == 36
    assert len(vertices) == output_vertices
    assert all(0 <= index < output_vertices for index in indices)
    xref_by_output = {output_index: xref for output_index, xref, *_ in vertices}
    # Each pair of triangles represents one original quad in the Max bridge.
    # Shared corners should normally remain in the same xatlas chart.
    for first_index in range(0, len(indices), 6):
        output_by_xref = {}
        for output_index in indices[first_index:first_index + 6]:
            xref = xref_by_output[output_index]
            if xref in output_by_xref:
                assert output_by_xref[xref] == output_index
            else:
                output_by_xref[xref] = output_index
    referenced_outputs = set(indices)
    saw_unreferenced = False
    for output_index, xref, atlas, chart, u, v in vertices:
        assert 0 <= xref < input_vertices
        if output_index in referenced_outputs:
            assert atlas == 0 and chart >= 0
            assert math.isfinite(u) and math.isfinite(v)
            assert 0.0 <= u <= 1.0 and 0.0 <= v <= 1.0
        else:
            saw_unreferenced = True
            assert atlas == -1 and chart == -1
    print(f"validated auto unwrap: cube generated {chart_count} charts and {output_vertices} UV vertices")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
