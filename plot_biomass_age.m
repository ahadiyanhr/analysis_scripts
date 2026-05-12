%% Plot completed biomass-age distributions from sloughed pixels only
%
% ageFrame values (from the fixed age-builder):
%   NaN  = grain/void pixel (permanent)
%   -1   = pixel that just sloughed this frame        ← used here to detect sloughing
%   0    = pore, no biomass
%   >0   = active biomass age in hours

clear; clc; close all;

%% ======== USER SETTINGS ========

% Frames to include in the ridgeline plot (1-based, matching file order).
% All frames are still processed for age collection — this only controls plotting.
% Example: plotFrames = [10, 20, 30, 40, 50, 60];
% Set to [] to auto-plot every frame that has sloughing data.
plotFrames = [];

% Maximum number of ages to keep per frame (inf = keep all)
maxPointsPerFrame = inf;

%% ======== PATHS ========
mainPath = pwd;
cd(mainPath); cd('../');
projectPath = pwd;

plotFolder = fullfile(projectPath, 'processed_data', 'plots');
ageFolder  = fullfile(projectPath, 'processed_data', 'biomass_age');

ageFiles = dir(fullfile(ageFolder, 'biomass_age_*.mat'));
if isempty(ageFiles)
    error('No biomass_age_*.mat files found in: %s', ageFolder);
end
[~, idx] = sort({ageFiles.name});
ageFiles  = ageFiles(idx);
nFiles    = numel(ageFiles);
fprintf('Found %d biomass-age files.\n', nFiles);

%% ======== COLLECT OR LOAD COMPLETED + ACTIVE AGES ========

cacheFile    = fullfile(ageFolder, 'completed_ages_all_frames.mat');
cacheVars    = {'allAges', 'allAgesActive', 'allTimes'};
cacheValid   = false;

if isfile(cacheFile)
    cacheInfo  = whos('-file', cacheFile);             % list variables inside the file
    savedVars  = {cacheInfo.name};
    cacheValid = all(ismember(cacheVars, savedVars));  % true only if ALL variables present

    if cacheValid
        fprintf('Cache found and complete. Loading from:\n  %s\n', cacheFile);
        load(cacheFile, 'allAges', 'allAgesActive', 'allTimes');
        nFiles = numel(allAges);
        fprintf('Loaded %d frames from cache.\n', nFiles);
    else
        missing = cacheVars(~ismember(cacheVars, savedVars));
        fprintf('Cache found but missing: %s\n  Reprocessing all frames...\n', ...
            strjoin(missing, ', '));
    end
end

if ~cacheValid

    allTimes      = nan(nFiles, 1);
    allAges       = cell(nFiles, 1);
    allAgesActive = cell(nFiles, 1);

    Sprev        = load(fullfile(ageFolder, ageFiles(1).name), ...
                        'ageFrame', 'currentTime');
    prevAgeFrame = Sprev.ageFrame;
    allTimes(1)  = double(Sprev.currentTime);

    activeAges1      = prevAgeFrame(prevAgeFrame > 0);
    allAgesActive{1} = activeAges1(~isnan(activeAges1));

    for i = 2:nFiles

        S        = load(fullfile(ageFolder, ageFiles(i).name), ...
                        'ageFrame', 'currentTime', 'sloughedMask');
        ageFrame = S.ageFrame;
        allTimes(i) = double(S.currentTime);

        sloughedMask  = S.sloughedMask;
        completedAges = prevAgeFrame(sloughedMask);
        completedAges = completedAges(completedAges > 0 & ~isnan(completedAges));

        if numel(completedAges) > maxPointsPerFrame
            sIdx = round(linspace(1, numel(completedAges), maxPointsPerFrame));
            completedAges = completedAges(sIdx);
        end
        allAges{i} = completedAges;

        activeAges = ageFrame(ageFrame > 0);
        activeAges = activeAges(~isnan(activeAges));

        if numel(activeAges) > maxPointsPerFrame
            sIdx = round(linspace(1, numel(activeAges), maxPointsPerFrame));
            activeAges = activeAges(sIdx);
        end
        allAgesActive{i} = activeAges;

        prevAgeFrame = ageFrame;

        fprintf('File %d/%d | t=%.1fhr | sloughed=%d | active=%d\n', ...
            i, nFiles, allTimes(i), numel(completedAges), numel(activeAges));
    end

    save(cacheFile, 'allAges', 'allAgesActive', 'allTimes');
    fprintf('Cache saved to:\n  %s\n', cacheFile);

end

%% ======== SELECT PLOT FRAMES ========

if isempty(plotFrames)
    plotIdx = find(~cellfun(@isempty, allAges));
else
    plotIdx = plotFrames;
end

hasData  = ~cellfun(@isempty, allAges(plotIdx)) & ~isnan(allTimes(plotIdx));
plotIdx  = plotIdx(hasData);

allAgesValid       = allAges(plotIdx);
allAgesActiveValid = allAgesActive(plotIdx);
allTimesValid      = allTimes(plotIdx);
nT                 = numel(allAgesValid);

