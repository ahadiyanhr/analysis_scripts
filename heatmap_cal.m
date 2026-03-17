%% === SETTINGS ===
blk     = 20;       % block size (20x20)

clc;

%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Log path
cd(projectPath);
cd('logs\');
logPath = pwd;

% DO ratio path
cd(projectPath);
cd('processed_data\do_ratio\');
doRatioPath = pwd;

% Heatmap path
cd(projectPath);
cd('processed_images\heatmap_images\');
heatmapPath = pwd;

% DO mapped path
cd(projectPath);
cd('processed_data\do_mapped\');
doMappedPath = pwd;

% Grain mask path
cd(projectPath);
cd('processed_images\grain_mask\');
grainMaskPath = pwd;

%% -------- LOAD MASK FILE --------
maskImg = imread(fullfile(grainMaskPath, 'inverted_mask.tif'));

if ndims(maskImg) == 3
    maskImg = rgb2gray(maskImg);
end

% BLOCK-AVERAGE
[H, W] = size(maskImg);
Hc = floor(H/blk)*blk; 
Wc = floor(W/blk)*blk; 
hBlocks = Hc / blk; 
wBlocks = Wc / blk;

% Original black-pixel mask at full resolution
blackMask_full = (maskImg == 0);

% Crop mask the same way as ratio image
blackMask_crop = blackMask_full(1:Hc, 1:Wc);

% Convert full-resolution mask to block-resolution mask
% One mapped pixel corresponds to one blk x blk block
Mresh = reshape(blackMask_crop, blk, hBlocks, blk, wBlocks);

% If any pixel in the block is black, mark that mapped pixel as black
blackMask = squeeze(any(any(Mresh, 1), 3));   % size = [hBlocks x wBlocks]
blackMask = logical(blackMask);

%% --- Mapping Curve ---
calibFile = dir(fullfile(logPath,'calibration_summary*.csv'));
T = readtable(fullfile(logPath, calibFile.name));
alpha_shared = T.alpha_shared(1);
Ksv_shared   = T.Ksv_shared(1);
alpha_all = T.alpha_ind;
Ksv_all   = T.Ksv_ind;
Rhigh_all = T.Rhigh_joint;
Chigh_all = T.C_high;

% This is the average ratio you want to evaluate
first_do_file = dir(fullfile(doRatioPath,'ratio_t*.mat'));
% Sort and pick first one
names = {first_do_file.name};
timeNums = nan(size(names));

for k = 1:numel(names)
    tok = regexp(names{k}, '^ratio_t(\d+)\.mat$', 'tokens', 'once');
    if ~isempty(tok)
        timeNums(k) = str2double(tok{1});
    end
end
[~, idx] = sort(timeNums);
first_do_file = first_do_file(idx(1));

first_do_ratio = load(fullfile(doRatioPath,first_do_file.name));
ratio_average = nanmean(first_do_ratio.do_ratio(:));

nOpt = numel(alpha_all);

C_est_all = nan(nOpt,1);

for i = 1:nOpt
    alpha_i = alpha_all(i);
    Ksv_i   = Ksv_all(i);
    Rhigh_i = Rhigh_all(i);
    Chigh_i = Chigh_all(i);

    % A_high for this optode
    A_high_i = alpha_i + (1 - alpha_i) / (1 + Ksv_i * Chigh_i);

    % Intermediate term
    B_i = (ratio_average / Rhigh_i) * A_high_i;

    % Check for invalid inversion
    if (B_i - alpha_i) <= 0 || ~isfinite(B_i)
        warning('Optode %d gives invalid inversion. Returning NaN.', i);
        C_est_all(i) = NaN;
    else
        C_est_all(i) = ((1 - alpha_i) / (B_i - alpha_i) - 1) / Ksv_i;
    end
end

Chigh = mean(C_est_all, 'omitnan');
A_high = alpha_shared + (1 - alpha_shared) ./ (1 + Ksv_shared .* Chigh);

% Reading all DO Ratio files
ratio_files = dir(fullfile(doRatioPath,'*.mat'));

% Sort ratio files by numeric time index
names = {ratio_files.name};
timeNums = nan(size(names));

for k = 1:numel(names)
    tok = regexp(names{k}, '^ratio_t(\d+)\.mat$', 'tokens', 'once');
    if ~isempty(tok)
        timeNums(k) = str2double(tok{1});
    else
        error('Filename does not match expected pattern: %s', names{k});
    end
end

[~, idx] = sort(timeNums);
ratio_files = ratio_files(idx);

Icrop = first_do_ratio.do_ratio(1:Hc, 1:Wc);
Iresh = reshape(double(Icrop), blk, hBlocks, blk, wBlocks);
Iavg  = squeeze(mean(mean(Iresh, 1), 3));      % [hBlocks × wBlocks]

for i = 1:numel(ratio_files)

    %% MAPPING

    ratioFile = load(fullfile(doRatioPath, ratio_files(i).name));

    % Current ratio image
    Rcur = ratioFile.do_ratio;
    
    % Crop to same size used for mask / block processing
    Rcrop = Rcur(1:Hc, 1:Wc);
    
    % Block-average current ratio image to match mapped size
    Rresh = reshape(double(Rcrop), blk, hBlocks, blk, wBlocks);
    Ravg  = squeeze(mean(mean(Rresh, 1), 3));   % [hBlocks x wBlocks]
    
    % Use current block-averaged ratio image in inversion
    B = (Ravg ./ ratio_average) .* A_high;
    mapped = ((1 - alpha_shared) ./ (B - alpha_shared) - 1) ./ Ksv_shared;

    % ratioFile = load(fullfile(doRatioPath, ratio_files(i).name));
    % B = (Iavg ./ ratioFile.do_ratio) .* A_high;
    % % Inversion formula:
    % % C = [ (1-alpha)/(B-alpha) - 1 ] / Ksv
    % mapped = ((1 - alpha_shared) ./ (B - alpha_shared) - 1) ./ Ksv_shared;
    %% ---------------- CLEAN RESULTS ----------------
    % Remove impossible or unstable values
    mapped(~isfinite(mapped)) = NaN;
    mapped(mapped < 0) = 0;
    
    % Optional: cap unrealistically high values
    % DO(DO > Chigh*1.2) = NaN;
    % mapped = a .* exp(b .* Iavg);   % direct mapping, unnormalized
    % mapped = min(max(mapped, 0), 7);  % clamp to [0,7] for display range
    
    %% DISPLAY HEATMAP
    figure('Color','w');
    imagesc(mapped);
    axis image off;
    caxis([0 7]);
    colormap(whiteRedBlue(256)); % <-- custom colormap below
    
    cb = colorbar;
    ylabel(cb,'Mapped value');
    % set(cb, 'Ticks', [0 1.5 2 3 7]);
    set(cb, 'Ticks', [0 2 7]);
    
    %% -------- OVERLAY BLACK MASK AS TRUE BLACK --------
    if ~isequal(size(blackMask,1), size(mapped,1)) || ~isequal(size(blackMask,2), size(mapped,2))
        error('Mask size must match mapped image size.');
    end
    
    hold on;
    % Create black RGB image
    overlay = zeros([size(blackMask), 3]);   % all zeros = black
    
    h = imshow(overlay);
    set(h, 'AlphaData', blackMask);          % show only mask pixels
    
    hold off;
    
    
    %% SAVE RESULTS
      
    % % Get timepoint label from filename
    % [~, baseName, ~] = fileparts(fretFiles(i).name);
    % timeLabel = extractBefore(baseName, '_ch01');
    % ratioMapName = fullfile(doRatioPath, sprintf('ratio_%s.mat', timeLabel));
    % 
    % % Save ratio image as .mat
    % save(ratioMapName, 'ratioFile', '-v7.3');
    % fprintf('✅ Saved ratio image: %s\n', ratioMapName);
  
    % Convert to RGB heatmap
    cmin = 0;
    cmax = 7;
    cmap = whiteRedBlue(256);
    
    mapped_norm = (mapped - cmin) ./ (cmax - cmin);
    mapped_norm = min(max(mapped_norm,0),1);
    
    idx = round(mapped_norm*(size(cmap,1)-1)) + 1;
    rgbImg = ind2rgb(idx,cmap);
    
    % Apply black mask to saved RGB heatmap
    rgbImg(repmat(blackMask, [1 1 3])) = 0;
    
    % % Get timepoint label from filename
    [~, baseName, ~] = fileparts(ratio_files(i).name);

    % Extract numeric part from ratio_t### format
    tok = regexp(baseName, '^ratio_t(\d+)$', 'tokens', 'once');
    if isempty(tok)
        error('Filename does not match expected pattern: %s', baseName);
    end
    
    tNum = str2double(tok{1});
    timeLabel = sprintf('t%03d', tNum); 
    
    % Save ratio image as .mat
    ratioMapName = fullfile(doMappedPath, sprintf('do_mapped_%s.mat', timeLabel));
    save(ratioMapName, 'mapped', '-v7.3');
    fprintf('✅ Saved ratio image: %s\n', ratioMapName);

    % Save tif
    imwrite(rgbImg, fullfile(heatmapPath, sprintf('heatmap_%s.tif', timeLabel)));

    fprintf('✅ Saved heatmap image and mapped data: %s\n', sprintf('heatmap_%s.tif', timeLabel));
    
end

fprintf('\nDone! All heatmaps and mapped images saved infolders\n');


%% === CUSTOM COLORMAP FUNCTION ===
function cmap = whiteRedBlue(n)
%  Red (0–1.5) → White (2) → Blue (3–7)
    if nargin < 1 || isempty(n), n = 256; end

    % % Define anchor points in data range 0–7 (Option 1)
    % anchorVals = [0, 1, 2, 4, 7];
    % anchorRGBs = [...
    %     1 0 0;   % 0   -> red
    %     1 0 0;   % 1.5 -> still red
    %     1 1 1;   % 2   -> white
    %     0 0 1;   % 3   -> blue
    %     0 0 1];  % 7   -> still blue
    
    % Define anchor points in data range 0–7 (Option 2)
    anchorVals = [0, 2, 7];
    anchorRGBs = [...
        1 0 0;   % 0   -> red
        1 1 1;   % 2   -> white
        0 0 1];  % 7   -> blue

    % Interpolate to full colormap
    xq = linspace(0, 7, n)';
    cmap = zeros(n, 3);
    for c = 1:3
        cmap(:,c) = interp1(anchorVals, anchorRGBs(:,c), xq, 'linear', 'extrap');
    end
    cmap = min(max(cmap, 0), 1);
end

