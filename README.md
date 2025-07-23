# 📊 Data Analysis Protocol for Microfluidic Experiments

This repository provides macros and scripts to support the analysis of pressure/flow sensor data and microscopy images (Brightfield, GFP, FRET) from microfluidic experiments. The protocol uses Fiji (ImageJ) and MATLAB for processing the data.

---

## **Preparation/Pre-processing**

### **Folder Structure Setup**
- Clone the **`analysis_scripts`** repository from GitHub into the **main root** of the experiment folder.
- Run `create_project_folders.bat` (located in the `analysis_scripts` folder) to automatically generate all required folders and subfolders as below.
- Save all documentation files like `test_report`s or `culture verification` images in the `docs/` folder.

```
MainFolderProject/
├── raw_data/                 # Original, untouched raw data (images, sensor data)
│   ├── images/
│   └── sensor_readings/
│
├── processed_data/           # Final, polished outputs of processing
│   └── do_ratio/                 # For DO ratio struct data
│
├── processed_images/         # Specific image-based outputs (masks, cropped)
│   ├── grain_masks/                # For grain masks, segmentation masks, etc.
│   ├── registered_images/              # For images that have been cropped and aligned
│   |  └── biomass_images_*/         # For biomass occupation images based on parameters
│   |    │    └── decay_images/            # For decay images based on parameters
│   |    │    └── growth_images/           # For growth images based on parameters
│   |    └── thresholding_parameters.txt   # Saved thresholding parameters
│   |
│   └── background_subtracted/          # For background subtracted images   
│
├── analysis_scripts/         # Fiji macros, MATLAB functions/scripts
│
├── logs/                     # Log files (Transforms log, imaging timestamp)
│
└── docs/                     # Project documentation, READMEs, notes
```

### **Copy Sensor Data**
- Place the pressure and flow sensor **`.txt` files in:
  ```
  raw_data/sensor_readings/
  ```
- Use the following filename formats:
  - *Constant pressure experiments:* `pconst_ob1.txt`, `pconst_reader.txt`
  - *Constant flow rate experiments:* `qconst_ob1.txt`, `qconst_reader.txt`

### **Copy Experimental Images**
- Copy the Leica imaging project file to:
  ```
  raw_data/images/
  ```
- Export all **RAW IMAGE** channels (Brightfield, GFP, FRET) from **LAS X software** into:
  ```
  raw_data/images/tif_images/
  ```
  as `.tif` files (make sure you choose RAW).
- File naming convention (done automatically by LAS X):
  - `..._ch00.tif` → Brightfield
  - `..._ch01.tif` → GFP
  - `..._ch02.tif` → FRET
> *Note:* If you only need specific images from an image series, you can use the **crop** tools in LAS X software. Simply set the start and end slice to create a new series from your original one.

### **Copy Grain Mask Images**
- Copy all mask images into:
  ```
  processed_images/grain_mask/mask.tif
  ```
  - Here is a link to access all grain masks [download](https://drive.google.com/open?id=1MAp_4y9EnB75sp7faB2pifpVzzQgqX1o&usp=drive_fs)
  
### **Create Imaging Timestamp Log**
- Using `Properties` in **LAS X software**, create an Excel file in the `logs/` folder named:
  ```
  imaging_timestamp.xlsx
  ```
- Include the following columns:
  - `Image#`
  - `Absolute Time`
  - `Date`
- The first row should be:
  ```
  Image# = 0
  ```
  marking the beginning of the experiment.

---

## **Process Images**

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
- After applying the mask, **compare the alignment**. If it looks good, choose **'YES'**.
- All aligned images are saved in:
  ```
  processed_images/registered_images/
  ```

### **Background Subtraction and DO Ratio calculation**
- Open and run in MATLAB:
  ```
  backSub_do.m
  ```
- All background subtracted images and DO Ratio data are saved in:
  ```
  processed_images/background_subtracted/
  processed_data/do_ratio/
  ```

---
