clear; clc; close all;

%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Thresholded MAT files path
cd(projectPath);
cd('processed_images\thresholded_images\');
threshRootPath = pwd;
mainResultsFolder = dir(fullfile(threshRootPath, '*_main_results'));
threshPath = fullfile(threshRootPath, mainResultsFolder(1).name);

% Growth folder
cd(projectPath);
cd('processed_images\growth_erosion_images\growth\');
growthPath = pwd;

% Erosion folder
cd(projectPath);
cd('processed_images\growth_erosion_images\erosion\');
erosionPath = pwd;

% Net folder
cd(projectPath);
cd('processed_images\growth_erosion_images\net_visual\');
netPath = pwd;

% Add this in the Setup section
cd(projectPath);
cd('logs\');
logsPath = pwd;

% mat file
cd(projectPath);
cd('processed_data\growth_erosion_timepoints');
matFolder = pwd;

% File pattern  (*** changed from *.tif ***)
filePattern = '*.mat';

% Optional preprocessing
smoothSigma    = 0;      % 0 = no smoothing, try 1 if noisy
thresholdDiff  = 0.00;   % ignore tiny changes below this normalised value
useCommonCrop  = true;   % crop all images to common minimum size
saveAsUint16   = true;   % save growth/erosion outputs as uint16 TIFF

%% -------- LOAD MASK FILE --------
% Load saved alignment
alignmentFile = fullfile(logsPath, 'manual_alignment.mat');
load(alignmentFile, 'GM_Final');
disp('Loaded final Grain Mask from logs folder.');


%% =========================
% READ FILE LIST
%% =========================
imgFiles = dir(fullfile(threshPath, filePattern));

if isempty(imgFiles)
    error('No MAT files found in threshPath.');
end

% Natural sort
fileNames = {imgFiles.name};
[~, sortIdx] = sort_nat(fileNames);
imgFiles = imgFiles(sortIdx);

nFrames = numel(imgFiles);

if nFrames < 2
    error('At least 2 MAT files are required.');
end

fprintf('Found %d MAT files.\n', nFrames);

%% =========================
% DETERMINE COMMON SIZE
%% =========================
% Read first frame to get reference size.
% (If your MAT files have different sizes, re-enable the full loop below.)
I0 = loadMatImage(fullfile(threshPath, imgFiles(1).name));
minRows = size(I0, 1);
minCols = size(I0, 2);
fprintf('Reference size from first frame: %d x %d\n', minRows, minCols);

% ---- Full loop version (uncomment if frames have inconsistent sizes) ----
% allRows = zeros(nFrames,1);  allCols = zeros(nFrames,1);
% for k = 1:nFrames
%     Itmp = loadMatImage(fullfile(threshPath, imgFiles(k).name));
%     allRows(k) = size(Itmp,1);  allCols(k) = size(Itmp,2);
% end
% minRows = min(allRows);  minCols = min(allCols);
% fprintf('Cropping all frames to common size: %d x %d\n', minRows, minCols);

%% =========================
% LOAD GRAIN MASK & COMPUTE TOTAL PORE AREA
%% =========================
% Convention: 0 = pore (open space), 1 = grain (solid).

% Pore pixels are where the mask equals 0
poreMask = sum(GM_Final(:) == 0);
fprintf('Total pore pixels: %d\n', poreMask);
totalPoreArea = sum(poreMask(:));   % scalar, fixed for whole experiment

fprintf('Total pore area (pixels): %d\n', totalPoreArea);

if totalPoreArea == 0
    error('Grain mask has no pore pixels (no zeros found). Check mask convention.');
end

%% =========================
% READ FIRST IMAGE
%% =========================
prev = readMatFrame(fullfile(threshPath, imgFiles(1).name), minRows, minCols, smoothSigma);

metricsMatFile = fullfile(matFolder, 'growth_erosion.mat');

% Preallocate lightweight result arrays only (not images)
growthAbs  = nan(nFrames-1, 1, 'single');
erosionAbs = nan(nFrames-1, 1, 'single');
netAbs     = nan(nFrames-1, 1, 'single');

growthPct  = nan(nFrames-1, 1, 'single');
erosionPct = nan(nFrames-1, 1, 'single');
netPct     = nan(nFrames-1, 1, 'single');

previousTotalBiomass = nan(nFrames-1, 1, 'single');
prevImageName = strings(nFrames-1, 1);
currImageName = strings(nFrames-1, 1);

% Save an initial MAT file so progress is preserved during the run
save(metricsMatFile, ...
    'growthAbs', 'erosionAbs', 'netAbs', ...
    'growthPct', 'erosionPct', 'netPct', ...
    'previousTotalBiomass', 'prevImageName', 'currImageName', ...
    'totalPoreArea', ...
    '-v7.3');

fprintf('Metric results will be saved incrementally in:\n%s\n', metricsMatFile);

%% =========================
% LOOP THROUGH SUCCESSIVE PAIRS
%% =========================
for k = 2:nFrames
    curr = readMatFrame(fullfile(threshPath, imgFiles(k).name), minRows, minCols, smoothSigma);

    % Difference image
    % Both prev and curr are single, NaNs already replaced with 0,
    % so values live in [0, 1].  Positive diff = growth, negative = erosion.
    dI = curr - prev;

    %% =========================
    % CREATE NET RGB IMAGE (visualization only)
    %% =========================

    % Robust percentile scaling to avoid outlier contrast collapse
    pHigh    = 99.5;
    scaleVal = prctile(abs(dI(:)), pHigh);
    if scaleVal == 0
        scaleVal = 1;
    end

    dI_scaled = dI / scaleVal;
    dI_scaled = max(min(dI_scaled, 1), -1);   % clip to [-1, 1]

    % Build RGB channels (neutral gray background)
    grayLevel = 0.5;
    R = ones(size(dI_scaled), 'single') * grayLevel;
    G = ones(size(dI_scaled), 'single') * grayLevel;
    B = ones(size(dI_scaled), 'single') * grayLevel;

    % Growth (positive diff) → green
    posMask = dI_scaled > 0;
    G(posMask) = grayLevel + 0.5 * dI_scaled(posMask);

    % Erosion (negative diff) → red
    negMask = dI_scaled < 0;
    R(negMask) = grayLevel + 0.5 * abs(dI_scaled(negMask));

    % Slightly reduce blue for contrast
    B(posMask | negMask) = grayLevel * 0.7;

    netRGB = cat(3, R, G, B);

    % Resize for visualization
    maxWidth = 2000;
    [rows, cols, ~] = size(netRGB);
    if cols > maxWidth
        netRGB = imresize(netRGB, maxWidth / cols, 'bilinear');
    end

    % Apply small-change threshold if desired
    if thresholdDiff > 0
        dI(abs(dI) < thresholdDiff) = 0;
    end

    % 1 where pore, 0 where grain
    poreBinaryMask = (GM_Final(1:minRows, 1:minCols) == 0);
    
    % Mask the difference image
    dI_masked = dI .* single(poreBinaryMask);

    % Growth = positive changes; Erosion = magnitude of negative changes
    growthImg  = max( dI, 0);
    erosionImg = max(-dI, 0);

    % Build output filenames  (*** strip .mat instead of .tif ***)
    prevName = erase(imgFiles(k-1).name, '.mat');
    currName = erase(imgFiles(k).name,   '.mat');

    growthName  = sprintf('growth_%s_to_%s.tif',  prevName, currName);
    erosionName = sprintf('erosion_%s_to_%s.tif', prevName, currName);
    netName     = sprintf('net_%s_to_%s.tif',     prevName, currName);

    % Save outputs
    if saveAsUint16
        % *** scale [0,1] → [0,65535] before uint16 conversion ***
        imwrite(toUint16Scaled(growthImg),  fullfile(growthPath, growthName));
        imwrite(toUint16Scaled(erosionImg), fullfile(erosionPath, erosionName));
        netRGB_uint8 = uint8(255 * netRGB);
        imwrite(netRGB_uint8, fullfile(netPath, netName));
    else
        imwrite(growthImg,  fullfile(growthPath, growthName));
        imwrite(erosionImg, fullfile(erosionPath, erosionName));
        imwrite(netRGB,     fullfile(netPath, netName));
    end

    fprintf('Saved pair %d/%d: %s -> %s\n', k-1, nFrames-1, imgFiles(k-1).name, imgFiles(k).name);

    %% -------------------------
    % Calculate %growth, %erosion, %net for this image pair
    % Denominator = total pore area from grain mask (fixed for whole experiment)
    % so percentages express how much of the available pore space
    % gained or lost biomass between frames.
    %% -------------------------
    prevBiomass = sum(prev(:), 'omitnan');   % store for reference only
    gAbs  = sum(growthImg(:),  'omitnan');
    eAbs  = sum(erosionImg(:), 'omitnan');
    nAbs  = gAbs - eAbs;

    % Use totalPoreArea (grain mask) as the fixed denominator
    gPct = 100 * gAbs / totalPoreArea;
    ePct = 100 * eAbs / totalPoreArea;
    nPct = 100 * nAbs / totalPoreArea;

    % Store scalar results for this interval
    idx = k - 1;
    growthAbs(idx)  = single(gAbs);
    erosionAbs(idx) = single(eAbs);
    netAbs(idx)     = single(nAbs);

    growthPct(idx)  = single(gPct);
    erosionPct(idx) = single(ePct);
    netPct(idx)     = single(nPct);

    previousTotalBiomass(idx) = single(prevBiomass);
    prevImageName(idx) = string(imgFiles(k-1).name);
    currImageName(idx) = string(imgFiles(k).name);

    % Save progress to MAT file after each image pair
    save(metricsMatFile, ...
        'growthAbs', 'erosionAbs', 'netAbs', ...
        'growthPct', 'erosionPct', 'netPct', ...
        'previousTotalBiomass', 'prevImageName', 'currImageName', ...
        'totalPoreArea', ...
        '-v7.3');

    % Terminal print for each calculation
    fprintf(['Calculated metrics %d/%d: %s -> %s | ' ...
             'Growth = %.4f%%, Erosion = %.4f%%, Net = %.4f%%\n'], ...
             idx, nFrames-1, imgFiles(k-1).name, imgFiles(k).name, ...
             gPct, ePct, nPct);

    % Free temporary variables
    clear prevBiomass gAbs eAbs nAbs gPct ePct nPct idx growthImg erosionImg dI

    % Advance frame
    prev = curr;
end

fprintf('\nDone.\nGrowth images saved in:\n%s\n', growthPath);
fprintf('Erosion images saved in:\n%s\n', erosionPath);

%% =========================
% HELPER FUNCTIONS
%% =========================

% --- Low-level loader: returns raw double matrix from a MAT file ---
function I = loadMatImage(matPath)
    S      = load(matPath);
    fields = fieldnames(S);
    I      = double(S.(fields{1}));   % grab whichever variable is stored
end

% --- Full read + crop + NaN-fill + smooth (replaces readRawImage) ---
function I = readMatFrame(matPath, nRows, nCols, smoothSigma)
    Iraw = loadMatImage(matPath);

    % Replace NaN (no-biomass background) with 0 so arithmetic is clean.
    % A background→biomass transition will appear as positive diff (growth),
    % and a biomass→background transition as negative diff (erosion).
    Iraw(isnan(Iraw)) = 0;

    % Crop to common size
    Iraw = Iraw(1:nRows, 1:nCols);

    % Work in single precision (matches original pipeline)
    I = single(Iraw);

    if smoothSigma > 0
        I = imgaussfilt(I, smoothSigma);
    end
end

% --- Scale [0,1] float to full uint16 range for TIFF saving ---
% (Original toUint16Raw assumed pixel values were already in [0,65535];
%  MAT data lives in [0,1] so we multiply before casting.)
function out = toUint16Scaled(I)
    I   = max(I, 0);          % no negatives for growth/erosion images
    I   = I * 65535;          % *** scale from [0,1] to uint16 range ***
    I   = min(I, 65535);      % safety clip
    out = uint16(I);
end

% --- Natural sort (unchanged) ---
function [sortedStrings, sortIndex] = sort_nat(strings)
    padded = regexprep(strings, '\d+', '${sprintf(''%010d'', str2double($0))}');
    [~, sortIndex] = sort(lower(padded));
    sortedStrings  = strings(sortIndex);
end
