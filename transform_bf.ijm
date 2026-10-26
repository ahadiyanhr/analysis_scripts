// transform_bf_downscaled.ijm
//
// Low-memory version of transform_bf.ijm.
//
// The macro runs SIFT on downscaled copies of the brightfield images, then
// converts every transform matrix back to full-resolution pixel units before
// it saves logs/transform_matrices.txt. registration.m can therefore read the
// log exactly as before, with no changes.
//
// Memory: only ONE full-resolution image is open at a time. The stack that
// SIFT aligns holds the small copies only.
//
// Conversion: if the small image is the full canvas scaled by (sx, sy), then
// a full-resolution point x maps to u = D*x with D = diag(sx, sy). A SIFT
// transform u' = A*u + t on the small images becomes, at full resolution,
//     x' = (D^-1 * A * D) * x + D^-1 * t
// i.e.  m00, m11 unchanged;  m01 * sy/sx;  m10 * sx/sy;  tx / sx;  ty / sy.
//
// Padding: images are padded to the common full-resolution canvas (centered,
// zero fill) BEFORE downscaling, so the canvas matches padToCanvasCenter() in
// registration.m and every slice shares the same scale factors.

// -------- Step 0: Inputs --------
channel_ID     = getString("Enter brightfield channel ID:", "ch00");
targetLongSide = getNumber("Long side of the downscaled images [px]:", 2048);

print("\\Clear");   // FIX: start from an empty Log so old matrices are not saved again

// -------- Step 1: Folders (same as transform_bf.ijm) --------
currentDir = getDirectory("current");
parentDir  = File.getParent(currentDir);
inputDir   = parentDir + "\\raw_data\\images\\bf_red_channel" + File.separator;
logFile    = parentDir + "\\logs\\transform_matrices.txt";
logFileRaw = parentDir + "\\logs\\transform_matrices_downscaled.txt";

// -------- Step 2: List brightfield images --------
list   = getFileList(inputDir);
bfList = newArray();
for (i = 0; i < list.length; i++) {
    if (endsWith(list[i], ".tif") && indexOf(list[i], channel_ID) != -1) {
        bfList = Array.concat(bfList, list[i]);
    }
}
Array.sort(bfList);
if (bfList.length < 2) exit("Found fewer than two '" + channel_ID + "' images in:\n" + inputDir);

// -------- Step 3: Full-resolution canvas from file headers only --------
// Bio-Formats reads the width and height without loading the pixels.
run("Bio-Formats Macro Extensions");
canvasW = 0;
canvasH = 0;
for (i = 0; i < bfList.length; i++) {
    Ext.setId(inputDir + bfList[i]);
    Ext.getSizeX(w);
    Ext.getSizeY(h);
    Ext.close();
    canvasW = maxOf(canvasW, w);
    canvasH = maxOf(canvasH, h);
}

// Scale factor: long side of the canvas -> targetLongSide (never upscale)
s = targetLongSide / maxOf(canvasW, canvasH);
if (s > 1) s = 1;
newW = round(canvasW * s);
newH = round(canvasH * s);
sx = newW / canvasW;   // exact factors after rounding to whole pixels
sy = newH / canvasH;

print("Full-resolution canvas: " + canvasW + " x " + canvasH + " px");
print("Downscaled canvas:      " + newW + " x " + newH + " px");
print("Scale factors: sx = " + d2s(sx, 8) + ", sy = " + d2s(sy, 8));

// -------- Step 4: Open, pad, downscale, close (one image at a time) --------
setBatchMode(true);
for (i = 0; i < bfList.length; i++) {
    open(inputDir + bfList[i]);
    fullID = getImageID();

    // RGB brightfield -> 8-bit grayscale (SIFT uses intensity only; 3x less memory)
    if (bitDepth() == 24) run("8-bit");

    // Pad to the common canvas, centered, as "Images to Stack" and
    // padToCanvasCenter() in registration.m do
    if (getWidth() != canvasW || getHeight() != canvasH) {
        run("Canvas Size...", "width=" + canvasW + " height=" + canvasH + " position=Center zero");
    }

    // Downscale to a new image and close the full-resolution one
    run("Scale...", "x=- y=- width=" + newW + " height=" + newH +
        " interpolation=Bilinear average create title=small_" + IJ.pad(i, 4));
    selectImage(fullID);
    close();
    call("java.lang.System.gc");

    showProgress(i + 1, bfList.length);
}

// Stack the small images in file order
run("Images to Stack", "name=aligned_stack title=small_ use");
setBatchMode("exit and display");

// -------- Step 5: SIFT alignment (same parameters as transform_bf.ijm) --------
run("Linear Stack Alignment with SIFT",
    "initial_gaussian_blur=1.60 steps_per_scale_octave=3 minimum_image_size=64 " +
    "maximum_image_size=1024 feature_descriptor_size=4 feature_descriptor_orientation_bins=8 " +
    "closest/next_closest_ratio=0.92 maximal_alignment_error=25 inlier_ratio=0.05 " +
    "expected_transformation=Affine interpolate show_transformation_matrix");

rename("Aligned_BF");
close("aligned_stack");
print("Alignment is DONE!");

// -------- Step 6: Save the raw (downscaled) log for the record --------
logContent = getInfo("Log");
File.saveString(logContent, logFileRaw);

// -------- Step 7: Convert every matrix to full-resolution units --------
key   = "AffineTransform[[";
lines = split(logContent, "\n");
out   = "";
nConverted = 0;

for (k = 0; k < lines.length; k++) {
    line  = lines[k];
    start = indexOf(line, key);
    stop  = lastIndexOf(line, "]]");

    if (start >= 0 && stop > start) {
        // "m00, m01, m02], [m10, m11, m12"  ->  six numbers
        inner = substring(line, start + lengthOf(key), stop);
        inner = replace(inner, "\\], \\[", ",");
        p = split(inner, ",");

        if (p.length == 6) {
            m00 = parseFloat(replace(p[0], " ", ""));
            m01 = parseFloat(replace(p[1], " ", ""));
            m02 = parseFloat(replace(p[2], " ", ""));
            m10 = parseFloat(replace(p[3], " ", ""));
            m11 = parseFloat(replace(p[4], " ", ""));
            m12 = parseFloat(replace(p[5], " ", ""));

            f00 = m00;
            f01 = m01 * sy / sx;
            f02 = m02 / sx;
            f10 = m10 * sx / sy;
            f11 = m11;
            f12 = m12 / sy;

            line = substring(line, 0, start) + key +
                   d2s(f00, 12) + ", " + d2s(f01, 12) + ", " + d2s(f02, 9) + "], [" +
                   d2s(f10, 12) + ", " + d2s(f11, 12) + ", " + d2s(f12, 9) + "]]" +
                   substring(line, stop + 2);
            nConverted++;
        }
    }
    out = out + line + "\n";
}

File.saveString(out, logFile);

print("Converted " + nConverted + " transform matrices to full-resolution units.");
print("Full-resolution matrices: " + logFile);
print("Downscaled matrices:      " + logFileRaw);
