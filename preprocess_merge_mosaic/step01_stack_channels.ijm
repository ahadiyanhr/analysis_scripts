// stack_ch00_ch01.ijm
// Pairs every *ch00*.tif with its matching *ch01*.tif in a folder,
// stacks the pair (slice 1 = ch00, slice 2 = ch01), and saves each
// stack as a separate TIFF in a subfolder named "Stacked_Tiles".
// Each stack is named after its tile (file name with "ch00" removed).

// ---- settings ----
outFolderName = "Stacked_Tiles";   // name of the output subfolder
convertTo8bit = false;             // true if ch00/ch01 differ in type (e.g., RGB vs 8-bit)
// ------------------

inputDir = getDirectory("Choose the folder with ch00/ch01 TIFF images");
outDir = inputDir + outFolderName + File.separator;
if (!File.exists(outDir)) File.makeDirectory(outDir);

setBatchMode(true);
list = getFileList(inputDir);
list = Array.sort(list);

nDone = 0;
nMissing = 0;
print("\\Clear");

for (i = 0; i < list.length; i++) {
    name = list[i];
    lower = toLowerCase(name);

    // keep only TIFFs that carry the ch00 tag
    if (!(endsWith(lower, ".tif") || endsWith(lower, ".tiff"))) continue;
    k = lastIndexOf(name, "ch00");
    if (k < 0) continue;

    // build the matching ch01 file name
    name1 = substring(name, 0, k) + "ch01" + substring(name, k + 4);
    if (!File.exists(inputDir + name1)) {
        print("Missing partner, skipped: " + name1);
        nMissing++;
        continue;
    }

    // tile name = file name without "ch00" and extension, trailing _ / space / - removed
    dot = lastIndexOf(name, ".");
    base = substring(name, 0, k) + substring(name, k + 4, dot);
    while (lengthOf(base) > 0 && (endsWith(base, "_") || endsWith(base, " ") || endsWith(base, "-")))
        base = substring(base, 0, lengthOf(base) - 1);
    if (base == "") base = "tile_" + IJ.pad(nDone + 1, 3);

    // open the pair
    open(inputDir + name);
    if (convertTo8bit) run("8-bit");
    t0 = getTitle();
    open(inputDir + name1);
    if (convertTo8bit) run("8-bit");
    t1 = getTitle();

    // stack in order: ch00 then ch01
    run("Concatenate...", "title=[" + base + "] open image1=[" + t0 + "] image2=[" + t1 + "] image3=[-- None --]");

    // label slices
    setSlice(1); setMetadata("Label", "ch00");
    setSlice(2); setMetadata("Label", "ch01");
    setSlice(1);

    saveAs("Tiff", outDir + base + ".tif");
    close("*");

    print("Saved: " + base + ".tif");
    nDone++;
}

setBatchMode(false);
print("Done. " + nDone + " stacks saved to: " + outDir);
if (nMissing > 0) print(nMissing + " ch00 file(s) had no ch01 partner.");
