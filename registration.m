clc;

%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Functions path
cd('functions\');
funcPath = pwd;

% Original grain mask path
cd(mainPath);
cd('grain_mask\');
origMaskPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Registered images path
cd('processed_images\registered_images\');
registeredImagesPath = pwd;

% Grain mask path
cd(projectPath);
cd('processed_images\grain_mask\');
grainMaskPath = pwd;

% TIF raw images path
cd(projectPath);
cd('raw_data\images\tif_images\');
tifRawImagesPath = pwd;

% Logs path
cd(projectPath);
cd('logs\');
logsPath = pwd;


%% -------- Load Images (Mask, Brightfields --------

% Get list of .tif images in the current directory
imgFiles = dir(fullfile(tifRawImagesPath, '*ch00*.tif'));
nImgs = length(imgFiles);

% All transform matrices 
tform0 = cell(nImgs, 1);

if nImgs < 2
    error('Need at least two images for pairwise registration.');
end

% Read all image filenames
imgNames = {imgFiles.name};

% Read grain mask image
mask_img = imread(fullfile(origMaskPath, "mask (hip).tif"));


%% -------- Manual Alignment: BF_time0 to Mask --------

% Read first image
img0 = imread(fullfile(tifRawImagesPath, imgNames{1}));

% Convert to grayscale
if size(img0, 3) > 1,  img0  = rgb2gray(img0);  end

% Resize grain mask image based on the BF and save it
cd(funcPath);
mask_img = resizeMaskToBFWidth(mask_img, img0);

% Save resized and inverted mask into the grain_mask path
imwrite(mask_img, fullfile(grainMaskPath, 'resized_mask.tif'));
imwrite(mask_img, fullfile(grainMaskPath, 'inverted_mask.tif'));

% Binarize mask to have sharp edges of grains
mask_thresh = imbinarize(mask_img, graythresh(mask_img));

[mp_mask, mp_first] = cpselect(mask_thresh, img0, 'Wait', true);
tform0 = estimateGeometricTransform2D(mp_first, mp_mask, 'affine');
R_mask = imref2d(size(mask_img));
R_first  = imref2d(size(img0));

% Align first image
img0_aligned = imwarp(img0, R_first, tform0, 'OutputView', R_mask);

% Show before and after registration
hFig = figure;
subplot(1,2,1); imshowpair(mask_thresh, img0);    title('Before registration');
subplot(1,2,2); imshowpair(mask_thresh, img0_aligned); title('After registration');

% Wait until the figure is closed
uiwait(hFig);

% Proceed confirmation
answer = questdlg('Do you want to proceed?', ...
                  'Confirmation', ...
                  'Yes', 'No', 'Yes');
switch answer
    case 'Yes'
        disp('Proceeding...');
        % Place the code to run if "Yes"
    case 'No'
        disp('Operation cancelled.');
        return;  % Stops execution
end

%% -------- Align Remaining Images --------

% Save img0 into registered folder
% imwrite(img0_aligned, fullfile(registeredImagesPath, 't00_bf.tif'));

% Extract all transfrom matrices from logs folder
tforms = readAffineTransforms(tform0, logsPath);

for i = 1:nImgs
    % Extract base filename for this image (e.g., 't00')
    [~, name, ~] = fileparts(imgNames{i});
    baseName = extractBefore(name, 'ch00');  % This gets 't00_' or similar
    
    % Process each channel
    for ch = 0:2
        % Construct filename for current channel
        chName = sprintf('ch%02d', ch);
        filename = fullfile(tifRawImagesPath, [baseName, chName, '.tif']);
        
        if ~isfile(filename)
            warning('File not found: %s', filename);
            continue;
        end

        % Read and convert to grayscale if needed
        img = imread(filename);
        
        % Channel-specific conversion
        switch ch
            case 0  % Brightfield: grayscale
                if size(img, 3) > 1, img = rgb2gray(img); end
            case 1  % GFP: green channel
                if size(img, 3) == 3
                    img = img(:,:,2);  % Green channel
                end
            case 2  % FRET: red channel
                if size(img, 3) == 3
                    img = img(:,:,1);  % Red channel
                end
        end
        
        % Reference and transform
        R_img = imref2d(size(img));
        aligned_img = imwarp(img, R_img, tforms{i}, 'OutputView', R_mask);

        % Save image with consistent naming
        outName = sprintf('t%02d_ch%02d.tif', i-1, ch);
        imwrite(aligned_img, fullfile(registeredImagesPath, outName));

        fprintf('Registered and saved: %s\n', outName);
    end
end

disp('All images registered and saved.');
