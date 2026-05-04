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
cd('raw_data\images\bf_red_channel\');
tifRawImagesPath = pwd;

% Logs path
cd(projectPath);
cd('logs\');
logsPath = pwd;

% Biofilm matrices output path
cd(projectPath);
cd('processed_images\biofilm_matrices\');
biofilmMatPath = pwd;


%% -------- Load Images (Mask, Brightfields) --------

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
[fileName, filePath] = uigetfile(fullfile(origMaskPath, '*.tif'), 'Select the hip mask file');
mask_img = imread(fullfile(filePath, fileName));


%% -------- Manual Alignment: BF_time0 to Mask --------

% Read first image
img0 = imread(fullfile(tifRawImagesPath, imgNames{1}));

% Convert to grayscale
if size(img0, 3) > 1,  img0  = rgb2gray(img0);  end

% Resize grain mask image based on the BF and save it
cd(funcPath);
mask_img = resizeMaskToBFWidth(mask_img, img0);
inverted_img = imcomplement(mask_img);

% Save resized and inverted mask into the grain_mask path
imwrite(mask_img, fullfile(grainMaskPath, 'resized_mask.tif'));
imwrite(inverted_img, fullfile(grainMaskPath, 'inverted_mask.tif'));

% Binarize mask to have sharp edges of grains
mask_thresh = imbinarize(mask_img, graythresh(mask_img));

% --- Step 2 addition: use binarized mask as GM_Final for biofilm masking ---
GM_Final = mask_thresh;

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
    case 'No'
        disp('Operation cancelled.');
        return;
end


%% -------- Align Remaining Images + Biofilm Thresholding --------

% Extract all transform matrices from logs folder
tforms = readAffineTransforms(tform0, logsPath);

% Biofilm thresholding sensitivity (increase to detect more biofilm)
sensitivity = 0.5;

% T=0 reference image placeholder (captured on first iteration)
REF_IMG_RGB = [];

for i = 1:nImgs
    % Extract base filename for this image (e.g., 't00')
    [~, name, ~] = fileparts(imgNames{i});
    baseName = extractBefore(name, 'ch00');

    % Process each channel
    for ch = 0:1
        % Construct filename for current channel
        chName = sprintf('ch%02d', ch);
        filename = fullfile(tifRawImagesPath, [baseName, chName, '.tif']);

        if ~isfile(filename)
            warning('File not found: %s', filename);
            continue;
        end

        % Read image
        img = imread(filename);

        % Channel-specific conversion
        switch ch
            case 0  % Brightfield: grayscale
                if size(img, 3) > 1, img = rgb2gray(img); end
            case 1  % FRET: green channel
                if size(img, 3) == 3
                    img = img(:,:,2);
                end
        end

        % Reference and transform
        R_img = imref2d(size(img));
        aligned_img = imwarp(img, R_img, tforms{i}, 'OutputView', R_mask);

        % Save registered image with consistent naming
        outName = sprintf('t%02d_ch%02d.tif', i-1, ch);
        imwrite(aligned_img, fullfile(registeredImagesPath, outName));
        fprintf('Registered and saved: %s\n', outName);

        % --- Biofilm processing for brightfield channel (ch00) only ---
        if ch == 0

            % Capture T=0 image as reference and skip biofilm processing
            if i == 1
                REF_IMG_RGB = double(aligned_img);
                disp('T=0 reference image captured.');
                continue;
            end

            % --- Step 6.1: Fill zero-value border pixels created by warping ---
            nonZeroMask = aligned_img ~= 0;
            [~, nearestLinearIdx] = bwdist(nonZeroMask, 'cityblock');
            [nearestIdxRow, nearestIdxCol] = ind2sub(size(aligned_img), nearestLinearIdx);
            A_filled = aligned_img;
            zeroMask = aligned_img == 0;
            A_filled(zeroMask) = aligned_img(sub2ind(size(aligned_img), ...
                nearestIdxRow(zeroMask), nearestIdxCol(zeroMask)));

            % --- Step 6.2: Normalize to T=0 reference ---
            BB = 65535 - REF_IMG_RGB;
            newimg = double(A_filled) + BB;
            newimgGray = uint16(newimg);

            % --- Step 6.3: Adaptive thresholding to detect biofilm ---
            Thresh = adaptthresh(newimgGray, sensitivity, 'ForegroundPolarity', 'dark');
            newimg_bin = imbinarize(newimgGray, Thresh);
            newimg_bin = imcomplement(newimg_bin);  % Biofilm = white (1)

            % --- Step 6.4: Erode-dilate to remove noise specks ---
            SE_Bio = strel('square', 4);
            newimg_bin = imerode(newimg_bin, SE_Bio);
            newimg_bin = imdilate(newimg_bin, SE_Bio);

            % --- Step 6.5: Remove grain overlap ---
            newimg_bin = newimg_bin .* imcomplement(GM_Final);

            % --- Step 6.6: Normalize intensity and build output matrices ---
            newimgGray_d0  = double(newimgGray);
            newimgGray_norm = newimgGray_d0 / 65535;

            % All pore pixels (grains set to NaN)
            newimgGray_norm_poreAll = newimgGray_norm;
            newimgGray_norm_poreAll(GM_Final == 1) = NaN;

            % Only confirmed biofilm pixels (non-biofilm set to NaN)
            newimgGray_norm_biofilm = newimgGray_norm;
            newimgGray_norm_biofilm(newimg_bin == 0) = NaN;

            % Display before and after thresholding
            figure;
            subplot(1,2,1); imshow(newimgGray_norm_poreAll); title('Before Thresholding');
            subplot(1,2,2); imshow(newimgGray_norm_biofilm);  title('After Thresholding');

            % --- Step 6.7: Gap fill, reshape, and save ---
            cd(funcPath);
            Density_original_reshaped = fliplr(newimgGray_norm_biofilm');
            Final_Biofilm_Matrix_OF   = fill_gaps(Density_original_reshaped);

            frameID = sprintf('%02d', i-1);
            varName = ['BIOFILM_' frameID];
            eval([varName ' = Final_Biofilm_Matrix_OF;']);
            save(fullfile(biofilmMatPath, [varName '.mat']), varName);
            fprintf('Biofilm matrix saved: %s\n', varName);

        end % end ch == 0 biofilm block
    end % end channel loop
end % end image loop

disp('All images registered, biofilm thresholded, and matrices saved.');
