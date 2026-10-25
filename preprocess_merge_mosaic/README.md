# Merge Mosaic (Tile Stitching)

These two Fiji macros rebuild full-chip mosaic images from the individual tiles of a Leica tile scan. Step 1 stacks all channels of each tile (two, three or more), and Step 2 stitches the stacked tiles of each time point into one image per channel.

| Step | Macro | Input | Output |
|------|-------|-------|--------|
| 1 | `step01_stack_channels.ijm` | Exported tiles, one TIFF per channel (`ch00`, `ch01`, `ch02`, …) | One stack per tile (one slice per channel), in `Stacked_Tiles/` |
| 2 | `step02_stitch_stacked_tiles.ijm` | `Stacked_Tiles/` | One stitched TIFF per channel and time point, in `Stacked_Tiles/Stitched/` |

---

## Requirements

- **Leica LAS X** to export the tiles from the `.lif` project file.
- **Fiji** with the *Grid/Collection stitching* plugin (Plugins › Stitching), which ships with Fiji by default.

---

## 1. Export the tiles from the `.lif` project (Leica LAS X)

The stitching runs in Fiji, so LAS X must export the raw tiles, not the merged mosaic.

1. Open the `.lif` project file in LAS X and select the **TileScan** you want to process in the *Open Projects* panel.
2. Do **not** run *Mosaic Merge* in LAS X. If the project already contains a merged image, select the original (non-merged) TileScan instead.
3. Right-click the TileScan and choose **Export** (or *File › Export*). Set the format to **TIFF** and export **single images**, so that each tile, time point and channel becomes its own file.
4. Export into an empty folder, for example `raw_data/images/<experiment>_tiles/`.

The exported files should look like this:

```
TileScan 1_t00_s00_ch00.tif
TileScan 1_t00_s00_ch01.tif
TileScan 1_t00_s00_ch02.tif
TileScan 1_t00_s01_ch00.tif
TileScan 1_t00_s01_ch01.tif
TileScan 1_t00_s01_ch02.tif
...
TileScan 1_t05_s08_ch02.tif
```

Here `t##` is the time point, `s##` is the tile (position) index starting at 0, and `ch##` is the channel. Both macros rely on these tags, so do not rename the files. The tags must be separated from the rest of the name by `_`, a space, or `-`.

> The exact menu names in the LAS X export dialog differ between LAS X versions. What matters is the result: one TIFF per tile and channel, with the `t`, `s` and `ch` tags in the file names.

---

## 2. Stack the channels of each tile (`step01_stack_channels.ijm`)

1. In Fiji, open the macro with *Plugins › Macros › Run…* (or drag it onto the Fiji bar and click **Run**).
2. Choose the folder with the exported tiles.

For every `*ch00*.tif`, the macro finds the matching `ch01`, `ch02`, … files (same name, only the channel number changes), stacks them in channel order (slice 1 = `ch00`, slice 2 = `ch01`, slice 3 = `ch02`, …) and saves the stack in a `Stacked_Tiles` subfolder. Each stack takes the tile name without the channel tag:

```
Stacked_Tiles/
├── TileScan 1_t00_s00.tif
├── TileScan 1_t00_s01.tif
└── ...
```

**Settings** (top of the macro):

- `outFolderName`: name of the output subfolder (default `Stacked_Tiles`).
- `nChannels`: number of channels per tile. With `0` (default), the macro counts the channels of the first tile (`ch00`, `ch01`, … up to the first missing one) and expects the same count for every other tile. Set it to `2`, `3`, … to require exactly that many.
- `maxChannels`: upper limit for the automatic count (default `10`).
- `convertTo8bit`: set to `true` if the channels differ in bit depth or type (for example, one RGB and two 8-bit). *Concatenate* fails when the images differ.

Every tile must end up with the same number of slices, because Step 2 stitches all slices of a tile together. A tile with a missing channel, or with more channels than the first tile, is skipped and listed in the Log window.

---

## 3. Stitch the stacked tiles (`step02_stitch_stacked_tiles.ijm`)

1. Run the macro in Fiji and choose the `Stacked_Tiles` folder.
2. Enter the grid size and overlap in the dialog:
   - **Tiles in X (n)**: number of tile columns.
   - **Tiles in Y (m)**: number of tile rows.
   - **Tile overlap [%]**: overlap set in LAS X for the tile scan (plugin default: 20).

   The number of tiles per time point must equal n × m. For example, a 3 × 3 scan has tiles `s00`–`s08`.

The macro groups the files by time point and stitches each group with *Grid/Collection stitching*:

- **Type:** Grid: snake by rows
- **Order:** Right & Down
- **File name pattern:** detected from the file names, e.g. `TileScan 1_t00_s{ii}.tif`
- **Start index:** the lowest `s` number in the group (normally 0)
- **All other options:** plugin defaults (Linear Blending, regression threshold 0.30, max/avg displacement 2.50, absolute displacement 3.50, compute overlap on)

All slices of a tile are placed with the same tile positions, so the channels stay aligned with each other. After each stitch, the macro runs *Stack to Images* and saves each channel separately in `Stitched/`. It removes the original `t` and `s` tags and numbers the time points again from `t000`:

```
Stacked_Tiles/Stitched/
├── TileScan 1_t000_ch00.tif
├── TileScan 1_t000_ch01.tif
├── TileScan 1_t000_ch02.tif
├── TileScan 1_t001_ch00.tif
├── TileScan 1_t001_ch01.tif
├── TileScan 1_t001_ch02.tif
└── ...
```

A time point with fewer or more than n × m tiles is skipped and listed in the Log window. The plugin also writes `TileConfiguration.txt` and `TileConfiguration.registered.txt` to the `Stacked_Tiles` folder; these record the tile positions of the last stitched time point.

---

## Troubleshooting

- **"Right & Down" is not recognized.** The plugin stores this option with trailing spaces, and the macro copies them. If your Fiji version names it differently, record one stitching run with *Plugins › Macros › Record…* and paste the recorded `order=[...]` text into line 115 of `step02_stitch_stacked_tiles.ijm`.
- **The mosaic looks scrambled.** The tile order in LAS X did not match *snake by rows, Right & Down*. Check the scan direction in the LAS X tile-scan settings and change `type=` and `order=` in the macro to match.
- **No tiles found.** Check that the file names still carry the `_s##` tag (and `_t##` for time series) after export.
