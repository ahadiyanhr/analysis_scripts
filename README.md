# 📊 Data Analysis Protocol for Microfluidic Experiments

This repository provides macros and scripts to support the analysis of pressure/flow sensor data and microscopy images (Brightfield, GFP, FRET) from microfluidic experiments. The protocol uses Fiji (ImageJ) and MATLAB for processing the data.

---

## **Preparation/Pre-processing**

### **Folder Structure Setup**
- Clone the **`analysis_scripts`** repository from GitHub into the **main root** of the experiment folder.
- Run `create_project_folders.bat` (located in the `analysis_scripts` folder) to automatically generate all required folders and subfolders as below.
- Rename `Leica images` in the folder into **`original_images_readings`**, then move the `ElveFlow data` folder into it.
- Save all documentation files like `test_report`s or `culture verification` images in the `docs/` folder.

```
MainFolderProject/
├── raw_data/                 # Original, untouched raw data (images, sensor data)
│   ├── images/
│   └── sensor_readings/
│
├── processed_data/           # Final, polished outputs of processing
│   ├── do_ratio/               # For optode DO Ratio image (struct data, pixelwise)
│   ├── do_mapped/              # For optode DO Ratio image (struct data, blockwise, same size with heatmap images)
│   ├── bioOccu_bulkDO/         # For biomass occupation and bulk DO data series (struct data)
│   ├── growth_erosion/         # For biomass growth and erosion data (struct data)
│   ├── plots/                  # For biomass occupation plots (fig and png format)
│   └── pq_cleaned_data/        # CSV files for clean flowrate and deltaP data (including smooth data)
│
├── processed_images/         # Specific image-based outputs (masks, cropped)
│   ├── grain_mask/                  # For grain masks, segmentation masks, etc.
│   ├── registered_images/           # All registered images (3 channels).
│   ├── heatmap_images/              # All heatmap DO images (blockwise, same size with do_mapped data).
│   ├── background_subtracted/       # All background subtracted images (ready for thresholding).
│   ├── biomass_density_overlay/     # For biomass density overlay images generated from background subtracted images
│   ├── thresholded_images/          # For images that have been thresholded
│       └── subfolders/              # For biomass occupation images based on different thresholding methods
│           └── thresholding_parameters.txt   # Saved thresholding parameters
│   ├── growth_erosion_images/       # For the biomass growth and erosion images
│       ├── growth/                  # For biomass growth images
│       └── erosion/                 # For biomass erosion images
│
├── analysis_scripts/         # Fiji macros, MATLAB functions/scripts
│   ├── grain_mask/                # All grain masks for reference
│   ├── functions/                 # all sub-functions required for running main codes
│   └── timestamps_temp/           # templates for timestamps log
│
├── logs/                     # Log files (Transforms log, imaging timestamp, and ROI needed for cropping)
│
└── docs/                     # Project documentation, READMEs, notes
```

### **Copy Sensor Data**
- Place the pressure and flow sensor **`.txt` files in:
  ```
  raw_data/sensor_readings/
  ```
- Use the following filename formats:
  - *Constant pressure experiments:* `__ob1_pressures.txt`, `__reader_flowrate.txt`
  - *Constant flow rate experiments:* `__ob1_flowrate.txt`, `__reader_pressures.txt`

### **Copy Experimental Images**
- Export all **RAW IMAGE** of channels (Brightfield, FRET) from **LAS X software** into:
  ```
  raw_data/images/bf_red_channel/
  ```
  as `.tif` files (make sure you choose RAW).
