from __future__ import annotations

import sys
from collections import defaultdict
from pathlib import Path


def main() -> int:
    path = Path(sys.argv[1])
    chart_points = defaultdict(list)
    chart_count = None
    atlas_count = None
    for line in path.read_text(encoding="ascii").splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "chart_count":
            chart_count = int(parts[1])
        elif parts[0] == "atlas_count":
            atlas_count = int(parts[1])
        elif parts[0] == "vertex":
            chart_points[int(parts[4])].append((float(parts[5]), float(parts[6])))

    assert atlas_count == 1
    assert chart_count == 2
    assert len(chart_points) == 2
    bounds = []
    for points in chart_points.values():
        bounds.append((min(p[0] for p in points), min(p[1] for p in points),
                       max(p[0] for p in points), max(p[1] for p in points)))
    a, b = bounds
    separated = a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1]
    assert separated, f"stacked island chart bounds still overlap: {a} vs {b}"
    print("validated stacked islands: two separate, non-overlapping xatlas charts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
