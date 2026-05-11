%% Build biomass age stack from thresholded images
% Input image convention (n×m double):
%   NaN       = void / outside region of interest (permanent mask)
%   0         = no biomass
%   (0, 1]    = biomass present (1 = full biomass)
%
% Output ageFrame convention:
%   NaN       = grain/void pixel (permanent, from voidMask)
%   -1        = pixel that just sloughed this frame        % FIX: was NaN
%   0         = valid pixel with no biomass
%   >0        = biomass age in hours

clear; clc; close all;

%% -------- Setup --------

mainPath = pwd;

cd(mainPath);
cd('../');
projectPath = pwd;

% Thresholded MAT files path
cd(projectPath);
cd('processed_images\thresholded_images\');
threshRootPath = pwd;
mainResultsFolder = dir(fullfile(threshRootPath, '*_main_results'));
threshPath = fullfile(threshRootPath, mainResultsFolder(1).name);

% Output folder
ageDistPath = fullfile(projectPath, 'processed_data', 'biomass_age');

% Logs path
logsPath = fullfile(projectPath, 'logs');

% Timestamp file
timestampFile = fullfile(logsPath, 'imaging_timestamp.xlsx');

% Logs path
cd(projectPath);
cd('logs\');
logsPath = pwd;

% IMPORTANT:
% If your thresholded images start from image #2 in the timestamp list,
% set timestampOffset = 1. bioFiles(1) then corresponds to timestamp row 2.
timestampOffset = 1;

%% -------- Read thresholded .mat files --------

bioFiles = dir(fullfile(threshPath, '*.mat'));

if isempty(bioFiles)
    error('No .mat files found in: %s', threshPath);
end

[~, idxB] = sort({bioFiles.name});
bioFiles = bioFiles(idxB);

nImages = numel(bioFiles);
fprintf('Found %d thresholded images.\n', nImages);

%% -------- Read timestamps --------

T = readtable(timestampFile);

imageNumber = T{:,1};
datetimeRaw = T{:,2};

if isdatetime(datetimeRaw)
    datetimeList = datetimeRaw;
elseif isnumeric(datetimeRaw)
    datetimeList = datetime(datetimeRaw, 'ConvertFrom', 'excel');
elseif iscell(datetimeRaw)
    datetimeList = datetime(datetimeRaw);
elseif isstring(datetimeRaw) || ischar(datetimeRaw)
    datetimeList = datetime(datetimeRaw);
else
    error('Unknown datetime format in timestamp file.');
end

%% -------- Load flowrate and pressure to find shared t0 --------
% Mirrors exactly what the three-panel plot does:
%   t0 = min([t_q; t_p; t_img])

cd(projectPath);
cd('processed_data\pq_cleaned_data\');
pdCleanedPath = pwd;

TTq = readtable(fullfile(pdCleanedPath, 'cleaned_flowrate.csv'), 'TextType', 'string');
TTq.datetime = datetime(TTq.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
t_q = TTq.datetime(:);

TTp = readtable(fullfile(pdCleanedPath, 'cleaned_pressures.csv'), 'TextType', 'string');
TTp.datetime = datetime(TTp.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
t_p = TTp.datetime(:);

t0 = min([t_q; t_p; datetimeList]);   % identical to three-panel plot

fprintf('Shared t0: %s\n', datestr(t0));

% Return to logs path for the rest of the script
cd(projectPath);
cd('logs\');
logsPath = pwd;

%% -------- Match timestamps to available images --------

nTimestamps = numel(datetimeList);

startIdx = 1 + timestampOffset;
endIdx   = min(nImages + timestampOffset, nTimestamps);

validTimestampIdx = startIdx:endIdx;

datetimeList = datetimeList(validTimestampIdx);
imageNumber  = imageNumber(validTimestampIdx);

nImages  = numel(datetimeList);
bioFiles = bioFiles(1:nImages);

fprintf('Using %d images with matching timestamps.\n', nImages);

% Use shared t0 — now aligned with the three-panel plot
time_hr = hours(datetimeList - t0);   % CHANGED: was datetimeList(1)

%% -------- Load first image to get dimensions & void mask --------

firstData = load(fullfile(threshPath, bioFiles(1).name));
firstField = fieldnames(firstData);
firstImg = firstData.(firstField{1});

[rows, cols] = size(firstImg);

%% -------- Load grain mask --------
alignmentFile = fullfile(logsPath, 'manual_alignment.mat');
load(alignmentFile, 'GM_Final');
disp('Loaded saved grain mask from logs folder.');

voidMask = GM_Final == 1;   % force logical

fprintf('Image size: %d x %d  |  Grain (void) pixels: %d  |  Pore pixels: %d\n', ...
    rows, cols, sum(voidMask(:)), sum(~voidMask(:)));

%% -------- Save metadata --------

m.time_hr         = time_hr;
m.datetimeList    = datetimeList;
m.imageNumber     = imageNumber;
m.timestampOffset = timestampOffset;
m.voidMask        = voidMask;

%% -------- Build biomass age stack --------

% Tracks when biomass most recently started at each pixel
growthStartTime = nan(rows, cols, 'single');

% Tracks whether each pixel was occupied in the previous frame
prevOccupied = false(rows, cols);

fprintf('Building biomass age stack...\n');

for i = 1:nImages

    %% Load thresholded image
    data  = load(fullfile(threshPath, bioFiles(i).name));
    field = fieldnames(data);
    img   = double(data.(field{1}));

    %% FIX: Occupancy now requires actual biomass signal (img > 0)
    %  Previously ~isnan(img) wrongly treated zero-biomass pore pixels as occupied.
    %  Grain pixels are NaN in img, so img > 0 already excludes them too.
    occupied = img > 0;

    currentTime = single(time_hr(i));

    %% Initialise frame:
    %  - void pixels → NaN  (permanent grain mask, never changes)
    %  - valid pixels → 0   (no biomass; overwritten below for biomass pixels)
    ageFrame = zeros(rows, cols, 'single');
    ageFrame(voidMask) = NaN;

    %% Classify pixel transitions
    newlyOccupied = occupied & ~prevOccupied;
    stillOccupied = occupied &  prevOccupied;
    sloughed      = ~occupied & prevOccupied & ~voidMask;

    %% Update growth start time for newly colonised pixels
    growthStartTime(newlyOccupied) = currentTime;

    %% Compute age for all currently occupied pixels
    ageFrame(occupied) = currentTime - growthStartTime(occupied);

    %% FIX: Mark sloughed pixels as -1 instead of NaN
    %  This keeps them distinguishable from permanent grain/void pixels (NaN).
    ageFrame(sloughed)        = -1;
    growthStartTime(sloughed) = NaN;   % reset timer for future recolonisation

    %% FIX: Save sloughed mask explicitly alongside ageFrame
    %  Downstream code can now cleanly separate all four pixel states:
    %    NaN          → grain/void (use voidMask)
    %    -1           → just sloughed this frame (use sloughedMask)
    %    0            → pore, no biomass
    %    > 0          → active biomass, value = age in hours
    sloughedMask = sloughed;   % logical m×n, true where sloughing occurred
    save(fullfile(ageDistPath, sprintf('biomass_age_%03d.mat', i)), ...
        'ageFrame', 'currentTime', 'sloughedMask');

    %% Update occupancy for next iteration
    prevOccupied = occupied;

    fprintf('Processed image %d/%d\n', i, nImages);
end

fprintf('Done. All biomass age files saved to:\n  %s\n', ageDistPath);
