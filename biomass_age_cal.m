%% Build biomass age stack from background-subtracted BF images
% 0   = no biomass
% NaN = biomass was present before, but disappeared at this time step
% >0  = biomass age in hours

clear; clc; close all;

%% -------- Setup --------

mainPath = pwd;

cd(mainPath);
cd('../');
mainPath = pwd;

% Background-subtracted BF images
backSubPath = fullfile(mainPath, 'processed_images', 'background_subtracted');

% Output folder
erosionDistPath = fullfile(mainPath, 'processed_data', 'biomass_age');

% Logs path
logsPath = fullfile(mainPath, 'logs');

% Timestamp file
timestampFile = fullfile(logsPath, 'imaging_timestamp.xlsx');

% Biomass threshold
bioThreshold = 1000;

% IMPORTANT:
% If your background-subtracted images start from BF image #2,
% then use timestampOffset = 1.
% That means bioFiles(1) corresponds to timestamp row 2.
timestampOffset = 1;

%% -------- Read BF background-subtracted files --------

bioFiles = dir(fullfile(backSubPath, '*.tif'));

if isempty(bioFiles)
    error('No TIFF images found in: %s', backSubPath);
end

[~, idxB] = sort({bioFiles.name});
bioFiles = bioFiles(idxB);

nImages = numel(bioFiles);

fprintf('Found %d background-subtracted BF images.\n', nImages);

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

% Use only images that have matching timestamps
nImages = numel(datetimeList);
bioFiles = bioFiles(1:nImages);

fprintf('Using %d images with matching timestamps.\n', nImages);

% Experiment time in hours
time_hr = hours(datetimeList - datetimeList(1));

%% -------- Initialize output MAT file --------

sampleImg = imread(fullfile(backSubPath, bioFiles(1).name));

if size(sampleImg,3) > 1
    sampleImg = rgb2gray(sampleImg);
end

[rows, cols] = size(sampleImg);


% Save metadata
m.time_hr = time_hr;
m.datetimeList = datetimeList;
m.imageNumber = imageNumber;
m.bioThreshold = bioThreshold;
m.timestampOffset = timestampOffset;

%% -------- Build biomass age stack --------

% Tracks when biomass most recently started at each pixel
growthStartTime = nan(rows, cols, 'single');

% Tracks whether pixel was occupied in previous image
prevOccupied = false(rows, cols);

fprintf('Building biomass age stack...\n');

for i = 1:nImages

    img = imread(fullfile(backSubPath, bioFiles(i).name));

    if size(img,3) > 1
        img = rgb2gray(img);
    end

    occupied = img > bioThreshold;

    currentTime = single(time_hr(i));

    % Default: free pixels are zero
    ageFrame = zeros(rows, cols, 'single');

    % Newly occupied pixels
    newlyOccupied = occupied & ~prevOccupied;

    % Still occupied pixels
    stillOccupied = occupied & prevOccupied;

    % Sloughed pixels: occupied before, free now
    sloughed = ~occupied & prevOccupied;

    % For newly occupied pixels, reset growth start time
    growthStartTime(newlyOccupied) = currentTime;

    % For still occupied pixels, keep original growth start time
    ageFrame(occupied) = currentTime - growthStartTime(occupied);

    % Mark sloughed pixels as NaN only at the image where sloughing happens
    ageFrame(sloughed) = NaN;

    % After sloughing, reset growth start time
    growthStartTime(sloughed) = NaN;

    % Create filename like biomass_age_001.mat
    fileName = sprintf('biomass_age_%03d.mat', i);
    
    save(fullfile(erosionDistPath, fileName), ...
        'ageFrame', 'currentTime');

    % Update previous occupancy
    prevOccupied = occupied;

    fprintf('Processed image %d/%d\n', i, nImages);
end

fprintf('Saved all biomass age files');
