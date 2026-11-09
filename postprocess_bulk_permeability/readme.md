# Bulk permeability post-processing

`perm_calc_new.m` computes the bulk permeability of the microfluidic device from the pressure and flowrate sensor logs and plots it, normalized by its early peak, for the three main experiments:

| Tag      | Experiment                 | Legend label |
|----------|----------------------------|--------------|
| `cP`     | constant pressure          | cP           |
| `cQhigh` | constant flowrate (high Q) | cQ_high      |
| `cQlow`  | constant flowrate (low Q)  | cQ_low       |

The script finds each experiment's peak permeability, removes all data before the peak, and shifts time so the peak falls at t = 0 h. When biofilm leaves part of the reactor near the inlet uncolonized, the script can correct the permeability so it describes only the colonized zone (see [Clean-zone correction](#clean-zone-correction)). All curves stop when the shortest experiment ends.

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
- **Optional:** add one column that gives the size of the biofilm-free inlet zone (see [Clean-zone correction](#clean-zone-correction)):

  | Column            | Meaning                                              | Example |
  |-------------------|------------------------------------------------------|---------|
  | `clean_fraction`  | clean length ÷ reactor length, from 0 to 1           | 0.333   |
  | `clean_length_mm` | clean length in mm (the script divides it by `L`)    | 5       |

  If neither column exists or the cell is empty, the script sets the clean fraction to 0 (fully colonized reactor) and applies no correction.

  Example offset file:

  | flowrate | pressure_diff | clean_fraction |
  |----------|---------------|----------------|
  | 0.92     | 4.4           | 0.333          |

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
| `CORRECT_CLEAN_ZONE` | `true`    | Correct k for a biofilm-free inlet zone, using the clean fraction from the offset file |
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
8. divides k by k_peak,
9. if `CORRECT_CLEAN_ZONE` is on and the clean fraction f₁ > 0, converts k/k_peak to the permeability of the colonized zone (next section).

The script then cuts every curve at the end time of the shortest experiment and plots the normalized permeability on a log axis.

---

## Clean-zone correction

### Why it is needed

In some experiments, UV treatment at the inlet keeps the reactor section next to the inlet chamber free of biofilm, while biofilm still clogs the rest of the reactor up to the outlet. The bulk permeability from Darcy's law averages over the whole length L, so the clean section makes the reactor look more permeable than its colonized section really is. Without a correction, a reactor with a clean inlet third shows up to 1.5× higher bulk permeability than a fully colonized reactor with the same local clogging. This bias distorts comparisons between experiments with different colonized lengths.

### Derivation

The clean zone (length L₁, permeability k₀) and the colonized zone (length L₂, permeability k_zone) lie in series along the flow path, with L = L₁ + L₂ and the same cross-section A.

1. Darcy's law gives the pressure drop across each zone:

   ΔP₁ = Q μ L₁ / (A k₀)  ΔP₂ = Q μ L₂ / (A k_zone)

2. Mass conservation sends the same Q through both zones, and the sensors measure the total pressure drop, ΔP = ΔP₁ + ΔP₂:

   ΔP = (Q μ / A) · (L₁/k₀ + L₂/k_zone)

3. The script defines the bulk permeability over the full length, ΔP = Q μ L / (A k_bulk). Equating the two expressions cancels Q μ / A and gives the series-resistance relation:

   L / k_bulk = L₁ / k₀ + L₂ / k_zone

4. With f₁ = L₁/L and f₂ = L₂/L = 1 − f₁, solving for the colonized zone gives:

   **k_zone / k₀ = f₂ / (k₀/k_bulk − f₁)**

### How the script applies it

The script uses k_peak as k₀, so k₀/k_bulk = 1/k_norm and

```matlab
k_norm = (1 - f1) ./ (1 ./ k_norm - f1);
```

- k_norm = 1 maps to 1, so every curve still starts at (0 h, 1).
- f₁ = 0 leaves the curve unchanged.
- Under strong clogging (k_bulk ≪ k₀), k_zone/k₀ ≈ f₂ · k_bulk/k₀. With f₁ = ⅓, the colonized zone is about 1.5× less permeable than the bulk value shows.
- If k rises so far above k_peak that the denominator becomes ≤ 0, the script sets that point to NaN.
- The uncorrected curve stays in `results(c).k_norm_bulk`, so you can plot it separately (for example, in the SI).

| Local clogging, k_zone/k₀ | Bulk k/k₀, fully colonized | Bulk k/k₀, clean inlet third (f₁ = ⅓) |
|---------------------------|----------------------------|----------------------------------------|
| 0.1                       | 0.10                       | 0.14                                   |
| 0.01                      | 0.010                      | 0.015                                  |
| 0.001                     | 0.0010                     | 0.0015                                 |

### Assumptions

- Flow is effectively one-dimensional along the reactor, and each zone spans the full width.
- The clean zone keeps the clean-channel permeability k₀ for the whole run.
- The whole channel is clean at the peak, so k_peak represents k₀.
- f₁ is constant in time. If biofilm grows into the inlet zone, a constant f₁ overestimates clogging at later times; in that case, measure f₁ from the images at several time points.

### Output with the correction on

- The y-axis label changes to *k_zone/k_peak* when at least one experiment has f₁ > 0.
- The console prints f₁ and the clean length in mm for each experiment.
- The figure saves under a separate name (see [Output](#output)), so the corrected and bulk figures never overwrite each other.

---

## Output

The script saves two files in `ROOT_PATH`, a PDF (vector) and a TIF (300 dpi):

| `CORRECT_CLEAN_ZONE` | File name |
|----------------------|-----------|
| `false`              | `bulk_permeability_normalized_PNAS.pdf` / `.tif` |
| `true`               | `bulk_permeability_normalized_cleanzone_corrected_PNAS.pdf` / `.tif` |

The figure is 8 × 2.5 in, in the same style as `plot_for_manuscripts_1panels.m`.

---

## Notes and troubleshooting

- **Requirements:** MATLAB R2020a or newer (for `exportgraphics`). If your release rejects the `'Alpha'` option of `yline`, delete that line.
- **`DP_MIN_MBAR` and sensor noise:** the pressure sensor reads in steps of about 0.1 mbar, and its noise is about 0.17 mbar. With the default of 0.1 mbar, noise near ΔP ≈ 0 can still become the peak, especially in `cQlow`, where the clean-channel ΔP is close to the offset. If a peak looks unrealistic, raise the threshold to about 1 mbar.
- **"No valid permeability in the first N h":** ΔP never rose above `DP_MIN_MBAR` within `PEAK_SEARCH_H`. Raise `PEAK_SEARCH_H` or lower `DP_MIN_MBAR`.
- **"No folder containing cP, cQhigh or cQlow":** `ROOT_PATH` points to the wrong folder, or the folder names do not follow the rules above.
- **"Clean-zone fraction must be in [0, 1)":** the `clean_fraction` value is outside 0–1, or `clean_length_mm` is longer than the reactor. Check the units in the offset file.
- **"Pressure/flowrate txt files not recognized":** one of the two `.txt` files is missing, or its name lacks the `__reader_*` / `__ob1_*` part.
- **Reporting:** in the figure caption or Methods, state that t = 0 marks each experiment's peak bulk permeability. The peak times printed in the console give each shift in experiment time. If the clean-zone correction is on, also state that the plotted permeability is corrected for the uncolonized inlet zone.
