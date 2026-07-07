clc;

% Biofilm thresholding sensitivity (increase to detect more biofilm)
sensitivity = 0.5; % default is 0.5

% number of thresholding images
nIMG = inf;

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

% Plots path
cd(projectPath);
cd('processed_data\plots\');
plotPath = pwd;

% Thresholded images path
threshFolderName = sprintf('processed_images\\thresholded_images\\sensitivity_%s_main_results', strrep(num2str(sensitivity), '.', '.'));
threshFolderFullPath = fullfile(projectPath, threshFolderName);
if ~exist(threshFolderFullPath, 'dir')
    mkdir(threshFolderFullPath);
    disp(['Created folder: ' threshFolderFullPath]);
end
cd(threshFolderFullPath);
threshMatPath = pwd;



% Get list of .tif images in the current directory
imgFiles = dir(fullfile(tifRawImagesPath, '*ch00*.tif'));
nImgs = length(imgFiles);

    % Read all image filenames
imgNames = {imgFiles.name};


%% -------- Manual Alignment: BF_time0 to Mask --------
alignmentFile = fullfile(logsPath, 'manual_alignment.mat');

if isfile(alignmentFile)
    % --- Load previously saved alignment ---
    load(alignmentFile, 'tform0', 'R_mask', 'R_first', 'GM_Final', 'mask_img');
    disp('Loaded saved alignment from logs folder.');
else
    % --- Run manual alignment for the first time ---
    
    %% -------- Load Images (Mask, Brightfields) --------
    
    % All transform matrices
    tform0 = cell(nImgs, 1);
    
    if nImgs < 2
        error('Need at least two images for pairwise registration.');
    end
    
    % Read grain mask image
    [fileName, filePath] = uigetfile(fullfile(origMaskPath, '*.tif'), 'Select the hip mask file');
    mask_img = imread(fullfile(filePath, fileName));

    % Read first image
    img0 = imread(fullfile(tifRawImagesPath, imgNames{1}));
    if size(img0, 3) > 1,  img0 = rgb2gray(img0);  end
    img0 = im2uint16(img0);   % <-- promote 8-bit to 16-bit before any 16-bit arithmetic

    % Resize grain mask image based on the BF and save it
    cd(funcPath);
    mask_img = resizeMaskToBFWidth(mask_img, img0);
    inverted_img = imcomplement(mask_img);

    % Save resized and inverted mask into the grain_mask path
    imwrite(mask_img, fullfile(grainMaskPath, 'resized_mask.tif'));
    imwrite(inverted_img, fullfile(grainMaskPath, 'inverted_mask.tif'));

    % Binarize mask to have sharp edges of grains
    mask_thresh = imbinarize(mask_img, graythresh(mask_img));

    % Use binarized mask as GM_Final for biofilm masking
    GM_Final = mask_thresh;

    % Manual control point selection and transform estimation
    [mp_mask, mp_first] = cpselect(mask_thresh, img0, 'Wait', true);
    tform0 = estimateGeometricTransform2D(mp_first, mp_mask, 'affine');
    R_mask  = imref2d(size(mask_img));
    R_first = imref2d(size(img0));

    % Align first image
    img0_aligned = imwarp(img0, R_first, tform0, 'OutputView', R_mask);

    % Show before and after registration
    hFig = figure;
    subplot(1,2,1); imshowpair(mask_thresh, img0);       title('Before registration');
    subplot(1,2,2); imshowpair(mask_thresh, img0_aligned); title('After registration');
    uiwait(hFig);

    % Proceed confirmation
    answer = questdlg('Do you want to proceed?', 'Confirmation', 'Yes', 'No', 'Yes');
    switch answer
        case 'Yes'
            disp('Proceeding...');
        case 'No'
            disp('Operation cancelled.');
            return;
    end

    % --- Save alignment to logs folder for future runs ---
    save(alignmentFile, 'tform0', 'R_mask', 'R_first', 'GM_Final', 'mask_img');
    disp('Alignment saved to logs folder.');

end


%% -------- Align Remaining Images + Biofilm Thresholding --------

cd(funcPath);

% Extract all transform matrices from logs folder
tforms = readAffineTransforms(tform0, logsPath);

% T=0 reference image placeholder (captured on first iteration)
REF_IMG_RGB = [];

% *** DRIFT CORRECTION: reference grain intensity (set at T=0) ***
REF_GRAIN_INTENSITY = [];

% Pre-allocate array to log drift factors for inspection
nImgs_loop = min(nImgs, nIMG);
drift_log = nan(nImgs_loop, 1);

hasCh01 = ~isempty(dir(fullfile(tifRawImagesPath, '*ch01*.tif')));
channelsToProcess = 0:(hasCh01); % 0:0 or 0:1

for i = 1:nImgs_loop
    % Extract base filename for this image (e.g., 't00')
    [~, name, ~] = fileparts(imgNames{i});
    baseName = extractBefore(name, 'ch00');

    % Process each channel
    for ch = channelsToProcess
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
            case 1  % FRET: red channel
                if size(img, 3) == 3
                    img = img(:,:,2);
                end
        end
        img = im2uint16(img);   % <-- promote 8-bit to 16-bit, same scaling as img0

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

                % *** DRIFT CORRECTION: record median grain intensity at T=0 ***
                % Grain pixels (GM_Final == 1) are solid and should not change;
                % any change in their brightness across frames is pure illumination drift.
                grain_mask_logical = logical(GM_Final);
                REF_GRAIN_INTENSITY = median(double(aligned_img(grain_mask_logical)), 'all');
                fprintf('T=0 reference grain intensity: %.2f\n', REF_GRAIN_INTENSITY);

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
            clear aligned_img img  % <-- no longer needed after filling

            % *** DRIFT CORRECTION: Step 6.1b — Correct illumination drift  ***
            % Compute the median intensity of grain pixels in the current frame.
            % Grains are structurally stable, so any deviation from REF_GRAIN_INTENSITY
            % is attributed entirely to illumination drift (lamp flicker, ND filter
            % settling, camera gain shifts, etc.).  We scale the whole image by the
            % ratio so that grain pixels recover their T=0 baseline before any
            % biofilm-specific normalisation is applied.
            grain_mask_logical  = logical(GM_Final);
            curr_grain_intensity = median(double(A_filled(grain_mask_logical)), 'all');
            drift_factor         = REF_GRAIN_INTENSITY / curr_grain_intensity;
            drift_log(i)         = drift_factor;

            % Clamp to uint16 range after scaling to avoid overflow
            A_filled = uint16(min(double(A_filled) * drift_factor, 65535));
            fprintf('  Frame %02d | grain intensity: %.2f | drift factor: %.4f\n', ...
                    i-1, curr_grain_intensity, drift_factor);

            % --- Step 6.2: Normalize to T=0 reference ---
            BB = 65535 - REF_IMG_RGB;
            newimg = double(A_filled) + BB;
            newimgGray = uint16(newimg);
            clear A_filled BB  % <-- free intermediate arrays

            % --- Step 6.3: Adaptive thresholding to detect biofilm ---
            Thresh = adaptthresh(newimgGray, sensitivity, 'ForegroundPolarity', 'dark');
            newimg_bin = imbinarize(newimgGray, Thresh);
            newimg_bin = imcomplement(newimg_bin);  % Biofilm = white (1)
            clear Thresh newimgGray_d0  % <-- free after use

            % --- Step 6.4: Erode-dilate to remove noise specks ---
            SE_Bio = strel('square', 4);
            newimg_bin = imerode(newimg_bin, SE_Bio);
            newimg_bin = imdilate(newimg_bin, SE_Bio);

            % --- Step 6.5: Remove grain overlap ---
            newimg_bin = newimg_bin .* imcomplement(GM_Final);

            % --- Step 6.6: Normalize intensity and build output matrix ---
            newimgGray_d0   = double(newimgGray);
            newimgGray_norm = newimgGray_d0 / 65535;
            clear newimgGray newimgGray_d0
            
            % Build output matrix with the correct structure:
            %   grains         → NaN
            %   empty pores    → 0
            %   biomass pixels → normalized intensity [0, 1] (proxy for density)
            
            Final_Matrix = zeros(size(newimgGray_norm));             % Step 1: everything starts as 0 (empty pore)
            
            grain_mask   = logical(GM_Final);
            biofilm_mask = logical(newimg_bin) & ~grain_mask;        % biofilm that does NOT overlap grains
            
            Final_Matrix(grain_mask)    = NaN;                       % Step 2: grains → NaN
            Final_Matrix(biofilm_mask) = 1 - newimgGray_norm(biofilm_mask);  % Step 3: biomass → density [0,1]

            % % Display before and after thresholding
            % figure;
            % subplot(1,2,1); imshow(newimgGray_norm_poreAll); title('Before Thresholding');
            % subplot(1,2,2); imshow(newimgGray_norm_biofilm);  title('After Thresholding');

            % --- Step 6.7: Gap fill, reshape, and save ---
            cd(funcPath);
            Final_Biofilm_Matrix_OF = fill_gaps(Final_Matrix);
            
            frameID = sprintf('%02d', i-1);
            varName = ['thresholded_' frameID];
            eval([varName ' = Final_Biofilm_Matrix_OF;']);
            save(fullfile(threshMatPath, [varName '.mat']), varName);
            fprintf('Biofilm matrix saved: %s\n', varName);

            % Free everything before next iteration
            clear Final_Matrix newimgGray_norm ...
                  newimg_bin nonZeroMask nearestLinearIdx ...
                  nearestIdxRow nearestIdxCol zeroMask newimg ...
                  grain_mask biofilm_mask
            eval(['clear ' varName]);  % clear the dynamically named variable too
        else
            clear aligned_img img  % free FRET channel too
        end % end ch == 0 biofilm block
    end % end channel loop
end % end image loop

% *** DRIFT CORRECTION: save drift log for quality control ***
save(fullfile(logsPath, 'drift_correction_log.mat'), 'drift_log');
fprintf('\nDrift factors saved to logs folder.\n');

% Plot drift factors so you can spot problematic frames
figure;
plot(1:nImgs_loop, drift_log, 'o-', 'LineWidth', 1.5);
xlabel('Image #'); ylabel('Drift correction factor');
title('Illumination drift correction factors');
yline(1, '--k', 'No drift'); grid on;

saveas(gcf, fullfile(plotPath, 'Illumination_drift_correction_factors.png'));

disp('All images registered, biofilm thresholded, and matrices saved.');
