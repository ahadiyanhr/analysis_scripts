// Add GROWTH and DECAY images into the folder?
dynamics_images = 2; // 1: Yes, 2: NO
// ------------------ PARAMETERS ------------------
run("Auto Local Threshold", "method=Phansalkar radius=100 parameter_1=0.2 parameter_2=0.4 white");
// Set thresholding method:
// global: Otsu, Huang, Mean, Minimum
// local: Bernsen, Phansalker
method = "Phansalker";

// if local?
radius = 100; // Bern:20 | Phan: 100
param1 = 0.1; // Bern:50 | Phan: 0.1
param2 = 0.25; // Bern:0 | Phan: 0.25
// ------------------------------------------------------
// Find all folders
currentDir = getDirectory("current");
parentDir = File.getParent(currentDir);
inputDir = parentDir + "\\processed_images\\background_subtracted" + File.separator;
maskDir = parentDir + "\\processed_images\\grain_mask" + File.separator;
threshDir = parentDir + "\\processed_images\\thresholded_images" + File.separator;


// Find type of thresholding
// Thresholding
    if (method == "Otsu" || method == "Huang" || method == "Mean" || method == "Minimum") {
	    // Global
	    thresh_type = "global";
	} else if (method == "Bernsen" || method == "Phansalker") {
	    // Local
	    thresh_type = "local";
	}

// Loop to find next available output folder
i = 1;
while (true) {
    index = IJ.pad(i, 2); // pad with 0 to 2 digits
    folderName = thresh_type+"_" + method + "_" + index;
    outputDir = threshDir + folderName + File.separator;
    if (!File.exists(outputDir)) {
        // Folder does not exist – create it
        File.makeDirectory(outputDir);
        break;
    }
    i++;
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

// Sort files if necessary
Array.sort(bfList);

// Start processing loop from t=1 to end
for (i = 1; i < nFiles; i++) {
    
    // Open current time t image
    open(inputDir + bfList[i]);

    // Thresholding
    if (thresh_type == "global") {
	    // Global
	    threshold_method = method + " dark";
	    setAutoThreshold(threshold_method);
	    setOption("BlackBackground", true);
	    run("Convert to Mask");
	} else if (thresh_type == "local") {
	    // Local
	    threshold_method = "method="+method+" radius="+radius+" parameter_1="+param1+" parameter_2="+param2+" white";
	    run("8-bit");
		run("Auto Local Threshold", threshold_method);
	}
    
    // Rename mask
    num = IJ.pad(i, 2); // pad with leading zeros: 01, 02, etc.
    rename("Image_" + num);
    
    // Save mask
    saveAs("Tiff", outputDir + "Image_" + num + ".tif");
    
    // Close current images to free memory
    close("Image_" + num + ".tif");
}

// Format the parameter content
getDateAndTime(year, month, week, day, hour, min, sec, msec);
paramText = "Parameters for this biomass occupation results:\n\n";
paramText += "threshold_method = " + method + " "+ thresh_type + "\n";
if (thresh_type == "local") {
    // add local method parameters
    paramText += "radius = " + radius + "\n";
    paramText += "parameters1 = " + param1 + "\n";
    paramText += "parameters2 = " + param2 + "\n";
}
paramText += "Saved on Date: "+day+"/"+month+"/"+year+"  Time: " +hour+":"+min+":"+sec + "\n";

// Set output path and filename
paramFile = outputDir + "thresholding_parameters.txt";

// Save the file Parameters
File.saveString(paramText, paramFile);

print("Done: All Biomass Occupation saved into folder");

if (dynamics_images == 1) {
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
}
