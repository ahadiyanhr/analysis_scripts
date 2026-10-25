// stitch_stacked_tiles.ijm
// Stitches stacked tiles (slice 1 = ch00, slice 2 = ch01, slice 3 = ch02, ...)
// with Grid/Collection stitching: Grid: snake by rows, Right & Down.
// Works for any number of channels: all slices of a tile are stitched
// together with the same tile positions, and slice c is saved as ch(c-1).
//
// Expected file names: a tile tag "s##" and an optional time tag "t###",
// each preceded by "_", " " or "-", for example:
//     Experiment_t000_s00.tif ... Experiment_t000_s08.tif
//     Experiment_t001_s00.tif ... Experiment_t001_s08.tif
// Files that differ only by their s-number form one stitching group
// (one time point). The macro finds the s-number pattern and start index
// (normally 0) for each group without user input.
//
// Output (subfolder "Stitched"):
//     Experiment_t000_ch00.tif, Experiment_t000_ch01.tif, Experiment_t000_ch02.tif,
//     Experiment_t001_ch00.tif, ...
// The original t and s tags are removed, and time points are renumbered
// in order starting from t000.

// ---- settings ----
outFolderName = "Stitched";
// ------------------

inputDir = getDirectory("Choose the folder with stacked tiles");

Dialog.create("Tile grid");
Dialog.addNumber("Tiles in X (columns, n):", 3);
Dialog.addNumber("Tiles in Y (rows, m):", 3);
Dialog.addNumber("Tile overlap [%]:", 20);
Dialog.show();
gridX   = Dialog.getNumber();
gridY   = Dialog.getNumber();
overlap = Dialog.getNumber();
nTiles  = gridX * gridY;

outDir = inputDir + outFolderName + File.separator;
if (!File.exists(outDir)) File.makeDirectory(outDir);
print("\\Clear");

// ---------- 1. Group files by name with the s-number removed ----------
list = getFileList(inputDir);
list = Array.sort(list);

keys = newArray(0);    // name with s-number replaced by {s}
exts = newArray(0);
sLens = newArray(0);   // number of digits in the s-number
sMins = newArray(0);   // smallest s-number (start index)
counts = newArray(0);
tVals = newArray(0);   // original t value used for sorting

for (i = 0; i < list.length; i++) {
    name = list[i];
    lower = toLowerCase(name);
    if (!(endsWith(lower, ".tif") || endsWith(lower, ".tiff"))) continue;

    dot = lastIndexOf(name, ".");
    stem = substring(name, 0, dot);
    ext  = substring(name, dot);

    sTag = findTag(stem, "s");
    if (sTag[0] < 0) { print("No s-number, skipped: " + name); continue; }
    sPos = sTag[0]; sLen = sTag[1];
    sVal = parseInt(substring(stem, sPos + 1, sPos + 1 + sLen));
    key  = substring(stem, 0, sPos + 1) + "{s}" + substring(stem, sPos + 1 + sLen);

    g = -1;
    for (j = 0; j < keys.length; j++) if (keys[j] == key && exts[j] == ext) g = j;

    if (g < 0) {
        tTag = findTag(key, "t");
        tv = -1;
        if (tTag[0] >= 0) tv = parseInt(substring(key, tTag[0] + 1, tTag[0] + 1 + tTag[1]));
        keys   = Array.concat(keys, key);
        exts   = Array.concat(exts, ext);
        sLens  = Array.concat(sLens, sLen);
        sMins  = Array.concat(sMins, sVal);
        counts = Array.concat(counts, 1);
        tVals  = Array.concat(tVals, tv);
    } else {
        counts[g] = counts[g] + 1;
        if (sVal < sMins[g]) sMins[g] = sVal;
    }
}

if (keys.length == 0) exit("No tiles with an s-number found in:\n" + inputDir);

// sort groups by original t value
order = Array.rankPositions(tVals);

// ---------- 2. Stitch each group ----------
tOut = 0;
for (o = 0; o < order.length; o++) {
    g = order[o];
    key = keys[g];

    if (counts[g] != nTiles) {
        print("Skipped " + key + exts[g] + ": found " + counts[g] + " tiles, expected " + nTiles);
        continue;
    }

    // file-name pattern for the stitching plugin, e.g. Experiment_t000_s{ii}.tif
    braces = "";
    for (k = 0; k < sLens[g]; k++) braces = braces + "i";
    pattern = replace(key, "\\{s\\}", "{" + braces + "}") + exts[g];

    // output base name: remove the s and t tags with their separators
    base = removeTag(replace(key, "\\{s\\}", "0"), "s");
    base = removeTag(base, "t");
    if (base == "") base = "stitched";

    print("Stitching " + pattern + " (start index " + sMins[g] + ") -> " + base + "_t" + IJ.pad(tOut, 3));

    run("Grid/Collection stitching",
        "type=[Grid: snake by rows] order=[Right & Down                ]" +
        " grid_size_x=" + gridX + " grid_size_y=" + gridY +
        " tile_overlap=" + overlap +
        " first_file_index_i=" + sMins[g] +
        " directory=[" + inputDir + "]" +
        " file_names=[" + pattern + "]" +
        " output_textfile_name=TileConfiguration.txt" +
        " fusion_method=[Linear Blending] regression_threshold=0.30" +
        " max/avg_displacement_threshold=2.50 absolute_displacement_threshold=3.50" +
        " compute_overlap computation_parameters=[Save computation time (but use more RAM)]" +
        " image_output=[Fuse and display]");

    // ---------- 3. Split the fused stack and save each slice ----------
    fusedID = getImageID();
    nSl = nSlices;
    if (nSl > 1) {
        run("Stack to Images");
        // Stack to Images opens slices as separate windows in slice order
        ids = newArray(nSl);
        n = 0;
        for (w = 1; w <= nImages; w++) {
            selectImage(w);
            ids[n] = getImageID(); n++;
            if (n == nSl) w = nImages + 1;
        }
        for (c = 0; c < nSl; c++) {
            selectImage(ids[c]);
            saveAs("Tiff", outDir + base + "_t" + IJ.pad(tOut, 3) + "_ch" + IJ.pad(c, 2) + ".tif");
        }
    } else {
        saveAs("Tiff", outDir + base + "_t" + IJ.pad(tOut, 3) + ".tif");
    }
    close("*");
    tOut++;
}

print("Done. " + tOut + " time point(s) stitched and saved to: " + outDir);


// ---------- helper functions ----------

// Finds the last tag "<sep><c><digits>" (sep = _ space -) in str.
// Returns [position of the letter, number of digits]; position = -1 if absent.
function findTag(str, c) {
    best = -1; blen = 0;
    L = lengthOf(str);
    for (p = 1; p < L - 1; p++) {
        prev = substring(str, p - 1, p);
        if ((prev == "_" || prev == " " || prev == "-") && toLowerCase(substring(str, p, p + 1)) == c) {
            // FIX: the macro language evaluates both sides of "&&", so
            // substring() ran past the end of the name. Check the bound first.
            q = p + 1;
            scanning = true;
            while (scanning) {
                if (q >= L) scanning = false;
                else if (indexOf("0123456789", substring(str, q, q + 1)) < 0) scanning = false;
                else q++;
            }
            if (q > p + 1) { best = p; blen = q - p - 1; }
        }
    }
    return newArray(best, blen);
}

// Removes the tag "<sep><c><digits>" and its separator from str.
function removeTag(str, c) {
    tag = findTag(str, c);
    if (tag[0] < 0) return str;
    return substring(str, 0, tag[0] - 1) + substring(str, tag[0] + 1 + tag[1]);
}
