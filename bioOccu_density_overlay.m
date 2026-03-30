clc; clear;

%% ===================== USER SETTINGS =====================
filePattern  = "*.tif";     % input image type
scaleFactor  = 0.2;        % resize factor, e.g. 1 = original size, 0.5 = half size
gamma        = 5.0;         % nonlinear stretch
darkGreen    = [0, 0.30, 0];
white        = [1, 1, 1];
grayLevel    = 0.6;         % overlay gray for masked pixels

%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Background subtracted folder path
cd('processed_images\background_subtracted\');
backSubPath = pwd;

% Density overlay folder path
cd(projectPath);
cd('processed_images\biomass_density_overlay\');
overlayPath = pwd;

% Grain mask path
cd(projectPath);
cd('processed_images\grain_mask\');
grainMaskPath = pwd;




%% ===================== READ AND PREPARE MASK =====================

maskImg = imread(fullfile(grainMaskPath, 'resized_mask.tif'));

if ~isa(maskImg, 'uint16')
    error("Mask image must be uint16 (16-bit).");
end

% Resize mask if needed
if scaleFactor ~= 1
    % Use nearest for mask so binary values stay binary
    maskImg = imresize(maskImg, scaleFactor, 'nearest');
end

% Define white pixels in the mask
maskWhite = (maskImg == 65535);

%% ===================== GET IMAGE LIST =====================

files = dir(fullfile(backSubPath, filePattern));

if isempty(files)
    error("No input images found in the input folder.");
end

%% ===================== PROCESS ALL IMAGES =====================

for k = 1:numel(files)

    % Full input path
    inFile = fullfile(files(k).folder, files(k).name);

    % Read image
    I = imread(inFile);

    % Check type
    if ~isa(I, 'uint16')
        warning("Skipping %s because it is not uint16.", files(k).name);
        continue;
    end

    % Resize image if needed
    if scaleFactor ~= 1
        I = imresize(I, scaleFactor, 'bilinear');
    end

    % Check size match with mask
    if ~isequal(size(I), size(maskImg))
        warning("Skipping %s because image and mask size do not match after resizing.", files(k).name);
        continue;
    end

    %% Step 1: Invert 16-bit grayscale image
    Iinv = uint16(65535) - I;

    %% Step 2: Darker green mapping with nonlinear stretch
    In  = double(Iinv) / 65535;
    In2 = In .^ gamma;

    R = darkGreen(1) + (white(1) - darkGreen(1)) .* In2;
    G = darkGreen(2) + (white(2) - darkGreen(2)) .* In2;
    B = darkGreen(3) + (white(3) - darkGreen(3)) .* In2;

    RGB = cat(3, R, G, B);

    %% Step 3: Apply gray overlay where mask is white
    RGB_masked = RGB;

    for c = 1:3
        channel = RGB_masked(:,:,c);
        channel(maskWhite) = grayLevel;
        RGB_masked(:,:,c) = channel;
    end

    %% Save output
    [~, baseName, ~] = fileparts(files(k).name);
    outFile = fullfile(overlayPath, baseName + "_overlay.png");

    imwrite(RGB_masked, outFile);

    fprintf("Processed and saved: %s\n", baseName + "_overlay.png");
end

disp("Done.");