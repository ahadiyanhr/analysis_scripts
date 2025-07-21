%% ---- Parameters ----
radius = 10;       % for bright outlier removal
threshold = 40;    % for outlier intensity threshold

clc;

%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Functions path
cd('functions\');
funcPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Processed images path
cd(projectPath);
cd('processed_images\');
processedImagesPath = pwd;

% Registered images path
cd(projectPath);
cd('processed_images\registered_images\');
registeredPath = pwd;

% Output folders
backgroundPath = fullfile(processedImagesPath, 'background_subtracted');
ratioImagesPath = fullfile(processedImagesPath, 'do_ratio');

if ~exist(backgroundPath, 'dir'); mkdir(backgroundPath); end
if ~exist(ratioImagesPath, 'dir'); mkdir(ratioImagesPath); end

%% ---- Load Brightfield Images (ch00) ----
bfFiles = dir(fullfile(registeredPath, '*ch00*.tif'));
if isempty(bfFiles)
    error('No ch00 images found in the registered folder.');
end

% Sort files naturally (e.g., t00, t01, ..., t15)
[~, idx] = sort({bfFiles.name});
bfFiles = bfFiles(idx);

nImgs = numel(bfFiles);
fprintf('Found %d Brightfield (ch00) images.\n', nImgs);

% Use the last image as background reference
backgroundImg = imread(fullfile(registeredPath, bfFiles(1).name));
if size(backgroundImg, 3) > 1
    backgroundImg = rgb2gray(backgroundImg);
end
backgroundImg = double(backgroundImg);

%% ---- Process Brightfield Images ----
for i = 2:2 %2:nImgs
    fname = bfFiles(i).name;
    img = imread(fullfile(registeredPath, fname));
    if size(img, 3) > 1
        img = rgb2gray(img);
    end
    img = double(img);

    % Background subtraction
    subtracted = uint16(max(backgroundImg - img, 0));

    % Remove bright outliers
    cleaned = removeBrightOutliers(subtracted, radius, threshold);

    % Save cleaned image
    imwrite(cleaned, fullfile(backgroundPath, fname));
    fprintf('Processed and saved BF: %s\n', fname);
end

disp('✅ All Brightfield images processed and saved.');

%% ---- Calculate Ratio of FRET to GFP ----
gfpFiles = dir(fullfile(registeredPath, '*ch01*.tif'));  % GFP channel
fretFiles = dir(fullfile(registeredPath, '*ch02*.tif')); % FRET channel

if numel(gfpFiles) ~= numel(fretFiles)
    error('Mismatch in number of GFP and FRET images.');
end

[~, idx] = sort({gfpFiles.name});
gfpFiles = gfpFiles(idx);
[~, idx] = sort({fretFiles.name});
fretFiles = fretFiles(idx);

fprintf('\n📈 Computing FRET/GFP ratio for %d image pairs...\n', numel(gfpFiles));

for i = 1:2 %numel(gfpFiles)
    gfpImg = imread(fullfile(registeredPath, gfpFiles(i).name));
    fretImg = imread(fullfile(registeredPath, fretFiles(i).name));

    % Convert to double
    gfpImg = double(gfpImg);
    fretImg = double(fretImg);

    % Avoid divide-by-zero
    gfpImg(gfpImg == 0) = NaN;

    % Ratio calculation
    ratioImg = fretImg ./ gfpImg;

    % Get timepoint label from filename
    [~, baseName, ~] = fileparts(gfpFiles(i).name);
    timeLabel = extractBefore(baseName, '_ch01');
    outName = fullfile(ratioImagesPath, sprintf('ratio_%s.mat', timeLabel));

    % Save ratio image as .mat (optionally .tif for visualization)
    save(outName, 'ratioImg', '-v7.3');
    fprintf('✅ Saved ratio image: %s\n', outName);
end

fprintf('\nDone! All ratio images saved to: %s\n', ratioImagesPath);


%% ==== FUNCTION: Remove Bright Outliers ====
function outImg = removeBrightOutliers(img, radius, threshold)
    img = double(img);

    % Create circular mask
    [X, Y] = meshgrid(-radius:radius, -radius:radius);
    mask = (X.^2 + Y.^2 <= radius^2);
    mask(radius+1, radius+1) = false;

    % Local median filter (fast approximation)
    localMedian = medfilt2(img, [2*radius+1, 2*radius+1], 'symmetric');

    % Detect outliers
    outlierMask = (img - localMedian) > threshold;

    % Replace outliers
    img(outlierMask) = localMedian(outlierMask);

    outImg = uint16(img);
end
