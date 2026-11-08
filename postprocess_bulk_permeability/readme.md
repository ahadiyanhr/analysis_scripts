# Bulk permeability post-processing

`perm_calc_new.m` computes the bulk permeability of the microfluidic device from the pressure and flowrate sensor logs and plots it, normalized by its early peak, for the three main experiments:

| Tag      | Experiment                 | Legend label |
|----------|----------------------------|--------------|
| `cP`     | constant pressure          | cP           |
| `cQhigh` | constant flowrate (high Q) | cQ_high      |
| `cQlow`  | constant flowrate (low Q)  | cQ_low       |

The script finds each experiment's peak permeability, removes all data before the peak, and shifts time so the peak falls at t = 0 h. All curves stop when the shortest experiment ends.

---

## Folder structure

Each experiment must sit in **its own folder**, and the folder name must contain the experiment tag. Put all experiment folders under one root folder:

```
ROOT_PATH/
├── 2026-10-01_cP/
│   ├── cP__ob1_pressures.txt
│   ├── cP__reader_flowrate.txt
│   └── cP__sensor_offset.xlsx
├── 2026-10-08_cQhigh/
│   ├── cQ_high__reader_pressures.txt
│   ├── cQ_high__ob1_flowrate.txt
│   └── cQ_high__sensor_offset.xlsx
└── 2026-10-16_cQlow/
    ├── raw_data/sensor_readings/      <- subfolders are fine
    │   ├── cQ_low__reader_pressures.txt
    │   └── cQ_low__ob1_flowrate.txt
    └── logs/
        └── cQ_low__sensor_offset.xlsx
```

The script searches `ROOT_PATH` and all its subfolders, so the files can sit at any depth inside an experiment folder.

### Folder-name rules

- **`cP`** must use this exact case (capital P), and no lowercase letter may follow it. `cP`, `cP_rep1` and `2026_cP` all match; `cPressure` does not.
- **`cQhigh`** and **`cQlow`** ignore case and accept a separator after `cQ`: `cQhigh`, `cQ_high`, `cQ-high` and `cQ high` all match, and so do the `low` versions.
- Keep the tags out of every other folder name under `ROOT_PATH` (for example `cP_backup` or `old_cQlow`). The script treats every matching folder as one experiment.
- Folders inside an experiment folder are not counted as separate experiments, even when their names contain a tag.
- If two folders have the same tag (replicates), both curves are plotted and the legend adds the folder name to the label.

---

## Required files in each experiment folder

The script identifies each file by part of its name, so the text before `__` can be anything.

| Experiment | Pressure file              | Flowrate file             |
|------------|----------------------------|---------------------------|
| cP         | `*__ob1_pressures*.txt`    | `*__reader_flowrate*.txt` |
| cQ         | `*__reader_pressures*.txt` | `*__ob1_flowrate*.txt`    |

The script detects the experiment type from these names: a `__reader_pressures` file means constant flowrate, and a `__reader_flowrate` file means constant pressure. Keep only **one** pressure file and **one** flowrate file in each experiment folder. If there are more, the script uses whichever it finds last and gives no warning.

**Sensor logs (`.txt`)**
- Tab-delimited, one row per second, as exported by the Elveflow software.
- Column 1 holds the timestamp and column 2 the elapsed time in seconds.
- The script reads these columns:

  | Experiment | p1 | p2 | Q |
  |------------|----|----|---|
  | cP         | column 8 of `ob1_pressures` | column 10 of `ob1_pressures` | column 4 of `reader_flowrate` |
  | cQ         | column 4 of `reader_pressures` (HPS Read) | column 6 of `reader_pressures` (LPS Read) | column 8 of `ob1_flowrate` (HFS Read) |

  If your export uses a different column order, edit sections 3 and 4 of the script.

**Offset file (`*offset*.xlsx`)**
- The file name must contain `offset`.
- The file must contain columns named exactly `flowrate` [µL/min] and `pressure_diff` [mbar]. The script uses the first row.
- The script subtracts both offsets from the raw signals. Measure them at zero flow with the device connected.

