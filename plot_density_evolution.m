%% plot_density_evolution.m
%
% Reads the thresholded biomass matrices (thresholded_XX.mat) produced by
% the registration/thresholding pipeline for ONE experiment, crops out the
% inlet/outlet chambers (symmetric about the centerline, keeping only the
% reactor length = reactorLengthFactor x reactorHeight_mm), and plots a
% single space-time heatmap of biomass density evolution:
%
%   x-axis  = time
%   y-axis  = position along flow (mm)
%   color   = discrete density bin (0-0.1, 0.1-0.2, ..., 0.9-1)
%   gray    = grain pixels (excluded from biomass)
%
% Output: vector PDF + PNG, sized according to plotSize below.

clc; clearvars; close all;

%% -------- Setup (same path convention as registration script) --------

sensitivity = 0.5;   % must match the sensitivity used during thresholding
flowDim     = 2;     % 2 = flow along columns (x), 1 = flow along rows (y)
dt_minutes  = 30;    % time interval between saved frames

reactorHeight_mm  = 10;    % physical reactor height (the non-flow dimension) -- sets the px->mm scale
reactorLengthFactor = 1.5; % reactor length = reactorLengthFactor * reactorHeight_mm (here: 15 mm)
                            % used to crop out inlet/outlet chambers, symmetric about the centerline

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Thresholded images path (must match the folder created by the
% registration/thresholding script)
threshFolderName = sprintf('processed_images\\thresholded_images\\sensitivity_%s_main_results', ...
                            strrep(num2str(sensitivity), '.', '.'));
threshMatPath = fullfile(projectPath, threshFolderName);

% Plots path
cd(projectPath);
cd('processed_data\plots\');
plotPath = pwd;
cd(mainPath);

%% -------- Choose final plot size --------
% Options: 'pnas_single'  -> 3.42 x 4.5 in  (PNAS single column)
%          'pnas_double'  -> 7.0  x 5.5 in  (PNAS double column)
%          'custom'       -> set customWidth_in / customHeight_in below

plotSize = 'pnas_double';   % <-- change this

customWidth_in  = 6.5;
customHeight_in = 5.0;

switch plotSize
    case 'pnas_single'
        figWidth_in  = 3.42;
        figHeight_in = 4.50;
    case 'pnas_double'
        figWidth_in  = 7.00;
        figHeight_in = 5.50;
    case 'custom'
        figWidth_in  = customWidth_in;
        figHeight_in = customHeight_in;
    otherwise
        error('Unknown plotSize option: %s', plotSize);
end

%% -------- Load thresholded matrices --------

files = dir(fullfile(threshMatPath, 'thresholded_*.mat'));
if isempty(files)
    error('No thresholded_*.mat files found in: %s', threshMatPath);
end

idxNum = zeros(numel(files), 1);
for k = 1:numel(files)
    tok = regexp(files(k).name, 'thresholded_(\d+)\.mat', 'tokens');
    idxNum(k) = str2double(tok{1}{1});
end
[~, order] = sort(idxNum);
files  = files(order);
idxNum = idxNum(order);

nT = numel(files);
kymo = [];
meanDensity = nan(nT, 1);

mm_per_px  = [];
cropIdx    = [];   % indices (along the flow dimension) kept after cropping inlet/outlet

for k = 1:nT
    S  = load(fullfile(threshMatPath, files(k).name));
    fn = fieldnames(S);
    M  = S.(fn{1});   % NaN = grain, 0 = empty pore, (0,1] = biomass density

    % -------- Determine crop + px->mm scale once, from the first frame --------
    if isempty(cropIdx)
        if flowDim == 2
            heightPx = size(M, 1);   % non-flow dimension = reactor height
            nLenFull = size(M, 2);   % flow dimension = full image length (incl. inlet/outlet)
        else
            heightPx = size(M, 2);
            nLenFull = size(M, 1);
        end

        mm_per_px      = reactorHeight_mm / heightPx;
        reactorLengthPx = round(reactorLengthFactor * heightPx);

        startIdx = max(1, round((nLenFull - reactorLengthPx) / 2) + 1);
        endIdx   = min(nLenFull, startIdx + reactorLengthPx - 1);
        cropIdx  = startIdx:endIdx;   % symmetric crop about the centerline
    end

    % -------- Crop out inlet/outlet chambers, keep only the reactor section --------
    if flowDim == 2
        M = M(:, cropIdx);
        profile = mean(M, 1, 'omitnan');   % collapse rows -> profile along x
        profile = profile(:);
    else
        M = M(cropIdx, :);
        profile = mean(M, 2, 'omitnan');   % collapse columns -> profile along y
    end

    if isempty(kymo)
        kymo       = nan(numel(profile), nT);
        posAxis_mm = (0:numel(profile)-1)' * mm_per_px;   % position along flow, in mm
    end
    kymo(:, k) = profile;

    meanDensity(k) = mean(M(:), 'omitnan');
end

tvec = idxNum * (dt_minutes / 60);   % hours, frame 0 = t = 0

%% -------- Discrete binning (0-0.1, 0.1-0.2, ..., 0.9-1) --------

nBins   = 10;
edges   = linspace(0, 0.7, nBins + 1);          % 0:0.1:1
binIdx  = discretize(kymo, edges);            % NaN (grain) stays NaN

binColors = turbo(nBins);                     % one solid color per bin

binLabels = strings(nBins, 1);
for b = 1:nBins
    binLabels(b) = sprintf('%.1f-%.1f', edges(b), edges(b+1));
end

%% -------- Figure --------

fig = figure('Units', 'inches', 'Position', [1 1 figWidth_in figHeight_in], 'Color', 'w');

fontName = 'Helvetica';
fontSize = 8;
set(fig, 'DefaultAxesFontName', fontName, 'DefaultAxesFontSize', fontSize, ...
         'DefaultTextFontName', fontName, 'DefaultTextFontSize', fontSize);

axKymo = axes(fig);

imagesc(axKymo, tvec, posAxis_mm, binIdx, [0.5, nBins + 0.5]);
set(axKymo, 'YDir', 'normal');
colormap(axKymo, binColors);

% Grain pixels (NaN) rendered as light gray instead of a bin color
set(axKymo, 'Color', [0.85 0.85 0.85]);
alphaMask = ~isnan(binIdx);
imgHandle = findobj(axKymo, 'Type', 'image');
set(imgHandle, 'AlphaData', alphaMask);

xlabel(axKymo, 'Time (h)');
ylabel(axKymo, 'Position along flow (mm)');
title(axKymo, 'Biofilm density evolution', 'FontWeight', 'bold', 'FontSize', fontSize+1);
box(axKymo, 'on');

cb = colorbar(axKymo, 'eastoutside');
cb.Ticks = 1:nBins;
cb.TickLabels = binLabels;
cb.Label.String = 'Normalized biomass density';
cb.Label.FontSize = fontSize;

%% -------- Export --------

figBaseName = 'density_evolution';
pngPath = fullfile(plotPath, [figBaseName '.png']);

set(fig, 'PaperPositionMode', 'auto');
exportgraphics(fig, pngPath, 'Resolution', 600);

fprintf('\nSaved:\n  %s\n  %s\n', pdfPath, pngPath);