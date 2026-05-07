%% Plot completed biomass-age distributions from sloughed pixels only
% Uses biomass_age_001.mat, biomass_age_002.mat, ...
%
% ageFrame values:
%   0    = no biomass
%   NaN  = biomass was present before, but disappeared at this time step
%   >0   = active biomass age, still occupied
%
% This script removes all still-active >0 biomass ages from the analysis.
% It only uses NaN pixels, then extracts their age from the previous frame.

clear; clc; close all;

%% -------- User settings --------

startFile = 2;        % Start from 2 because frame 1 has no previous ageFrame
spaceData = 10;       % Space between data frames
maxPointsPerFrame = inf;

%% -------- Paths --------

mainPath = pwd;
cd(mainPath); cd('../');
projectPath = pwd;

plotFolder = fullfile(projectPath, 'processed_data', 'plots');

ageFolder = fullfile(projectPath, ...
    'processed_data', 'biomass_age');

ageFiles = dir(fullfile(ageFolder, 'biomass_age_*.mat'));

if isempty(ageFiles)
    error('No biomass_age_*.mat files found in: %s', ageFolder);
end

[~, idx] = sort({ageFiles.name});
ageFiles = ageFiles(idx);

nFiles = numel(ageFiles);

fprintf('Found %d biomass-age files.\n', nFiles);

%% -------- Collect completed biomass ages --------
% allAges{i} = ages of biomass pixels that sloughed at timestamp i

allTimes = nan(nFiles,1);
allAges = cell(nFiles,1);
maxAge = 0;

% Load first frame as previous frame
Sprev = load(fullfile(ageFolder, ageFiles(1).name), ...
    'ageFrame', 'currentTime');

prevAgeFrame = Sprev.ageFrame;

if isfield(Sprev, 'currentTime')
    allTimes(1) = double(Sprev.currentTime);
else
    allTimes(1) = 1;
end

for i = startFile:spaceData:nFiles

    S = load(fullfile(ageFolder, ageFiles(i).name), ...
        'ageFrame', 'currentTime');

    ageFrame = S.ageFrame;

    if isfield(S, 'currentTime')
        allTimes(i) = double(S.currentTime);
    else
        allTimes(i) = i;
    end

    % Pixels that sloughed at current timestamp
    sloughedMask = isnan(ageFrame);

    % Their completed age is the age from the previous frame
    completedAges = prevAgeFrame(sloughedMask);

    % Keep only valid previous ages
    completedAges = completedAges(completedAges > 0 & ~isnan(completedAges));

    % Optional downsampling for memory/plot speed
    if numel(completedAges) > maxPointsPerFrame
        sampleIdx = round(linspace(1, numel(completedAges), maxPointsPerFrame));
        completedAges = completedAges(sampleIdx);
    end

    allAges{i} = completedAges;

    if ~isempty(completedAges)
        maxAge = max(maxAge, max(completedAges));
    end

    % Update previous frame
    prevAgeFrame = ageFrame;

    fprintf('Processed file %d/%d: %d completed ages\n', ...
        i, nFiles, numel(completedAges));
end

% Remove empty timestamps for plotting
validIdx = ~cellfun(@isempty, allAges) & ~isnan(allTimes);

allAgesValid = allAges(validIdx);
allTimesValid = allTimes(validIdx);

nValid = numel(allAgesValid);

if nValid == 0
    error('No completed biomass ages found. Check whether NaN exists in your ageFrame files.');
end

fprintf('Using %d timestamps with completed sloughing ages.\n', nValid);

%% -------- Define common x grid --------

xMax = max(allTimesValid);   % experiment time axis, not biomass age axis
x = linspace(0, xMax, 200);

% %% -------- Plot 1: Ridgeline plot --------
% 
% fig1 = figure('Color','w');
% hold on;
% 
% offset = 0;
% offsetStep = 1.2;
% 
% cmap = jet(nValid);
% 
% for k = 1:nValid
% 
%     ages = allAgesValid{k};
% 
%     if numel(ages) < 2
%         continue;
%     end
% 
%     try
%         f = ksdensity(ages, x);
%     catch
%         counts = histcounts(ages, [x max(x)+eps], 'Normalization','pdf');
%         f = counts;
%     end
% 
%     if max(f) > 0
%         f = f / max(f);
%     end
% 
%     y = f + offset;
% 
%     plot(x, y, 'Color', cmap(k,:), 'LineWidth', 1.5);
% 
%     fill([x fliplr(x)], ...
%          [offset*ones(size(x)) fliplr(y)], ...
%          cmap(k,:), ...
%          'FaceAlpha', 0.3, ...
%          'EdgeColor', 'none');
% 
%     offset = offset + offsetStep;
% end
% 
% xlabel('Completed biomass age before sloughing (hr)');
% ylabel('Density distribution (stacked)');
% title('Ridgeline plot of completed biomass ages');
% 
% colormap(jet);
% cb = colorbar;
% cb.Label.String = 'Image #';
% caxis([min(allTimesValid) max(allTimesValid)]);
% 
% grid on;
% box on;
% 
% saveas(fig1, fullfile(plotFolder, 'completed_biomass_age_ridgeline.png'));

%% -------- Plot 1: Ridgeline plot (corrected) --------

fig1 = figure('Color', 'w');
hold on;

offset     = 0;
offsetStep = 1.2;

