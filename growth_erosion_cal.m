clear; clc; close all;

%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Subtracted images path
cd(projectPath);
cd('processed_images\background_subtracted\');
backSunPath = pwd;

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

% mat file
cd(projectPath);
cd('processed_data\growth_erosion');
matFolder = pwd;

% File pattern
filePattern = '*.tif';

% Optional preprocessing
smoothSigma = 0;          % 0 = no smoothing, try 1 if noisy
thresholdDiff = 0.00;     % ignore tiny changes below this normalized value
useCommonCrop = true;     % crop all images to common minimum size
saveAsUint16 = true;      % save outputs as uint16 TIFF

%% =========================
% READ FILE LIST
%% =========================
imgFiles = dir(fullfile(backSunPath, filePattern));

if isempty(imgFiles)
    error('No TIFF files found in inputFolder.');
end

% Natural sort
fileNames = {imgFiles.name};
[~, sortIdx] = sort_nat(fileNames);
imgFiles = imgFiles(sortIdx);

nFrames = numel(imgFiles);

if nFrames < 2
    error('At least 2 TIFF images are required.');
end

fprintf('Found %d TIFF files.\n', nFrames);

%% =========================
% DETERMINE COMMON SIZE
%% =========================
% if useCommonCrop
%     allRows = zeros(nFrames,1);
%     allCols = zeros(nFrames,1);
% 
%     for k = 1:nFrames
%         I = imread(fullfile(backSunPath, imgFiles(k).name));
%         if ndims(I) > 2
%             I = rgb2gray(I);
%         end
%         allRows(k) = size(I,1);
%         allCols(k) = size(I,2);
%     end
% 
%     minRows = min(allRows);
%     minCols = min(allCols);
% 
%     fprintf('Cropping all images to common size: %d x %d\n', minRows, minCols);
% else
    I0 = imread(fullfile(backSunPath, imgFiles(1).name));
    if ndims(I0) > 2
        I0 = rgb2gray(I0);
    end
    minRows = size(I0,1);
    minCols = size(I0,2);
% end

%% =========================
% READ FIRST IMAGE
%% =========================
prev = readRawImage(fullfile(backSunPath, imgFiles(1).name), minRows, minCols, smoothSigma);

metricsMatFile = fullfile(matFolder, 'growth_erosion.mat');

% Preallocate lightweight result arrays only (not images)
growthAbs  = nan(nFrames-1, 1, 'single');
erosionAbs = nan(nFrames-1, 1, 'single');
netAbs     = nan(nFrames-1, 1, 'single');

growthPct  = nan(nFrames-1, 1, 'single');
erosionPct = nan(nFrames-1, 1, 'single');
netPct     = nan(nFrames-1, 1, 'single');

previousTotalBiomass = nan(nFrames-1, 1, 'single');
prevImageName = strings(nFrames-1,1);
currImageName = strings(nFrames-1,1);

% Save an initial MAT file so progress is preserved during the run
save(metricsMatFile, ...
    'growthAbs', 'erosionAbs', 'netAbs', ...
    'growthPct', 'erosionPct', 'netPct', ...
    'previousTotalBiomass', 'prevImageName', 'currImageName', ...
    '-v7.3');

fprintf('Metric results will be saved incrementally in:\n%s\n', metricsMatFile);

%% =========================
% LOOP THROUGH SUCCESSIVE PAIRS
%% =========================
for k = 2:nFrames
    curr = readRawImage(fullfile(backSunPath, imgFiles(k).name), minRows, minCols, smoothSigma);

    % Difference image
    dI = curr - prev;

    %% =========================
    % CREATE NET RGB IMAGE (visualization only)
    %% =========================
    
    % --- Visualization scaling (NOT scientific normalization) ---
    % Use a robust percentile to avoid outliers blowing up contrast
    pHigh = 99.5;   % adjust if needed
    
    scaleVal = prctile(abs(dI(:)), pHigh);
    if scaleVal == 0
        scaleVal = 1;  % avoid division by zero
    end
    
    % Scale to [0,1] for display only
    dI_scaled = dI / scaleVal;
    dI_scaled = max(min(dI_scaled, 1), -1);  % clip to [-1, 1]
    
    % --- Build RGB channels ---
    % Start with neutral gray
    grayLevel = 0.5;
    
    R = ones(size(dI_scaled), 'single') * grayLevel;
    G = ones(size(dI_scaled), 'single') * grayLevel;
    B = ones(size(dI_scaled), 'single') * grayLevel;
    
    % Growth (positive) → green
    posMask = dI_scaled > 0;
    G(posMask) = grayLevel + 0.5 * dI_scaled(posMask);
    
    % Erosion (negative) → red
    negMask = dI_scaled < 0;
    R(negMask) = grayLevel + 0.5 * abs(dI_scaled(negMask));
    
    % Optional: slightly reduce blue to enhance contrast
    B(posMask | negMask) = grayLevel * 0.7;
    
    % Combine into RGB image
    netRGB = cat(3, R, G, B);

    %% Resize for visualization
    maxWidth = 2000;
    
    [rows, cols, ~] = size(netRGB);
    
    if cols > maxWidth
        scaleFactor = maxWidth / cols;
        netRGB = imresize(netRGB, scaleFactor, 'bilinear');
    end

    % Apply small-change threshold if desired
    if thresholdDiff > 0
        dI(abs(dI) < thresholdDiff) = 0;
    end

    % Growth = positive changes
    growthImg = max(dI, 0);

    % Erosion = magnitude of negative changes
    erosionImg = max(-dI, 0);

    % Build output filenames
    prevName = erase(imgFiles(k-1).name, '.tif');
    currName = erase(imgFiles(k).name, '.tif');

    growthName  = sprintf('growth_%s_to_%s.tif', prevName, currName);
    erosionName = sprintf('erosion_%s_to_%s.tif', prevName, currName);
    netName = sprintf('net_%s_to_%s.tif', prevName, currName);

    % Save outputs
    if saveAsUint16
        imwrite(toUint16Raw(growthImg),  fullfile(growthPath, growthName));
        imwrite(toUint16Raw(erosionImg), fullfile(erosionPath, erosionName));
        netRGB_uint8 = uint8(255 * netRGB);
        imwrite(netRGB_uint8, fullfile(netPath, netName));
    else
        imwrite(growthImg,  fullfile(growthPath, growthName));
        imwrite(erosionImg, fullfile(erosionPath, erosionName));
        imwrite(netRGB, fullfile(netPath, netName));
    end
    
    

    

    fprintf('Saved pair %d/%d: %s -> %s\n', k-1, nFrames-1, imgFiles(k-1).name, imgFiles(k).name);
    
    %% -------------------------
    % Calculate %growth, %erosion, %net for this image pair
    % Denominator = total biomass in previous frame
    %% -------------------------
    denom = sum(prev(:), 'omitnan');   % previous total biomass
    gAbs  = sum(growthImg(:), 'omitnan');
    eAbs  = sum(erosionImg(:), 'omitnan');
    nAbs  = gAbs - eAbs;

    if denom > 0
        gPct = 100 * gAbs / denom;
        ePct = 100 * eAbs / denom;
        nPct = 100 * nAbs / denom;
    else
        gPct = NaN;
        ePct = NaN;
        nPct = NaN;
    end

    % Store only scalar results for this interval
    idx = k - 1;
    growthAbs(idx)  = single(gAbs);
    erosionAbs(idx) = single(eAbs);
    netAbs(idx)     = single(nAbs);

    growthPct(idx)  = single(gPct);
    erosionPct(idx) = single(ePct);
    netPct(idx)     = single(nPct);

    previousTotalBiomass(idx) = single(denom);
    prevImageName(idx) = string(imgFiles(k-1).name);
    currImageName(idx) = string(imgFiles(k).name);

    % Save progress to MAT file after each image pair
    save(metricsMatFile, ...
        'growthAbs', 'erosionAbs', 'netAbs', ...
        'growthPct', 'erosionPct', 'netPct', ...
        'previousTotalBiomass', 'prevImageName', 'currImageName', ...
        '-v7.3');

    % Terminal print for each calculation
    fprintf(['Calculated metrics %d/%d: %s -> %s | ' ...
             'Growth = %.4f%%, Erosion = %.4f%%, Net = %.4f%%\n'], ...
             idx, nFrames-1, imgFiles(k-1).name, imgFiles(k).name, ...
             gPct, ePct, nPct);

    % Remove temporary scalar/image variables from memory
    clear denom gAbs eAbs nAbs gPct ePct nPct idx growthImg erosionImg dI

    % Move current to previous
    prev = curr;
end

fprintf('\nDone.\nGrowth images saved in:\n%s\n', growthPath);
fprintf('Erosion images saved in:\n%s\n', erosionPath);

%% =========================
% HELPER FUNCTIONS
%% =========================

function I = readRawImage(imgPath, nRows, nCols, smoothSigma)
    Iraw = imread(imgPath);

    if ndims(Iraw) > 2
        Iraw = rgb2gray(Iraw);
    end

    % Crop to common size
    Iraw = Iraw(1:nRows, 1:nCols);

    % Convert only to single, NO normalization
    I = single(Iraw);

    if smoothSigma > 0
        I = imgaussfilt(I, smoothSigma);
    end
end

function out = toUint16Raw(I)
    I = max(I, 0);              % no negative values for growth/erosion
    I = min(I, 65535);          % clip only to uint16 range
    out = uint16(I);
end

function [sortedStrings, sortIndex] = sort_nat(strings)
    padded = regexprep(strings, '\d+', '${sprintf(''%010d'', str2double($0))}');
    [~, sortIndex] = sort(lower(padded));
    sortedStrings = strings(sortIndex);
end
