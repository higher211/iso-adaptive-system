import csv
import json
import sys
from datetime import datetime, timezone

import iri2020
import numpy as np


def _as_utc_datetime(value):
    value = value.replace("Z", "+00:00")
    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _scalar(ds, name):
    if name not in ds:
        return None
    value = np.asarray(ds[name].values).ravel()[0]
    if not np.isfinite(value):
        return None
    return float(value)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: iri2020_profile.py input.json output.csv meta.json")

    input_path, output_path, meta_path = sys.argv[1:]
    with open(input_path, "r", encoding="utf-8") as f:
        req = json.load(f)

    h_km = np.asarray(req["hKm"], dtype=float)
    if h_km.ndim != 1 or h_km.size < 2:
        raise ValueError("hKm must be a one-dimensional array with at least two samples")

    step = float(np.median(np.diff(np.sort(h_km))))
    if not np.isfinite(step) or step <= 0:
        step = 1.0

    ds = iri2020.IRI(
        _as_utc_datetime(req["timeUTC"]),
        [float(np.min(h_km)), float(np.max(h_km)), step],
        float(req["latDeg"]),
        float(req["lonDeg"]),
    )

    alt = np.asarray(ds["alt_km"].values, dtype=float)
    ne = np.asarray(ds["ne"].values, dtype=float)
    ne_req = np.interp(h_km, alt, ne)

    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["hKm", "Ne_m3"])
        writer.writerows(zip(h_km.tolist(), ne_req.tolist()))

    meta = {
        "source": "space-physics iri2020 Python interface",
        "foF2": _scalar(ds, "foF2"),
        "hmF2": _scalar(ds, "hmF2"),
        "NmF2": _scalar(ds, "NmF2"),
        "hmE": _scalar(ds, "hmE"),
        "NmE": _scalar(ds, "NmE"),
        "TEC": _scalar(ds, "TEC"),
        "f107": float(ds.attrs["f107"]) if "f107" in ds.attrs else None,
        "ap": float(ds.attrs["ap"]) if "ap" in ds.attrs else None,
    }
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f)


if __name__ == "__main__":
    main()