- Export **RAW IMAGE** of GFP channel from **LAS X software** into: ([see google doc for details](https://docs.google.com/document/d/1rX5TPAGcIr966Zn2Bn92IoGF9PZxMy9OTDXNga8oEyc/edit?usp=sharing))
  ```
  raw_data/images/gfp_channel/
  ```
  as `.tif` files (make sure you choose RAW).
- File naming convention (done automatically by LAS X):
  - `..._ch00.tif` → Brightfield
  - `..._ch01.tif` → FRET
> *Note:* If you only need specific images (specific time) from an image series, you can use the **crop** tools in LAS X software. Simply set the start and end slice to create a new series from your original one.

### **Grain Mask Images**
- Here is a link to access all grain masks [download](https://github.com/ahadiyanhr/analysis_scripts/tree/main/grain_mask)
  
### **Create Imaging Timestamp Log**
- Using `Properties` in **LAS X software**, create an Excel file in the `logs/` folder named:
  ```
  imaging_timestamp.xlsx
  ```
  > *Note:* Use [this template](https://github.com/ahadiyanhr/analysis_scripts/tree/main/table_templates) for your reference.
- Include the following columns:
  - `Image#`
  - `Datetime`
- The first row should be:
  ```
  Image# = 0
  ```
  marking the beginning of the experiment.
- The second row format should be:
  ```
  mm/dd/yyyy hh:mm:ss AM/PM
  ```

### **Create Sensors Offset Log**
- Using `Offset` section in the **`docs/test_report.pdf`**, create an Excel file in the `logs/` folder named:
  ```
  sensor_offset.xlsx
  ```
- Include the following columns:
  - `flowrate`
  - `pressure_diff`
> *Note:* Use [this template](https://github.com/ahadiyanhr/analysis_scripts/tree/main/table_templates) for your reference.
  
### **Optode Calibration**
> *Note:* For optode calibration procedure and protocol, see **here**.
- Move folder **`optode_calibration`** into the main calibration images folder.
- Open Fiji ImageJ, then using `Analyze > Tools > ROI Manager`, open the `calibrationROI.roi`.
- Open the calibration images LIF file in Fiji and select `Hyperstack` as the view, then `Select All` and `OK`.
- Go to `Image > Stacks > Tools > Concatenate`, check `All open windows` and `Open as 4D image` and press `OK`.
- Open `extract_calib_data.ijm` and click on run.
- In `Results` window, using `File > Save`, save the data with desired filename as `opt##_id##.csv` that shows both optode batch# and calibration replicates id#.
- Open the CSV file, then enter all of the DO data for each image with the `O2` label in column F.

- Open and run this Fiji ImageJ macro:
  ```
  calib_joint_fit.m
  ```
  m file will run and generate a CSV file as `calibration_summary_opt##.csv`. Move this file into the `log` folder of the experiment.

---

## **Process Images**

### **Cleaning & smoothing flowrate and pressures data**
- Open and run this Matlab:
  ```
  pq_cleaning.m
  ```
> *Note:* Default value for smoothing window is 20 secs but it can be changed.

### **Generating Transform Matrices for Image Alignment**
- Open and run this Fiji ImageJ macro:
  ```
  transform_bf.ijm
  ```
- Set `channelID = 'ch00'` for Brightfield.
> *Note:* Before closing Aligned_BF stack, ensure that Fiji ImageJ has aligned the images correctly.
- After the running is completed, the log will be saved in:
  ```
  logs/transform_matrices.txt
  ```

### **Registration**
- Open and run in MATLAB:
  ```
  registration.m
  ```
- For manual alignment, select four corresponding points, located at the four corners, in both images.
> *Note:* To proceed after making a selection, dismiss the window.
- After applying the mask, **compare the alignment**. If it looks good, choose **'YES'**.
- All aligned images are saved in:
  ```
  processed_images/registered_images/
  ```
  
### **Background Subtraction and Thresholding**
- Open and run this Fiji ImageJ macro:
  ```
  BackSub_Threshoding.ijm
  ```
> *Note:* Due to issues with admin access to shared drive, all background subtracted and Thresholded images are saved on your Desktop in below folders:
  ```
  ... YOUR Desktop/background_subtracted
  ... YOUR Desktop/thresholded_images
  ```
> These two folders should copy into main experiment folder as below:
  ```
  processed_images/background_subtracted/
  processed_images/thresholded_images/
  ```

### **DO Ratio and Distribution Heatmap**
- Open and run in MATLAB:
  ```
  ratio_cal.m
  ```
- All DO Ratio data (pixelwise, the same size as original raw FRET images) are saved in:
  ```
  processed_data/do_ratio/
  ```
> *Note:* All struct data saved in `do_ratio` folder can be used for generating blockwise (block averaging) heatmaps in the following steps.
- Open and run in MATLAB:
  ```
  heatmap_cal.m
  ```
- All DO heatmap images and data (blockwise) are saved in:
  ```
  processed_data/do_mapped/
  processed_images/heatmap_images/
  ```

---

## **Post-Processing Images**

### **Biomass Occupation and Bulk DO Calculations**
- Open and run in MATLAB:
  ```
  bioOccu_bulkDO.m
  ```
- Once you run this m file, biomass occupation and bulk DO data are saved in:
  ```
  processed_data/bioOccu_bulkDO/
  ```

### **Biomass Density Overlay**
- Open and run in MATLAB:
  ```
  bioOccu_density_overlay.m
  ```
- Once you run this m file, biomass density overlay iamges are saved in:
  ```
  processed_data/biomass_density_overlay/
  ```

### **%Growth and % Erosion Calculation**
- Open and run in MATLAB:
  ```
  growth_erosion_cal.m
  ```
- Once you run this m file is saved in:
  ```
  processed_data/growth_erosion/
  ```

### **Generating Combined Plot**
- For having a combined plot (three panel) (%growth, %erosion, %net, normalized biomass occupation, Bulk DO, Flowrate, and DeltaP), run in MATLAB:
  ```
  plot_data.m
  ```
- Then see the plot in below directory:
   ```
  processed_data/plots/
  ```
---
