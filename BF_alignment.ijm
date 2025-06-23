// Step 0: Inputs
// Ask the user for a Sample ID
channel_ID = getString("Enter channel ID (ch00, ch01, ch02):", "ch00");

// Step 1: Find all folders
currentDir = getDirectory("current");
parentDir = File.getParent(currentDir);
inputDir = parentDir + "\\raw_data\\images\\tif_images" + File.separator;
roiDir = parentDir + "\\logs" + File.separator;
outputDir = parentDir + "\\processed_images\\modified_images" + File.separator;



// === FUNCTION: Crop image based on ROI file ===
function rectifyStack(roiPath) {
  
	// Build the Fiji roi path
	roiFolder = roiPath + File.separator;
	
	// Automatically find the first *.roi file inside Fiji macros folder
	roiList = getFileList(roiFolder);
	roiPath = "";
	for (i = 0; i < roiList.length; i++) {
	    if (endsWith(roiList[i], "working_area.roi")) {
	        roiPath = roiFolder + roiList[i];
	        break;
	    }
	}
	
	if (roiPath == "") {
	    exit("No ROI file found in Fiji macros folder!");
	} else {
	    print("ROI file found: " + roiPath);
	}
    
    // Load ROI
    roiManager("Reset");
    roiManager("Open", roiPath);
    roiManager("Select", 0);
    
    // Crop to center the ROI
    run("Crop");

    // Get ROI coordinates
    getSelectionCoordinates(xCoords, yCoords);

    // Compute rotation angle
    dx1 = xCoords[1] - xCoords[0];
    dy1 = yCoords[1] - yCoords[0];
    dx2 = xCoords[0] - xCoords[3];
    dy2 = yCoords[3] - yCoords[0];
	
	roiManager("Show All");
	roiManager("Show None");
    angle = -atan2(dy1, dx1) * 180 / PI;
    run("Rotate...", "angle=" + angle + " grid=1 interpolation=Bicubic");

    // Get image center
    cx = getWidth()/2;
    cy = getHeight()/2;

    roiWidth = round(Math.sqrt((dx1*dx1) + (dy1*dy1)));
    roiHeight = round(Math.sqrt((dx2*dx2) + (dy2*dy2)));

    xNew = cx - roiWidth/2;
    yNew = cy - roiHeight/2;
    makeRectangle(xNew, yNew, roiWidth, roiHeight);

    run("Crop");
}

// Step 2: Get all images
// (assuming 'ch00' is in the filename for brightfield
// 'ch01' for GFP and 'ch02' for FRET)
list = getFileList(inputDir);
bfList = newArray();
for (i=0; i<list.length; i++) {
    if (endsWith(list[i], ".tif") && indexOf(list[i], channel_ID) != -1) {
        bfList = Array.concat(bfList, list[i]);
    }
}

// Sort the list (optional but highly recommended to maintain correct order)
Array.sort(bfList);

// Open all images
for (i=0; i<bfList.length; i++) {
    open(inputDir + bfList[i]);
    // Convert them to 8-bit grayscale image
	run("8-bit");
}

// Make stack of images
run("Images to Stack", "name=aligned_stack");

// Step 3: Apply SIFT alignment
run("Linear Stack Alignment with SIFT", 
    "initial_gaussian_blur=1.60 steps_per_scale_octave=3 minimum_image_size=64 " + 
    "maximum_image_size=1024 feature_descriptor_size=4 feature_descriptor_orientation_bins=8 " + 
    "closest/next_closest_ratio=0.92 maximal_alignment_error=25 inlier_ratio=0.05 " + 
    "expected_transformation=Rigid interpolate show_transformation_matrix");

// Step 4: Rename the aligned stack
if (channel_ID == "ch00") {
    FileName = "BF_aligned";
} else if (channel_ID == "ch01") {
    FileName = "GFP_aligned";
} else {
    FileName = "FRET_aligned";
}
rename(FileName);
close("aligned_stack");

print("Alignment is DONE!");
print("Rectifying is running!");

// Step 5: Crop and rectify the stack

rectifyStack(roiDir);
print("Rectifying is DONE!");

// Loop through each slice and save it
for (i = 1; i <= nSlices; i++) {
    // Set slice
    setSlice(i);
    run("Duplicate...", " ");
    
    // Format slice number (e.g., t01, t02...)
    if (i < 11)
    	sliceLabel = "t0" + i-1;
	else
    	sliceLabel = "t" + i-1;
    
    // Build filename and save
    saveAs("Tiff", outputDir + sliceLabel + "_" + channel_ID + ".tif");
    close;
}

close();

print("All images is SAVED in > processed_images > modified_images!");