---

## How to run

1. Put the experiment folders under one root folder, as shown above.
2. In MATLAB, `cd` into that root folder (the script sets `ROOT_PATH = pwd`), or set `ROOT_PATH` to the folder's path at the top of the script.
3. Check the settings below, then run `perm_calc_new.m`.

The console lists the experiment folders it found and prints, for each one, the experiment type, the peak time (in experiment time), k_peak, and the run length after the peak. Check this list before you use the figure.

---

## Settings (top of the script)

| Setting            | Default     | Meaning |
|--------------------|-------------|---------|
| `ROOT_PATH`        | `pwd`       | Folder that holds all experiment folders |
| `SMOOTH_WINDOW`    | 2000        | Moving-average window in samples (about 33 min at 1 Hz) |
| `DP_MIN_MBAR`      | 0.1         | Lowest ΔP (after offset) counted as measurable; below it, k = NaN |
| `PEAK_SEARCH_H`    | 12          | The script searches for the peak only in the first N hours |
| `ZERO_AT_PEAK`     | `true`      | Shift each curve so its peak sits at t = 0 h |
| `REDUCTION_FACTOR` | 10          | Draws a reference line at k/k_peak = 1/N; `[]` hides it |
| `Y_FLOOR`, `Y_TOP` | 1e-4, 1     | Y-axis limits; values below `Y_FLOOR` are drawn on the bottom axis and labeled `<10^-4` |
| `W`, `H`, `L`      | 1 cm, 30 µm, 1.5 cm | Channel width, height and length |
| `MU`               | 8.9e-4 Pa·s | Viscosity of water |
| `TAGS`             | —           | Tag patterns, legend labels, colors, line styles and widths |

---

## Method

For each experiment, the script:

1. subtracts the flowrate and pressure offsets,
2. trims each log to the point where 1-s logging starts,
3. aligns the pressure and flowrate logs on matching timestamps,
4. smooths ΔP and Q with a moving average (`SMOOTH_WINDOW`),
5. computes the Darcy permeability, k = Q μ L / (A ΔP), with A = W H,
6. sets k = NaN where ΔP < `DP_MIN_MBAR` or k ≤ 0,
7. takes the highest k in the first `PEAK_SEARCH_H` hours as k_peak, removes all earlier data, and shifts time so the peak sits at t = 0 h,
8. divides k by k_peak.

The script then cuts every curve at the end time of the shortest experiment and plots k/k_peak on a log axis.

---

## Output

The script saves two files in `ROOT_PATH`:

- `bulk_permeability_normalized_PNAS.pdf` (vector)
- `bulk_permeability_normalized_PNAS.tif` (300 dpi)

The figure is 8 × 2.5 in, in the same style as `plot_for_manuscripts_1panels.m`.

---

## Notes and troubleshooting

- **Requirements:** MATLAB R2020a or newer (for `exportgraphics`). If your release rejects the `'Alpha'` option of `yline`, delete that line.
- **`DP_MIN_MBAR` and sensor noise:** the pressure sensor reads in steps of about 0.1 mbar, and its noise is about 0.17 mbar. With the default of 0.1 mbar, noise near ΔP ≈ 0 can still become the peak, especially in `cQlow`, where the clean-channel ΔP is close to the offset. If a peak looks unrealistic, raise the threshold to about 1 mbar.
- **"No valid permeability in the first N h":** ΔP never rose above `DP_MIN_MBAR` within `PEAK_SEARCH_H`. Raise `PEAK_SEARCH_H` or lower `DP_MIN_MBAR`.
- **"No folder containing cP, cQhigh or cQlow":** `ROOT_PATH` points to the wrong folder, or the folder names do not follow the rules above.
- **"Pressure/flowrate txt files not recognized":** one of the two `.txt` files is missing, or its name lacks the `__reader_*` / `__ob1_*` part.
- **Reporting:** in the figure caption or Methods, state that t = 0 marks each experiment's peak bulk permeability. The peak times printed in the console give each shift in experiment time.
