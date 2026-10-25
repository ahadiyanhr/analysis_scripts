# Optode Calibration

These files calibrate ratiometric oxygen optodes from a set of calibration images. A Fiji macro measures the Green and Red channel intensities inside a fixed ROI, and a MATLAB script fits the Red/Green ratio against dissolved oxygen (DO) with a modified Stern–Volmer model. The script fits each optode on its own and then fits all optodes together with a shared curve shape.

| File | Purpose |
|------|---------|
| `calibrationROI.roi` | Oval ROI (1536 × 1536 px, bounds x = 256–1792, y = 256–1792) used to measure the optode signal |
| `extract_calib_data.ijm` | Fiji macro that measures the ROI on every slice of the open stack |
| `calib_joint_fit.m` | MATLAB script that computes ratios, fits the calibration curves and saves the summary |
| `documentation/calibration_approach.pdf` | Step-by-step notes on the script, its functions and the fitting approach |
| `documentation/Joint model.pdf` | Derivation of the joint model that uses the ratio at the highest O₂ as the reference |

---

## Requirements

- **Fiji** (ImageJ) with Bio-Formats, to open the `.lif` calibration file.
- **MATLAB** with the **Optimization Toolbox** (`fmincon`).
- DO readings for every calibration image, from an independent probe.

---

## 1. Measure the calibration images in Fiji

1. Copy the `optode_calibration` folder into the main calibration-images folder.
2. In Fiji, open *Analyze › Tools › ROI Manager* and load `calibrationROI.roi`.
3. Open the calibration `.lif` file. Choose **Hyperstack** as the view, click **Select All**, then **OK**.
4. Concatenate the series with *Image › Stacks › Tools › Concatenate*. Check **All open windows** and **Open as 4D image**, then click **OK**.
5. Run `extract_calib_data.ijm`. The macro selects the first ROI in the ROI Manager and runs *Measure* on every slice of the active image.
6. In the *Results* window, choose *File › Save* and save the table as `opt##_id##.csv`, where `opt##` is the optode batch and `id##` is the calibration replicate (for example, `opt03_id01.csv`).
7. Open the CSV and type the DO value of each image in **column F**, with `O2` as the header.

The script reads the CSV by **column position**, not by header, so the table must have this layout:

| Column | Content |
|--------|---------|
| C | Mean intensity |
| D | Standard deviation of intensity |
| F | O₂ concentration (typed in by hand) |

and the rows must alternate **Green, Red, Green, Red, …**, so each Green/Red pair is one image. Before you measure, open *Analyze › Set Measurements* and check **Area**, **Mean gray value** and **Standard deviation**, and leave **Display label** off. With these settings Fiji writes the row number in column A, Area in B, Mean in C and StdDev in D. Other settings add or shift columns, and the script then reads the wrong data.

---

## 2. Fit the calibration curves in MATLAB (`calib_joint_fit.m`)

1. Put all `opt##_id##.csv` files of one calibration in the same folder as the script and make it the current MATLAB folder.
2. Run `calib_joint_fit.m`.

The script processes every file that matches `opt*.csv`, in alphabetical order, and uses each file name (without extension) as its label.

### What the script does

**Ratio and uncertainty.** For each Green/Red pair the script computes `R = Red / Green` and propagates the channel standard deviations into the ratio:

```
σR = |R| · sqrt( (σRed / Red)² + (σGreen / Green)² )
```

It drops rows with missing values, non-positive intensities or zero uncertainty, and removes the last row if the row count is odd.

**Replicates.** Images taken at the same O₂ value are combined into one point with an inverse-variance weighted mean. The uncertainty of that point is the standard error of the weighted mean, `sqrt(1 / Σw)`.

**Independent fit.** Each file is fitted with the modified Stern–Volmer model

```
R(C) = R0 · [ α + (1 − α) / (1 + Ksv · C) ]
```

where `R0` is the ratio at zero O₂, `α` is the non-quenchable fraction and `Ksv` is the Stern–Volmer constant. The fit minimizes the weighted sum of squared residuals with `fmincon`, with `0 ≤ α ≤ 1` and `Ksv, R0 ≥ 0`. The script also computes a 95% confidence band at each data point from a numerical Jacobian.

**Joint fit.** All files are then fitted together. The optodes share `α` and `Ksv`, but each file keeps its own reference ratio `Rhigh,f` at its highest O₂ value, `Chigh,f`:

```
R(C) = Rhigh,f · [ α + (1 − α) / (1 + Ksv · C) ] / [ α + (1 − α) / (1 + Ksv · Chigh,f) ]
```

This is the same Stern–Volmer model, rewritten so the reference point is the ratio at the highest O₂ instead of the ratio at zero O₂. The separate `Rhigh,f` absorbs differences in absolute ratio between optodes, while the shared `α` and `Ksv` describe one curve shape for the whole batch. `documentation/Joint model.pdf` gives the full derivation.

### Outputs

- **Command Window:** `α`, `Ksv` and `R0` for each independent fit, and the shared `α`, shared `Ksv` and each `Rhigh` from the joint fit.
- **Figure:** for each file, the weighted data points with error bars, the independent fit at each data point with its 95% confidence whiskers, and the joint fit as a line.
- **CSV:** `calibration_summary_opt##.csv`, with one row per file:

  | Column | Meaning |
  |--------|---------|
  | `Optode` | File label |
  | `alpha_ind`, `Ksv_ind`, `R0_ind` | Independent-fit parameters |
  | `C_high` | Highest O₂ value of that file |
  | `Rhigh_joint` | Joint-fit ratio at `C_high` |
  | `alpha_shared`, `Ksv_shared` | Shared joint-fit parameters |

Move the summary CSV into the `log` folder of the experiment.

---

## Notes and known issues

- **File pattern.** The script looks for `opt*.csv`, but its header comment and error message still mention `results_opt*.csv`. The `opt##_id##.csv` naming above is the one that works.
- **Summary file name.** The script builds the output name from the part of the **first** file's name before `_id`. Every file therefore needs `_id` in its name, and all files in the folder should belong to the same optode batch. A file name without `_id` makes the save step fail.
- **Number of files.** The plot defines eight colors, so the script stops if the folder holds more than eight CSV files. Add rows to `colors` to raise the limit.
- **Units.** The script does not convert units. `Ksv` comes out in the inverse of the units you typed into column F (for example, L/mg if the O₂ values are in mg/L), so use the same units when you apply the calibration to experiment images.
- **Plotted curves.** The fits are evaluated only at the measured O₂ values, so the joint-fit line connects those points rather than drawing a smooth curve.
