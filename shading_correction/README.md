# Shading Correction (Flat-Field)

`shading_correction.m` removes vignetting and uneven illumination from brightfield microscopy tiles. It divides each tile by a smoothed, normalized reference image taken from a blank area of the reactor, so every tile has an even background before stitching or thresholding.

| File | Purpose |
|------|---------|
| `shading_correction.m` | MATLAB script that corrects every tile in a folder and saves the results |
| `ref_image.tif` | Flat-field reference: an image of a blank (empty) area of the reactor, 4000 × 3000 px, 8-bit grayscale |

---

## Requirements

- **MATLAB** with the **Image Processing Toolbox** (`imgaussfilt`, `im2double`).
- A flat-field reference image with the **same pixel size as the tiles**, taken with the same objective, light settings and camera settings.
- Optional: a dark frame (camera shutter closed, same exposure).

---

## How it works

The script corrects each tile with

```
corrected(x,y) = raw(x,y) ./ flat_norm(x,y)
```

and builds `flat_norm` from the reference image in four steps:

1. **Load** the reference and convert it to grayscale if it is RGB.
2. **Subtract the dark frame**, if one is given.
3. **Smooth** the reference with a Gaussian filter (`FLAT_SMOOTH_SIGMA`). Smoothing removes noise, dust and small features from the reference, so only the slow illumination gradient remains.
4. **Normalize** the smoothed reference so its mean equals 1. Because the mean is 1, corrected tiles keep their original overall brightness.

With a dark frame, the correction becomes

```
corrected = (raw - dark) ./ (flat - dark)
```

The script clips the corrected values to [0, 1] and saves each tile at the bit depth of the first tile in the folder (8-bit or 16-bit). RGB tiles are corrected channel by channel with the same grayscale flat field.

---

## Usage

1. Acquire the reference image: move the stage to a blank area of the reactor (no grains, no biomass) and take one brightfield image with the same settings as the experiment. Save it as `ref_image.tif`, or point `FLAT_IMAGE_PATH` to your own file.
2. Open `shading_correction.m` and edit the **USER SETTINGS** block:

   | Setting | Default | Description |
   |---------|---------|-------------|
   | `TILES_DIR` | `''` | Folder with the raw tiles. An empty string means the current MATLAB folder. |
   | `FLAT_IMAGE_PATH` | `'ref_image.tif'` | Path to the flat-field reference. |
   | `DARK_IMAGE_PATH` | `''` | Path to a dark frame. Leave empty if you have none. |
   | `OUTPUT_DIR` | `'tiles_corrected/'` | Output folder. The script creates it if it does not exist. |
   | `TILE_EXT` | `'*.tif'` | File pattern for the tiles (`*.tif`, `*.png`, …). |
   | `FLAT_SMOOTH_SIGMA` | `50` | Gaussian sigma in pixels. Start at about 1/5 of the tile width; set to `0` to skip smoothing. |

3. Run the script. The Command Window reports the flat-field range and each corrected tile, for example:

   ```
   Found 54 tiles to correct.

   Loading flat-field reference: ref_image.tif
     Flat-field range : 0.812 – 1.094  (mean = 1.00)

     [  1/54]  TileScan 1_t00_s00_ch00.tif  →  tiles_corrected/TileScan 1_t00_s00_ch00.tif
     ...
   ```

Corrected tiles keep their original file names, so you can pass `tiles_corrected/` straight to the stitching macros in [`merge_mosaic`](../merge_mosaic/).

---

## Tips

- **Correct only brightfield tiles.** The reference is a brightfield image, so it does not describe the illumination of fluorescence channels. If the export folder holds several channels, narrow `TILE_EXT` (for example, `'*ch00.tif'`) or move the brightfield tiles to their own folder.
- **Check the flat-field range.** A range far from 1 (for example, below 0.5) suggests that the reference contains grains, biomass or debris, or that its settings differ from the tiles.
- **Tune `FLAT_SMOOTH_SIGMA`.** If the corrected tiles still show a bright center or dark corners, the sigma is too large. If they show ghost features from the reference, the sigma is too small.

---

## Known issues

- **The last tile is skipped.** The loop runs `for i = 1 : numel(tile_list)-1`, so the script never corrects the last file in the folder. Change it to `for i = 1 : numel(tile_list)` to process every tile.
- **Tile and reference sizes must match.** The script does not check dimensions; a size mismatch stops MATLAB with an array-size error during division.
- **Mixed bit depths.** The script reads the bit depth from the first tile only and saves every tile at that depth.