% --- Distinguishable color palette (up to ~20 traces) ---
baseColors = [
    0.00  0.45  0.70;   % blue
    0.85  0.33  0.10;   % orange-red
    0.47  0.67  0.19;   % green
    0.50  0.00  0.50;   % purple
    0.93  0.69  0.13;   % gold
    0.30  0.75  0.93;   % sky blue
    0.64  0.08  0.18;   % dark red
    0.00  0.60  0.50;   % teal
    1.00  0.60  0.00;   % amber
    0.49  0.18  0.56;   % violet
    0.19  0.53  0.74;   % steel blue
    0.74  0.74  0.13;   % olive
    1.00  0.40  0.40;   % salmon
    0.13  0.70  0.67;   % cyan-green
    0.80  0.47  0.74;   % mauve
    0.55  0.34  0.29;   % brown
    0.57  0.82  0.31;   % lime
    0.09  0.75  0.81;   % aqua
    0.99  0.75  0.44;   % peach
    0.39  0.58  0.93;   % periwinkle
];

nColors = size(baseColors, 1);

for k = 1:nValid

    ages = allAgesValid{k};
    tMax = allTimesValid(k);   % this image's experiment time (hr)

    if numel(ages) < 2
        continue;
    end

    % --- 1. Clip x to [0, tMax] so the area never extends beyond its own time ---
    xk = x(x <= allTimesValid(k));
    if isempty(xk)
        xk = linspace(0, allTimesValid(k), 50);
    end

    % --- KDE on clipped grid ---
    try
        f = ksdensity(ages, xk);
    catch
        edges  = [xk, max(xk) + eps];
        counts = histcounts(ages, edges, 'Normalization', 'pdf');
        f      = counts;
        if numel(f) < numel(xk)
            f(end+1:numel(xk)) = 0;
        end
    end

    % Normalize peak to 1
    if max(f) > 0
        f = f / max(f);
    end

    y     = f + offset;
    color = baseColors(mod(k-1, nColors) + 1, :);

    % Ridge line
    plot(xk, y, 'Color', color, 'LineWidth', 1.8);

    % Filled area from the local baseline (offset) up to the curve
    fill([xk, fliplr(xk)], ...
         [offset * ones(size(xk)), fliplr(y)], ...
         color, 'FaceAlpha', 0.35, 'EdgeColor', 'none');

    % --- 3. Time label at the right end of this area ---
    text(tMax + maxAge * 0.015, ...        % just past the right edge
         offset + 0.50, ...                % vertically centred in the ridge
         sprintf('%.0f hr', tMax), ...
         'Color',           color, ...
         'FontSize',        9, ...
         'FontWeight',      'bold', ...
         'VerticalAlignment','middle', ...
         'HorizontalAlignment','left');

    offset = offset + offsetStep;
end

xlabel('Completed biomass age before sloughing (hr)');
ylabel('Density (stacked, normalized)');
title('Ridgeline plot of completed biomass ages');

% Extend x-axis a little to make room for labels
xlim([0, maxAge * 1.18]);

% No colorbar — colors are self-labelled on the right
grid on;
box on;

saveas(fig1, fullfile(plotFolder, 'completed_biomass_age_ridgeline.png'));

% %% -------- Plot 2: Overlay normalized density plots --------
% 
% fig2 = figure('Color','w');
% hold on;
% 
% tNorm = (allTimesValid - min(allTimesValid)) ./ ...
%         (max(allTimesValid) - min(allTimesValid));
% 
% if all(isnan(tNorm)) || allTimesValid(1) == allTimesValid(end)
%     tNorm = zeros(size(allTimesValid));
% end
% 
% cmap = jet(256);
% 
% for k = 1:nValid
% 
%     ages = allAgesValid{k};
% 
%     if numel(ages) < 2
%         continue;
%     end
% 
%     try
%         f = ksdensity(ages, x);
%     catch
%         counts = histcounts(ages, [x max(x)+eps], 'Normalization','pdf');
%         f = counts;
%     end
% 
%     if max(f) > 0
%         f = f / max(f);
%     end
% 
%     colorIdx = max(1, min(256, round(tNorm(k)*255)+1));
%     color = cmap(colorIdx, :);
% 
%     plot(x, f, 'Color', color, 'LineWidth', 1.2);
% end
% 
% xlabel('Completed biomass age before sloughing (hr)');
% ylabel('Normalized density');
% title('Completed biomass-age distribution over time');
% 
% colormap(jet);
% cb = colorbar;
% cb.Label.String = 'Experiment time (hr)';
% caxis([min(allTimesValid) max(allTimesValid)]);
% 
% grid on;
% box on;
% 
% saveas(fig2, fullfile(plotFolder, 'completed_biomass_age_norm_density.png'));
% 
% %% -------- Plot 3: Overlay raw density plots --------
% 
% fig3 = figure('Color','w');
% hold on;
% 
% for k = 1:nValid
% 
%     ages = allAgesValid{k};
% 
%     if numel(ages) < 2
%         continue;
%     end
% 
%     try
%         f = ksdensity(ages, x);
%     catch
%         counts = histcounts(ages, [x max(x)+eps], 'Normalization','pdf');
%         f = counts;
%     end
% 
%     colorIdx = max(1, min(256, round(tNorm(k)*255)+1));
%     color = cmap(colorIdx, :);
% 
%     plot(x, f, 'Color', color, 'LineWidth', 1.2);
% end
% 
% xlabel('Completed biomass age before sloughing (hr)');
% ylabel('Probability density');
% title('Completed biomass-age raw density over time');
% 
% colormap(jet);
% cb = colorbar;
% cb.Label.String = 'Experiment time (hr)';
% caxis([min(allTimesValid) max(allTimesValid)]);
% 
% grid on;
% box on;
% 
% saveas(fig3, fullfile(plotFolder, 'completed_biomass_age_density.png'));
