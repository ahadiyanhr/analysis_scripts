// ==== BEGIN MACRO ====

// Step 1: Directory setup
currentDir = getDirectory("current");
parentDir = File.getParent(currentDir);
inputDir = parentDir + "\\processed_images\\modified_images" + File.separator;
roiDir = parentDir + "\\logs" + File.separator;
outputDir = inputDir;

// === FUNCTION: Crop image based on ROI file ===
function rectifyStack(roiPath) {
    roiFolder = roiPath + File.separator;
    roiList = getFileList(roiFolder);
    roiPath = "";
    for (i = 0; i < roiList.length; i++) {
        if (endsWith(roiList[i], "working_area.roi")) {
            roiPath = roiFolder + roiList[i];
            break;
        }
    }

    if (roiPath == "") {
        exit("No ROI file found in logs folder!");
    } else {
        print("ROI file found: " + roiPath);
    }

    roiManager("Reset");
    roiManager("Open", roiPath);
    roiManager("Select", 0);
    run("Crop");
    getSelectionCoordinates(xCoords, yCoords);

    dx1 = xCoords[1] - xCoords[0];
    dy1 = yCoords[1] - yCoords[0];
    dx2 = xCoords[0] - xCoords[3];
    dy2 = yCoords[3] - yCoords[0];

    roiManager("Show All");
    roiManager("Show None");
    angle = -atan2(dy1, dx1) * 180 / PI;
    run("Rotate...", "angle=" + angle + " grid=1 interpolation=Bicubic");

    cx = getWidth()/2;
    cy = getHeight()/2;
    roiWidth = round(Math.sqrt(dx1*dx1 + dy1*dy1));
    roiHeight = round(Math.sqrt(dx2*dx2 + dy2*dy2));

    xNew = cx - roiWidth/2;
    yNew = cy - roiHeight/2;
    makeRectangle(xNew, yNew, roiWidth, roiHeight);
    run("Crop");
}

// ==== Loop through channels ====
channels = newArray("ch01", "ch02");

for (c = 0; c < channels.length; c++) {
    channel_ID = channels[c];
    print("Processing channel: " + channel_ID);

    // Step 2: Get image list for this channel
    list = getFileList(inputDir);
    imgList = newArray();
    for (i=0; i<list.length; i++) {
        if (endsWith(list[i], ".tif") && indexOf(list[i], channel_ID) != -1) {
            imgList = Array.concat(imgList, list[i]);
        }
    }

    Array.sort(imgList);

    // Step 3: Open images
    for (i=0; i<imgList.length; i++) {
        open(inputDir + imgList[i]);
    }

    // Step 4: Stack and rename
    run("Images to Stack", "name=aligned_stack");
    if (channel_ID == "ch01")
        FileName = "GFP_aligned";
    else
        FileName = "FRET_aligned";

    rename(FileName);
    close("aligned_stack");

    print("Rectifying is running for " + channel_ID);
    rectifyStack(roiDir);
    print("Rectifying is DONE for " + channel_ID);

    // Step 5: Save slices
    for (i = 1; i <= nSlices; i++) {
        setSlice(i);
        run("Duplicate...", " ");
        // Format slice number (e.g., t01, t02...)
	    if (i < 11)
	    	sliceLabel = "t0" + i-1;
		else
	    	sliceLabel = "t" + i-1;
        saveAs("Tiff", outputDir + sliceLabel + "_" + channel_ID + ".tif");
        close();
    }

    close(); // Close the aligned image
    print("Finished saving for " + channel_ID);
}

print("All GFP and FRET images are SAVED in modified_images!");

// ==== END MACRO ====