fprintf('\nPlotting %d selected frames.\n', nT);

%% ======== BUILD HEATMATRICES ========

nBins    = 50;
maxAgeSloughed = max(cellfun(@(x) max(x(:)), allAgesValid(~cellfun(@isempty,allAgesValid))));
maxAgeActive   = max(cellfun(@(x) max(x(:)), allAgesActiveValid(~cellfun(@isempty,allAgesActiveValid))));

edgesS = linspace(0, maxAgeSloughed, nBins+1);
edgesA = linspace(0, maxAgeActive,   nBins+1);

heatSloughed = zeros(nT, nBins);
heatActive   = zeros(nT, nBins);
mediansS     = zeros(nT, 1);
mediansA     = zeros(nT, 1);

for k = 1:nT

    % Sloughed
    ages = double(allAgesValid{k});
    if numel(ages) >= 2
        c = histcounts(ages, edgesS);
        if max(c) > 0; heatSloughed(k,:) = c / max(c); end
        mediansS(k) = median(ages);
    end

    % Active
    ages = double(allAgesActiveValid{k});
    if numel(ages) >= 2
        c = histcounts(ages, edgesA);
        if max(c) > 0; heatActive(k,:) = c / max(c); end
        mediansA(k) = median(ages);
    end

end

%% ======== Y-AXIS TICK LABELS (from plotIdx — already filtered) ========

tickStep   = 5;
tickPos    = 1:tickStep:nT;              % row indices into the nT valid frames
tickFrames = plotIdx(tickPos);           % FIX: use plotIdx not plotFrames
                                         % plotIdx is already filtered to nT entries
tickLabels = arrayfun(@(n) sprintf('#%03d', n), tickFrames, 'UniformOutput', false);

%% ======== PLOT: TWO HEATMAPS SIDE BY SIDE ========

accentColor = [0.30 0.65 1.00];   % ADD THIS LINE

fig = figure('Color','w','Position',[100 80 1300 700]);
tl  = tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

binCentersS = edgesS(1:end-1) + diff(edgesS)/2;
binCentersA = edgesA(1:end-1) + diff(edgesA)/2;

%% --- LEFT: Sloughed completed ages ---
ax1 = nexttile(tl, 1);

imagesc(ax1, binCentersS, 1:nT, heatSloughed);
axis(ax1, 'xy');
colormap(ax1, flipud(hot));
cb1 = colorbar(ax1);
cb1.Label.String = 'Normalized density';
clim(ax1, [0 1]);

hold(ax1, 'on');

% Diagonal boundary (max possible age = experiment time)
plot(ax1, allTimesValid, 1:nT, '--', ...
    'Color', accentColor, 'LineWidth', 1.5, ...
    'DisplayName', 'Max possible age');

% Median
plot(ax1, mediansS, 1:nT, '-o', ...
    'Color', accentColor, 'MarkerFaceColor', accentColor, ...
    'MarkerSize', 4, 'LineWidth', 1.5, ...
    'DisplayName', 'Median');

xlabel(ax1, 'Completed age at sloughing (hr)', 'FontSize', 11, 'FontWeight', 'bold');
ylabel(ax1, 'Image number',                     'FontSize', 11, 'FontWeight', 'bold');

yticks(ax1, tickPos);
yticklabels(ax1, tickLabels);
legend(ax1, 'Location', 'northwest', 'Box', 'off', 'FontSize', 9);
grid(ax1, 'off'); box(ax1, 'on');

%% --- RIGHT: Active biomass ages ---
ax2 = nexttile(tl, 2);

imagesc(ax2, binCentersA, 1:nT, heatActive);
axis(ax2, 'xy');
colormap(ax2, flipud(hot));
cb2 = colorbar(ax2);
cb2.Label.String = 'Normalized density';
clim(ax2, [0 1]);

hold(ax2, 'on');

% Diagonal boundary
plot(ax2, allTimesValid, 1:nT, '--', ...
    'Color', accentColor, 'LineWidth', 1.5, ...
    'DisplayName', 'Max possible age');

% Median
plot(ax2, mediansA, 1:nT, '-o', ...
    'Color', accentColor, 'MarkerFaceColor', accentColor, ...
    'MarkerSize', 4, 'LineWidth', 1.5, ...
    'DisplayName', 'Median');

xlabel(ax2, 'Active biomass age (hr)', 'FontSize', 11, 'FontWeight', 'bold');
ylabel(ax2, 'Image number',            'FontSize', 11, 'FontWeight', 'bold');

yticks(ax2, tickPos);
yticklabels(ax2, tickLabels);
legend(ax2, 'Location', 'northwest', 'Box', 'off', 'FontSize', 9);
grid(ax2, 'off'); box(ax2, 'on');

exportgraphics(fig, fullfile(plotFolder, 'biomass_age_heatmaps_dual.pdf'), ...
    'Resolution', 300);
fprintf('Saved dual heatmap to:\n  %s\n', plotFolder);
