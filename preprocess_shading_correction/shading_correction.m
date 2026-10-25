%% Flat-Field (Shading) Correction for Brightfield Microscopy Tiles
%
%  Corrects vignetting / uneven illumination in image tiles using a
%  reference image taken from a blank (empty) area of the reactor.
%
%  Correction formula:
%      corrected(x,y) = raw(x,y) ./ flat_norm(x,y)
%
%  where flat_norm is the flat-field smoothed and normalized so its
%  mean equals 1 — this preserves the original intensity scale.
%
%  If you also have a dark frame (camera with shutter closed):
%      corrected = (raw - dark) ./ (flat - dark)
%      → set DARK_IMAGE_PATH below.
%
%  Requirements: Image Processing Toolbox (for imgaussfilt, imwrite)

clc; clear; close all;

%% ── USER SETTINGS ──────────────────────────────────────────────────────

TILES_DIR       = '';            % folder containing raw tile images
FLAT_IMAGE_PATH = 'ref_image.tif';% your blank-area reference image
DARK_IMAGE_PATH = '';                  % dark frame path — leave '' if none
OUTPUT_DIR      = 'tiles_corrected/'; % output folder (created if missing)
TILE_EXT        = '*.tif';            % tile file pattern (*.tif, *.png …)

% Gaussian blur sigma applied to the flat-field before normalization.
% Smoothing removes noise/features from the reference so only the slow
% illumination gradient survives.  Tune to ~1/5 of your tile width.
% Set to 0 to skip smoothing.
FLAT_SMOOTH_SIGMA = 50;               % pixels

%% ── SETUP ───────────────────────────────────────────────────────────────

if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

% Collect tile paths
tile_list = dir(fullfile(TILES_DIR, TILE_EXT));
if isempty(tile_list)
    error('No tiles found in "%s" matching "%s". Check TILES_DIR and TILE_EXT.', ...
          TILES_DIR, TILE_EXT);
end
fprintf('Found %d tiles to correct.\n\n', numel(tile_list));

%% ── LOAD & PREPARE FLAT-FIELD ───────────────────────────────────────────

fprintf('Loading flat-field reference: %s\n', FLAT_IMAGE_PATH);
flat_raw = load_as_double(FLAT_IMAGE_PATH);

% Convert to grayscale if the reference is RGB
if size(flat_raw, 3) == 3
    flat_raw = mean(flat_raw, 3);
end

% Subtract dark frame if provided
if ~isempty(DARK_IMAGE_PATH)
    dark = load_as_double(DARK_IMAGE_PATH);
    if size(dark, 3) == 3
        dark = mean(dark, 3);
    end
    flat_raw = flat_raw - dark;
    flat_raw = max(flat_raw, 1e-6);   % avoid zeros
end

% Smooth to capture only the illumination trend
if FLAT_SMOOTH_SIGMA > 0
    flat_smooth = imgaussfilt(flat_raw, FLAT_SMOOTH_SIGMA);
else
    flat_smooth = flat_raw;
end

% Normalize so mean == 1  →  tiles keep their original brightness
flat_norm = flat_smooth ./ mean(flat_smooth(:));

% Guard against near-zero values (dead pixels in the reference)
flat_norm(flat_norm < 1e-3) = 1e-3;

fprintf('  Flat-field range : %.3f – %.3f  (mean = 1.00)\n\n', ...
        min(flat_norm(:)), max(flat_norm(:)));

%% ── CORRECT EACH TILE ───────────────────────────────────────────────────

% Read one tile to detect bit depth for saving
info      = imfinfo(fullfile(tile_list(1).folder, tile_list(1).name));
bit_depth = info.BitDepth;            % 8 or 16 (typical for microscopy)

for i = 1 : numel(tile_list)-1

    tile_path = fullfile(tile_list(i).folder, tile_list(i).name);
    out_path  = fullfile(OUTPUT_DIR, tile_list(i).name);

    % ── Load tile ──
    raw = load_as_double(tile_path);
    is_color = size(raw, 3) == 3;

    % ── Subtract dark frame if provided ──
    if ~isempty(DARK_IMAGE_PATH)
        if is_color
            dark_tile = repmat(dark, [1 1 3]);
        else
            dark_tile = dark;
        end
        raw = max(raw - dark_tile, 0);
    end

    % ── Apply flat-field correction ──
    if is_color
        corrected = raw ./ repmat(flat_norm, [1 1 3]);
    else
        corrected = raw ./ flat_norm;
    end

    % ── Clip to [0, 1] and save at original bit depth ──
    corrected = min(max(corrected, 0), 1);
    save_image(corrected, out_path, bit_depth);

    fprintf('  [%3d/%d]  %s  →  %s\n', i, numel(tile_list), ...
            tile_list(i).name, out_path);
end

fprintf('\nDone ✓  Corrected tiles saved to "%s"\n', OUTPUT_DIR);

%% ── LOCAL FUNCTIONS ─────────────────────────────────────────────────────

function img = load_as_double(path)
% Load any supported image and return it as double in [0, 1].
    raw = imread(path);
    switch class(raw)
        case 'uint8'
            img = double(raw) / 255;
        case 'uint16'
            img = double(raw) / 65535;
        case 'double'
            img = raw;
        case 'single'
            img = double(raw);
        otherwise
            img = im2double(raw);   % fallback via Image Processing Toolbox
    end
end

function save_image(img_double, path, bit_depth)
% Save a double [0,1] image at the specified bit depth.
    switch bit_depth
        case 8
            imwrite(uint8(img_double * 255), path);
        case 16
            imwrite(uint16(img_double * 65535), path);
        otherwise
            imwrite(uint16(img_double * 65535), path);
    end
end