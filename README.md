# 📊 Data Analysis Protocol for Microfluidic Experiments

This repository provides macros and scripts to support the analysis of pressure/flow sensor data and microscopy images (Brightfield, GFP, FRET) from micromodel experiments. The protocol uses Fiji (ImageJ) and MATLAB for preprocessing, segmentation, and alignment.

---

## **Pre-processing**

### **Folder Structure Setup**
- Clone the `analysis_scripts` repository from GitHub into the **main root** of the experiment folder.
- Run `create_project_folders.bat` from within the `analysis_scripts` folder to generate all required folders and subfolders as below:

## 📁 Project Folder Structure

```
YourExperimentProject/
├── raw_data/                 # Original, untouched raw data (images, sensor data)
│   ├── images/
│   └── sensor_readings/
│
├── processed_data/           # Final, polished outputs of processing (e.g., CSVs of measurements, analysis reports)
│
├── processed_images/         # Specific image-based outputs (masks, cropped, overlays)
│   ├── masks/                # For grain masks, segmentation masks, etc.
│   │   ├── grain_masks/
│   │   └── cell_masks/
│   ├── cropped_regions/      # For images that have been cropped
│   └── overlays/             # For images with timestamps, ROIs, or other data overlaid
│       └── timestamped_images/
│
├── analysis_scripts/         # Your Fiji macros, MATLAB functions/scripts
│
├── config/                   # Settings, thresholds, specific paths, instrument settings
│   ├── analysis_parameters.json
│   ├── sensor_thresholds.csv
│   └── camera_calibration.yaml
│
├── lookup_tables/            # Reference data for mapping or classification
│   └── material_properties.csv
│
├── intermediates/            # Data generated during processing, used by subsequent steps, but not final outputs
│   ├── feature_vectors/      # e.g., features extracted from images before classification
│   └── normalized_readings/  # e.g., sensor data after normalization
│
├── resources/                # Large supporting files (e.g., pre-trained models, specific templates)
│   └── pre_trained_model.h5
│
├── logs/                     # Log files from script execution
│
└── docs/                     # Project documentation, READMEs, notes
```
/

- Save all `test_report` files in the `docs/` folder.

---

## **Copy Sensor Data**
- Place the pressure and flow sensor `.txt` files in:
  ```
  raw_data/sensor_readings/
  ```
- Use the following filename formats:
  - *Constant pressure experiments:* `pconst_ob1.txt`, `pconst_reader.txt`
  - *Constant flow rate experiments:* `qconst_ob1.txt`, `qconst_reader.txt`

---

## **Copy Experimental Images**
- Copy the Leica imaging project file to:
  ```
  raw_data/images/
  ```
- Export all image channels (Brightfield, GFP, FRET) from **LAS X software** into:
  ```
  raw_data/images/tif_images/
  ```
  as `.tif` files.
- File naming convention (done automatically by LAS X):
  - `..._ch00.tif` → Brightfield
  - `..._ch01.tif` → GFP
  - `..._ch02.tif` → FRET

---

## **Create Imaging Timestamp Log**
- Create an Excel file in the `logs/` folder named:
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

## **ROI Creation (Region of Interest)**
- Open **Fiji/ImageJ**
- Load the first Brightfield image from:
  ```
  raw_data/images/tif_images/
  ```
- Draw a rectangular ROI over the micromodel area.
- In the ROI Manager:
  - Add the selection
  - Rotate via `More > Rotate`
  - Align corners to fit the micromodel edges
  - Add again to the ROI Manager
- Save as:
  ```
  logs/crop.roi
  ```

---

## **Process Images**

### **Image Alignment and Cropping (Brightfield Only)**
- Open and run the macro:
  ```
  image_alignment.ijm
  ```
- Set `channelID = 'ch00'` for Brightfield.
> *Note:* Do **not** use this for GFP or FRET. These will be aligned later using MATLAB.
- Save the transformation log as:
  ```
  logs/transform.txt
  ```

---

### **Mask Refinement**
- Open the following two files as a stack in Fiji:
  - `mask.tif`
  - `t00_ch00.tif` (from `processed_images/modified_images/`)
- Align using SIFT and crop to the original image size.
- Apply outlier removal:
  ```
  Process > Noise > Remove Outliers
  Radius: 7.5 | Threshold: 75 | Outliers: Bright
  ```
- Save the result as:
  ```
  processed_images/grain_mask/mask.tif
  ```

---

### **Biomass Segmentation**
- Open and run:
  ```
  biomass_segmentation.ijm
  ```
- Set thresholding parameters and run the macro.
- Results are saved in:
  ```
  processed_images/biomass_images_*/
  ```
- Threshold settings saved as:
  ```
  thresholding_parameters.txt
  ```

---

> For alignment of GFP/FRET channels, use MATLAB scripts instead of Fiji.
