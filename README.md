📊 Data Analysis Protocol for Microfluidic Experiments
This repository contains scripts and macros to pre-process image and sensor data from microfluidic experiments involving biofilms, GFP/FRET fluorescence, and micromodel flow visualization. Follow the instructions below to set up your project, import raw data, and run the analysis pipeline using Fiji (ImageJ) and MATLAB.

🗂 Folder Structure Setup
Clone this repository into the main root of your experiment directory.

Run the batch file:

bash
Copy
Edit
create_project_folders.bat
This will generate all necessary folders and subfolders.

Place any test_report files in the docs/ folder.

📥 Import Raw Data
🔧 Sensor Readings
Copy .txt files for pressure and flow sensors into:

bash
Copy
Edit
raw_data/sensor_readings/
Use the following naming conventions:

Constant Pressure: pconst_ob1.txt, pconst_reader.txt

Constant Flow Rate: qconst_ob1.txt, qconst_reader.txt

🖼 Imaging Files
Copy the Leica imaging project file into:

bash
Copy
Edit
raw_data/images/
From LAS X software, export images (Brightfield, GFP, FRET) into:

bash
Copy
Edit
raw_data/images/tif_images/
Use .tif format. LAS X will automatically name files like:

bash
Copy
Edit
..._ch00.tif  # Brightfield
..._ch01.tif  # GFP
..._ch02.tif  # FRET
🕒 Create Timestamp Log
Create an Excel file:

bash
Copy
Edit
logs/imaging_timestamp.xlsx
Include the following columns:

mathematica
Copy
Edit
Image# | Absolute Time | Date
First row must be:

bash
Copy
Edit
Image# = 0
🟦 ROI Creation
Open Fiji/ImageJ.

Load the first Brightfield image from:

bash
Copy
Edit
raw_data/images/tif_images/
Draw a rectangle covering the micromodel working section.

In the ROI Manager:

Add the selection

Use More > Rotate to align

Adjust corners to match micromodel edges

Add it again

Save the ROI as:

bash
Copy
Edit
logs/crop.roi
🧰 Image Processing Pipeline
🔁 Alignment and Cropping
Open image_alignment.ijm in Fiji.

Set channelID = 'ch00' (Brightfield).

⚠️ GFP and FRET channels must be aligned later in MATLAB.

Save transformation log as:

bash
Copy
Edit
logs/transform.txt
🎭 Mask Refinement
Open mask.tif and t00_ch00.tif as a stack:

bash
Copy
Edit
processed_images/modified_images/
Use SIFT for alignment, then crop to match t00_ch00.tif.

Remove noise:

yaml
Copy
Edit
Process > Noise > Remove Outliers
Radius: 7.5 | Threshold: 75 | Outliers: Bright
Save refined mask as:

bash
Copy
Edit
processed_images/grain_mask/mask.tif
🦠 Biomass Segmentation
Run biomass_segmentation.ijm in Fiji.

Set thresholding parameters and run.

Outputs are saved in:

bash
Copy
Edit
processed_images/biomass_images_*/
Thresholding settings saved as:

Copy
Edit
thresholding_parameters.txt
🧾 Notes
GFP and FRET alignment should be performed using MATLAB scripts, not Fiji.

Ensure file and folder names match the expected structure before running macros.
