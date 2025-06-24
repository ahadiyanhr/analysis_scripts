// ------------------ PARAMETERS ------------------
radius_outliers = 10;
threshold_outliers = 40;
threshold_method = "Otsu dark";
manual_threshold_min = 10000;  // you can modify
manual_threshold_max = 65535;
// ------------------------------------------------------
// Find all folders
currentDir = getDirectory("current");
parentDir = File.getParent(currentDir);
inputDir = parentDir + "\\processed_images\\modified_images" + File.separator;
maskDir = parentDir + "\\processed_images\\grain_mask" + File.separator;

// Loop to find next available output folder
i = 1;
while (true) {
    index = IJ.pad(i, 2); // pad with 0 to 2 digits
    folderName = "biomass_images_" + index;
    outputDir = inputDir + folderName + File.separator;
    
    if (!File.exists(outputDir)) {
        // Folder does not exist – create it
        File.makeDirectory(outputDir);
        break;
    }
    i++;
}

filelist = getFileList(maskDir);
for (i = 0; i < lengthOf(filelist); i++) {
    if (endsWith(filelist[i], "mask.tif")) { 
        open(maskDir + File.separator + filelist[i]);
        rename("Mask");
    } 
}

// Get list of all images
list = getFileList(inputDir);
bfList = newArray();
for (i=0; i<list.length; i++) {
    if (endsWith(list[i], ".tif") && indexOf(list[i], "ch00") != -1) {
        bfList = Array.concat(bfList, list[i]);
    }
}

nFiles = bfList.length;

// Sort files if necessary (optional, depending on your filenames)
Array.sort(bfList);

// Load reference image (t=0)
open(inputDir + bfList[0]);
rename("refImage");
run("Enhance Contrast...", "saturated=0.35 normalize");
selectWindow("refImage");

// Start processing loop from t=1 to end
for (i = 1; i < nFiles; i++) {
    
    // Open current time t image
    open(inputDir + bfList[i]);
    rename("currImage");
    run("Enhance Contrast...", "saturated=0.35 normalize");
    
    // Subtract: current - reference
    imageCalculator("Subtract create", "refImage", "currImage");
    rename("subtracted");
    
    // Remove grains using mask
    imageCalculator("AND", "subtracted","Mask");
    
    // Remove outliers
    run("Remove Outliers...", "radius=" + radius_outliers + " threshold=" + threshold_outliers + " which=Bright");
    
    // Enhance contrast again after outlier removal
    run("Enhance Contrast...", "saturated=0.35 normalize");
    
    // Thresholding
    setAutoThreshold(threshold_method);
    setThreshold(manual_threshold_min, manual_threshold_max);
    setOption("BlackBackground", true);
    run("Convert to Mask");
    
    // Rename mask
    num = IJ.pad(i, 2); // pad with leading zeros: 01, 02, etc.
    rename("Image_" + num);
    
    // Save mask
    if (i == 1) {
    	saveAs("Tiff", outputDir + "Image_00.tif");    	
    }
    saveAs("Tiff", outputDir + "Image_" + num + ".tif");
    
    // Close current images to free memory
    close("currImage");
    close("subtracted");
    close("Image_" + num + ".tif");
}

// Close reference image after loop
close("refImage");
close("Mask");

// Format the parameter content
getDateAndTime(year, month, week, day, hour, min, sec, msec);
paramText = "Parameters for this biomass occupation results:\n\n";
paramText += "radius_outliers = " + radius_outliers + "\n";
paramText += "threshold_outliers = " + threshold_outliers + "\n";
paramText += "threshold_method = \"" + threshold_method + "\"\n";
paramText += "manual_threshold_min = " + manual_threshold_min + "\n";
paramText += "manual_threshold_max = " + manual_threshold_max + "\n\n";
paramText += "Saved on Date: "+day+"/"+month+"/"+year+"  Time: " +hour+":"+min+":"+sec + "\n";

// Set output path and filename
paramFile = outputDir + "thresholding_parameters.txt";

// Save the file Parameters
File.saveString(paramText, paramFile);

print("Done: All Biomass Occupation saved into folder");


// Get biomass image list and sort it
fileList = getFileList(outputDir);
Array.sort(fileList);

// Step 3: Create 'growth' and 'decay' folders in same root
growthDir = outputDir + "growth_images/";
decayDir = outputDir + "decay_images/";
File.makeDirectory(growthDir);
File.makeDirectory(decayDir);

// Step 4: Loop over image pairs
for (i = 0; i < fileList.length - 2; i++) {
    file1 = fileList[i];
    file2 = fileList[i + 1];
    
    open(outputDir + file1);
    image1 = getTitle();
    
    open(outputDir + file2);
    image2 = getTitle();

    // Compute growth: img2 - img1
    imageCalculator("Subtract create", image2,image1);
    
    // Rename mask
    num = IJ.pad(i+1, 2); // pad with leading zeros: 01, 02, etc.

    saveAs("Tiff", growthDir + "Image_" + num + ".tif");

    // Compute decay: img1 - img2
    imageCalculator("Subtract create", image1,image2);
    
    saveAs("Tiff", decayDir + "Image_" + num + ".tif");
    close("Image_" + num + ".tif");
    close("Image_" + num + "-1.tif");
    close();
}

print("Done: All Growth and Decay images saved.");
