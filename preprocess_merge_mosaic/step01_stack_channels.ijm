// step01_stack_channels.ijm
// Stacks all channels of every tile into one TIFF.
//
// For every *ch00*.tif, the macro looks for the partner files ch01, ch02, ...
// (same name, only the channel number changes), stacks them in channel order
// (slice 1 = ch00, slice 2 = ch01, slice 3 = ch02, ...) and saves the stack
// in a subfolder named "Stacked_Tiles". Each stack is named after its tile
// (file name with the channel tag removed).
//
// Number of channels:
//   nChannels = 0  -> detect it from the first tile (ch00, ch01, ... up to the
//                     first missing channel). Every other tile must have the
//                     same number of channels, otherwise it is skipped.
//   nChannels = N  -> use exactly ch00 ... ch(N-1). A tile with a missing
//                     channel is skipped.
// Every tile of a scan must have the same number of slices, because
// step02_stitch_stacked_tiles.ijm stitches all slices together.

// ---- settings ----
outFolderName = "Stacked_Tiles";   // name of the output subfolder
nChannels     = 0;                 // 0 = auto-detect; or 2, 3, ...
maxChannels   = 10;                // upper limit for auto-detection
convertTo8bit = false;             // true if the channels differ in type (e.g., RGB vs 8-bit)
// ------------------

inputDir = getDirectory("Choose the folder with the channel TIFF images");
outDir = inputDir + outFolderName + File.separator;
if (!File.exists(outDir)) File.makeDirectory(outDir);

setBatchMode(true);
list = getFileList(inputDir);
list = Array.sort(list);

nDone = 0;
nSkipped = 0;
expected = nChannels;   // channel count every tile must have (set by the first tile when 0)
print("\\Clear");

for (i = 0; i < list.length; i++) {
    name = list[i];
    lower = toLowerCase(name);

    // keep only TIFFs that carry the ch00 tag
    if (!(endsWith(lower, ".tif") || endsWith(lower, ".tiff"))) continue;
    k = lastIndexOf(name, "ch00");
    if (k < 0) continue;

    // ---- find the partner files ch01, ch02, ... ----
    prefix = substring(name, 0, k);
    suffix = substring(name, k + 4);
    files = newArray(name);

    if (expected > 0) {
        // fixed channel count: every channel must exist
        missing = "";
        for (c = 1; c < expected; c++) {
            nameC = prefix + "ch" + IJ.pad(c, 2) + suffix;
            if (File.exists(inputDir + nameC)) files = Array.concat(files, nameC);
            else missing = missing + " " + nameC;
        }
        if (missing != "") {
            print("Missing channel(s), skipped " + name + ":" + missing);
            nSkipped++;
            continue;
        }
        // with auto-detection, also reject tiles that have MORE channels than the first tile
        extra = prefix + "ch" + IJ.pad(expected, 2) + suffix;
        if (nChannels == 0 && File.exists(inputDir + extra)) {
            print("Extra channel " + extra + " (expected " + expected + " channels), skipped " + name);
            nSkipped++;
            continue;
        }
    } else {
        // auto-detect on the first tile: ch01, ch02, ... until the first missing one
        c = 1;
        searching = true;
        while (searching && c < maxChannels) {
            nameC = prefix + "ch" + IJ.pad(c, 2) + suffix;
            if (File.exists(inputDir + nameC)) { files = Array.concat(files, nameC); c++; }
            else searching = false;
        }
        expected = files.length;
        print("Detected " + expected + " channel(s) per tile (ch00 - ch" + IJ.pad(expected - 1, 2) + ")");
    }

    if (files.length < 2) {
        print("Only one channel found, skipped: " + name);
        nSkipped++;
        continue;
    }

    // ---- tile name = file name without "ch00" and extension, trailing _ / space / - removed ----
    dot = lastIndexOf(name, ".");
    base = prefix + substring(name, k + 4, dot);
    while (lengthOf(base) > 0 && (endsWith(base, "_") || endsWith(base, " ") || endsWith(base, "-")))
        base = substring(base, 0, lengthOf(base) - 1);
    if (base == "") base = "tile_" + IJ.pad(nDone + 1, 3);

    // ---- open the channels in order ----
    titles = newArray(files.length);
    for (c = 0; c < files.length; c++) {
        open(inputDir + files[c]);
        if (convertTo8bit) run("8-bit");
        titles[c] = getTitle();
    }

    // ---- stack in channel order ----
    args = "title=[" + base + "] open";
    for (c = 0; c < titles.length; c++)
        args = args + " image" + (c + 1) + "=[" + titles[c] + "]";
    args = args + " image" + (titles.length + 1) + "=[-- None --]";
    run("Concatenate...", args);

    // label slices with their channel tag
    for (c = 0; c < files.length; c++) {
        setSlice(c + 1);
        setMetadata("Label", "ch" + IJ.pad(c, 2));
    }
    setSlice(1);

    saveAs("Tiff", outDir + base + ".tif");
    close("*");

    print("Saved: " + base + ".tif (" + files.length + " channels)");
    nDone++;
}

setBatchMode(false);
print("Done. " + nDone + " stacks saved to: " + outDir);
if (nSkipped > 0) print(nSkipped + " tile(s) skipped; see the messages above.");
