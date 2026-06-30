%% batch_intensity_correction_grainmask.m
%
% STEP 1 (fit): Using one registered "bright" image + its matching
%               reference image + grain mask (all same FOV/alignment),
%               fit a linear transform I_ref = a*I_bright + b using
%               ONLY grain-mask pixels.
%
% STEP 2 (apply): Apply that SAME (a, b) to every raw .tif image in a
%               separate folder you specify (e.g. images that were never
%               registered to the mask grid, but were acquired under the
%               same bright-light condition as the fitting image). The
%               mask is fixed reactor/chip geometry, so it's only used
%               once for fitting -- it is NOT reapplied to the raw images.
%
% Outputs corrected versions of every raw image into an output folder.

clear; clc; close all;

%% ---- 1. User inputs: fitting set (registered) ----
bright_fit_path = 't02_ch00.tif';   % ONE registered bright image
ref_fit_path     = 'ref_ch00.tif';     % its matching reference image
mask_path        = 'mask.tif';    % grain mask, aligned to the above two

%% ---- 2. User inputs: batch to correct (NOT registered) ----
raw_input_folder  = 'unregistered';        % <-- folder you specify, unregistered raw .tif image
output_folder     = 'corrected_images_folder';  % <-- where corrected images will be saved
file_ext          = '*.tif';                    % change to '*.tiff' if needed

if ~exist(output_folder, 'dir')
    mkdir(output_folder);
end

%% ---- 3. Load fitting images and mask ----
I_bright_fit = double(imreadGray(bright_fit_path));
I_ref_fit    = double(imreadGray(ref_fit_path));
M_raw        = imreadGray(mask_path);

grainMask = M_raw ~= 0;   % nonzero = grain. Flip to ~grainMask if your convention is opposite.

assert(isequal(size(I_bright_fit), size(I_ref_fit), size(grainMask)), ...
    'Fitting bright image, reference image, and mask must all be the same size/registered.');

%% ---- 4. Fit linear model on grain-mask pixels ----
x = I_bright_fit(grainMask);
y = I_ref_fit(grainMask);

A = [x, ones(size(x))];
coeffs = A \ y;     % least squares
a = coeffs(1);
b = coeffs(2);

y_fit = a*x + b;
resid = y - y_fit;
rmse_grain = sqrt(mean(resid.^2));
r2 = 1 - sum(resid.^2)/sum((y - mean(y)).^2);

fprintf('Fitted model: I_ref = %.4f * I_bright + %.4f\n', a, b);
fprintf('Grain-pixel fit quality: RMSE = %.3f, R^2 = %.4f\n', rmse_grain, r2);

% Quick diagnostic plot for the fit
figure('Name','Linear fit on grain-mask pixels');
scatter(x, y, 4, 'filled', 'MarkerFaceAlpha', 0.15); hold on;
xv = linspace(min(x), max(x), 100);
plot(xv, a*xv + b, 'r-', 'LineWidth', 2);
xlabel('Bright image intensity (grain)'); ylabel('Reference intensity (grain)');
title(sprintf('a=%.3f, b=%.3f, R^2=%.4f', a, b, r2));
legend('Grain pixels','Linear fit','Location','best'); grid on;

%% ---- 5. Apply fitted transform to every raw image in the batch folder ----
fileList = dir(fullfile(raw_input_folder, file_ext));
fprintf('\nFound %d images in %s\n', numel(fileList), raw_input_folder);

for k = 1:numel(fileList)
    inPath  = fullfile(raw_input_folder, fileList(k).name);
    outPath = fullfile(output_folder, fileList(k).name);

    I_raw = double(imreadGray(inPath));

    I_corr = a * I_raw + b;
    I_corr_uint8 = uint8(min(max(I_corr, 0), 255));

    imwrite(I_corr_uint8, outPath);
    fprintf('Corrected: %s -> %s\n', fileList(k).name, outPath);
end

fprintf('\nDone. %d corrected images saved to: %s\n', numel(fileList), output_folder);

%% ---- Helper function ----
function img = imreadGray(path)
    img = imread(path);
    if ndims(img) == 3
        img = img(:,:,1);
    end
end