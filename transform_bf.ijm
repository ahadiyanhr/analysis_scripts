// Step 0: Inputs
// Ask the user for a Brightfield channel ID
channel_ID = getString("Enter brightfield channel ID:", "ch00");

// Step 1: Inputs & find all folders'
currentDir = getDirectory("current");
parentDir = File.getParent(currentDir);
inputDir = parentDir + "\\raw_data\\images\\tif_images" + File.separator;
outputDir = parentDir + "\\processed_images\\registered_images" + File.separator;
logDir = parentDir + "\\logs\\transform_matrices.txt";


// -------- Step 2: Read all images --------
list = getFileList(inputDir);
bfList = newArray();
for (i=0; i<list.length; i++) {
    if (endsWith(list[i], ".tif") && indexOf(list[i], channel_ID) != -1) {
        bfList = Array.concat(bfList, list[i]);
    }
}

// Sort the images list
Array.sort(bfList);

// Open all images
for (i=0; i<bfList.length; i++) {
    open(inputDir + bfList[i]);
}

// Make stack of images
run("Images to Stack", "name=aligned_stack");

// Step 3: Apply SIFT alignment
run("Linear Stack Alignment with SIFT", 
    "initial_gaussian_blur=1.60 steps_per_scale_octave=3 minimum_image_size=64 " + 
    "maximum_image_size=1024 feature_descriptor_size=4 feature_descriptor_orientation_bins=8 " + 
    "closest/next_closest_ratio=0.92 maximal_alignment_error=25 inlier_ratio=0.05 " + 
    "expected_transformation=Affine interpolate show_transformation_matrix");

// Step 4: Rename the aligned stack
rename("Aligned_BF");
close("aligned_stack");

print("Alignment is DONE!");

// Get the content of the Log window
logContent = getInfo("Log");

// Save the log content as a text file
File.saveString(logContent, logDir);

// Print a message in Log window
print("Transfrom Matrices saved to log folder");
