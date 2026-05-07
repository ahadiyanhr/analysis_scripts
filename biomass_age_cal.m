%% Build biomass age stack from thresholded images
% Input image convention (n×m double):
%   NaN       = void / outside region of interest (permanent mask)
%   0         = no biomass
%   (0, 1]    = biomass present (1 = full biomass)
%
% Output ageFrame convention:
%   NaN       = void pixel  OR  pixel that just sloughed this frame
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

% Experiment time in hours
time_hr = hours(datetimeList - datetimeList(1));

%% -------- Load first image to get dimensions & void mask --------

firstData = load(fullfile(threshPath, bioFiles(1).name));
firstField = fieldnames(firstData);
firstImg = firstData.(firstField{1});   % grab whatever variable is inside

[rows, cols] = size(firstImg);

%% -------- Load grain mask --------
% Grain mask convention (n×m logical or double):
%   true / 1  = grain (solid, void — excluded from analysis)
%   false / 0 = open pore space (valid region for biomass)
alignmentFile = fullfile(logsPath, 'manual_alignment.mat');
load(alignmentFile, 'GM_Final');
disp('Loaded saved grain mask from logs folder.');

voidMask  = GM_Final == 1;   % force logical

fprintf('Image size: %d x %d  |  Grain (void) pixels: %d  |  Pore pixels: %d\n', ...
    rows, cols, sum(voidMask(:)), sum(~voidMask(:)));

%% -------- Save metadata --------

m.time_hr        = time_hr;
m.datetimeList   = datetimeList;
m.imageNumber    = imageNumber;
m.timestampOffset = timestampOffset;
m.voidMask       = voidMask;

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

    %% Occupancy: biomass present = not void AND above threshold
    occupied = ~isnan(img);

    currentTime = single(time_hr(i));

    %% Initialise frame:
    %  - void pixels → NaN  (region of no interest, never changes)
    %  - valid pixels → 0   (no biomass; will be overwritten for biomass pixels)
    ageFrame = zeros(rows, cols, 'single');
    ageFrame(voidMask) = NaN;

    %% Classify pixel transitions (void pixels are excluded via 'occupied')
    newlyOccupied = occupied & ~prevOccupied;   % just appeared
    stillOccupied = occupied &  prevOccupied;   % continuous biomass
    sloughed      = ~occupied & prevOccupied & ~voidMask; % had biomass, now gone

    %% Update growth start time for newly colonised pixels
    growthStartTime(newlyOccupied) = currentTime;

    %% Compute age for all currently occupied pixels
    ageFrame(occupied) = currentTime - growthStartTime(occupied);

    %% Mark sloughed pixels as NaN only in this frame, then reset their timer
    ageFrame(sloughed)          = NaN;
    growthStartTime(sloughed)   = NaN;

    %% Save frame
    fileName = sprintf('biomass_age_%03d.mat', i);
    save(fullfile(ageDistPath, fileName), 'ageFrame', 'currentTime');

    %% Update occupancy for next iteration
    prevOccupied = occupied;

    fprintf('Processed image %d/%d\n', i, nImages);
end

fprintf('Done. All biomass age files saved to:\n  %s\n', ageDistPath);
