@echo off
setlocal

:: Get the full path of the directory where this batch file is located (e.g., C:\Projects\MyExperimentProject\analysis_scripts\)
set "CURRENT_SCRIPT_LOCATION=%~dp0"

echo.
echo Running script from: "%CURRENT_SCRIPT_LOCATION%"

:: Navigate to the parent directory of analysis_scripts.
:: This parent directory will now be considered the main project folder.
pushd "%CURRENT_SCRIPT_LOCATION%"
cd ..
set "MAIN_PROJECT_PATH=%CD%"
popd

echo Setting the main project path to: "%MAIN_PROJECT_PATH%"

:: Change directory to the main project path (the parent of analysis_scripts)
cd "%MAIN_PROJECT_PATH%"

:: --- Create Raw Data Folders ---
echo.
echo Creating Raw Data folders...
mkdir "raw_data"
mkdir "raw_data\images"
mkdir "raw_data\images\tif_images"
mkdir "raw_data\sensor_readings"

:: --- Create Processed Data Folder ---
echo.
echo Creating Processed Data folder...
mkdir "processed_data"
mkdir "processed_data\do_ratio"

:: --- Create Processed Images Folders ---
echo.
echo Creating Processed Images folders...
mkdir "processed_images"
mkdir "processed_images\grain_mask"
mkdir "processed_images\registered_images"
mkdir "processed_images\background_subtracted"

:: --- Create Logs Folder ---
echo.
echo Creating Logs folder...
mkdir "logs"

:: --- Create Docs Folder ---
echo.
echo Creating Docs folder...
mkdir "docs"

echo.
echo Folder structure created successfully within "%MAIN_PROJECT_PATH%"!
echo The 'analysis_scripts' folder is already in place.
echo.
pause
endlocal