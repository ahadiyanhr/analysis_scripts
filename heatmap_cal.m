%% === SETTINGS ===
blk     = 10;       % block size (20x20)

clc;

%% -------- Setup --------

mainPath    = pwd;

cd(mainPath); cd('../');
projectPath = pwd;

cd(projectPath); cd('logs\');
logPath     = pwd;

cd(projectPath); cd('processed_data\do_ratio\');
doRatioPath = pwd;

cd(projectPath); cd('processed_images\heatmap_images\');
heatmapPath = pwd;

cd(projectPath); cd('processed_data\do_mapped\');
doMappedPath = pwd;

cd(projectPath); cd('processed_images\grain_mask\');
grainMaskPath = pwd;

%% -------- LOAD MASK FILE --------
maskImg = imread(fullfile(grainMaskPath, 'inverted_mask.tif'));

if ndims(maskImg) == 3
    maskImg = rgb2gray(maskImg);
end

[H, W]   = size(maskImg);
Hc       = floor(H/blk)*blk;
Wc       = floor(W/blk)*blk;
hBlocks  = Hc / blk;
wBlocks  = Wc / blk;

blackMask_full = (maskImg == 0);
blackMask_crop = blackMask_full(1:Hc, 1:Wc);

Mresh    = reshape(blackMask_crop, blk, hBlocks, blk, wBlocks);
blackMask = squeeze(any(any(Mresh, 1), 3));
blackMask = logical(blackMask);

%% --- Mapping Curve ---
calibFile    = dir(fullfile(logPath, 'calibration_summary*.csv'));
T            = readtable(fullfile(logPath, calibFile.name));
alpha_shared = T.alpha_shared(1);
Ksv_shared   = T.Ksv_shared(1);
alpha_all    = T.alpha_ind;
Ksv_all      = T.Ksv_ind;
Rhigh_all    = T.Rhigh_joint;
Chigh_all    = T.C_high;

first_do_file = dir(fullfile(doRatioPath, 'ratio_t*.mat'));
names         = {first_do_file.name};
timeNums      = nan(size(names));

for k = 1:numel(names)
    tok = regexp(names{k}, '^ratio_t(\d+)\.mat$', 'tokens', 'once');
    if ~isempty(tok)
        timeNums(k) = str2double(tok{1});
    end
end
[~, idx]      = sort(timeNums);
first_do_file = first_do_file(idx(1));

first_do_ratio = load(fullfile(doRatioPath, first_do_file.name));
ratio_average  = nanmean(first_do_ratio.do_ratio(:));

nOpt      = numel(alpha_all);
C_est_all = nan(nOpt, 1);

for i = 1:nOpt
    alpha_i  = alpha_all(i);
    Ksv_i    = Ksv_all(i);
    Rhigh_i  = Rhigh_all(i);
    Chigh_i  = Chigh_all(i);
    A_high_i = alpha_i + (1 - alpha_i) / (1 + Ksv_i * Chigh_i);
    B_i      = (ratio_average / Rhigh_i) * A_high_i;
    if (B_i - alpha_i) <= 0 || ~isfinite(B_i)
        warning('Optode %d gives invalid inversion. Returning NaN.', i);
        C_est_all(i) = NaN;
    else
        C_est_all(i) = ((1 - alpha_i) / (B_i - alpha_i) - 1) / Ksv_i;
    end
end

Chigh  = mean(C_est_all, 'omitnan');
A_high = alpha_shared + (1 - alpha_shared) ./ (1 + Ksv_shared .* Chigh);

% Sort all ratio files by time index
ratio_files = dir(fullfile(doRatioPath, '*.mat'));
names       = {ratio_files.name};
timeNums    = nan(size(names));

for k = 1:numel(names)
    tok = regexp(names{k}, '^ratio_t(\d+)\.mat$', 'tokens', 'once');
    if ~isempty(tok)
        timeNums(k) = str2double(tok{1});
    else
        error('Filename does not match expected pattern: %s', names{k});
    end
end
[~, idx]    = sort(timeNums);
ratio_files = ratio_files(idx);

Icrop = first_do_ratio.do_ratio(1:Hc, 1:Wc);
Iresh = reshape(double(Icrop), blk, hBlocks, blk, wBlocks);
Iavg  = squeeze(mean(mean(Iresh, 1), 3));

% --- Colormap and grain color ---
cmap     = burgundySandTeal(256);
cmin     = 0;
cmax     = 7;

% Dark warm-gray grain: distinct from sand midpoint, neutral against
% both burgundy and teal ends. RGB ~0.35 sits well below the sand
% (~0.85) while avoiding pure black harshness.
grainRGB = [0.36, 0.34, 0.32];   % #5C5652 — dark charcoal-brown

%% -------- MAIN LOOP --------
for i = 1:numel(ratio_files)

    %% MAPPING
    ratioFile = load(fullfile(doRatioPath, ratio_files(i).name));
    Rcrop     = ratioFile.do_ratio(1:Hc, 1:Wc);
    Rresh     = reshape(double(Rcrop), blk, hBlocks, blk, wBlocks);
    Ravg      = squeeze(mean(mean(Rresh, 1), 3));

    B      = (Ravg ./ ratio_average) .* A_high;
    mapped = ((1 - alpha_shared) ./ (B - alpha_shared) - 1) ./ Ksv_shared;

    %% CLEAN
    mapped(~isfinite(mapped)) = NaN;
    mapped(mapped < 0)        = 0;

    %% CONVERT TO RGB — no figure window opened
    mapped_norm = (mapped - cmin) ./ (cmax - cmin);
    mapped_norm = min(max(mapped_norm, 0), 1);

    % NaN pixels -> grain color (will be overwritten by mask anyway)
    mapped_norm(isnan(mapped_norm)) = 0;

    idx_cm = round(mapped_norm * (size(cmap, 1) - 1)) + 1;
    rgbImg = ind2rgb(idx_cm, cmap);

    %% APPLY GRAIN MASK (dark charcoal-brown)
    for c = 1:3
        ch             = rgbImg(:,:,c);
        ch(blackMask)  = grainRGB(c);
        rgbImg(:,:,c)  = ch;
    end

    %% SAVE
    [~, baseName, ~] = fileparts(ratio_files(i).name);
    tok = regexp(baseName, '^ratio_t(\d+)$', 'tokens', 'once');
    if isempty(tok)
        error('Filename does not match expected pattern: %s', baseName);
    end

    tNum      = str2double(tok{1});
    timeLabel = sprintf('t%03d', tNum);

    save(fullfile(doMappedPath, sprintf('do_mapped_%s.mat', timeLabel)), ...
         'mapped', '-v7.3');

    imwrite(rgbImg, fullfile(heatmapPath, sprintf('heatmap_%s.tif', timeLabel)));

    fprintf('Saved: heatmap_%s.tif\n', timeLabel);

end

fprintf('\nDone. All heatmaps saved to %s\n', heatmapPath);


%% === COLORMAP FUNCTION ===
function cmap = burgundySandTeal(n)
% burgundySandTeal  cmocean-inspired diverging colormap for DO (0–7 mg/L).
%
%   Burgundy (0 mg/L) -> Sand (2 mg/L) -> Dark teal (7 mg/L)
%
%   Divergence point at 2/7 ≈ 0.286 (normalized), matching the
%   oxic/anoxic threshold. Perceptually smooth; good grayscale reproduction.
%
%   Cite: Thyng et al. (2016) Oceanography 29(3).
%         Crameri et al. (2020) Nat. Commun. doi:10.1038/s41467-020-19160-7

    if nargin < 1 || isempty(n), n = 256; end

    T = 2/7;   % normalised threshold position

    % Five anchors for a smooth perceptual arc through each half
    anchorNorm = [0,      T*0.5,  T,      T+(1-T)*0.5,  1    ];
    anchorRGB  = [...
        0.52, 0.04, 0.12;   % 0 mg/L        — deep burgundy   #850A1F
        0.78, 0.42, 0.35;   % 1 mg/L (mid)  — muted rose      #C76B59
        0.86, 0.80, 0.64;   % 2 mg/L        — warm sand       #DBCC A3
        0.26, 0.58, 0.56;   % ~4.5 mg/L     — mid teal        #429490
        0.03, 0.36, 0.40];  % 7 mg/L        — dark teal       #085C66

    xq   = linspace(0, 1, n)';
    cmap = zeros(n, 3);
    for c = 1:3
        cmap(:,c) = interp1(anchorNorm, anchorRGB(:,c), xq, 'linear', 'extrap');
    end
    cmap = min(max(cmap, 0), 1);
end
