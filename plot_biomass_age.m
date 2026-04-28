%% Ridgeline plot of biomass age evolution

clear; clc; close all;

%% -------- Paths --------

mainPath = pwd;
cd(mainPath); cd('../');
projectPath = pwd;

ageFolder = fullfile(projectPath, ...
    'processed_data', 'biomass_age');

ageFiles = dir(fullfile(ageFolder, 'biomass_age_*.mat'));


[~, idx] = sort({ageFiles.name});
ageFiles = ageFiles(idx);

nFiles = numel(ageFiles);

%% -------- Collect data --------

allTimes = nan(nFiles,1);
allAges = cell(nFiles,1);
maxAge = 0;

for i = 1:nFiles

    S = load(fullfile(ageFolder, ageFiles(i).name), ...
        'ageFrame', 'currentTime');

    ageFrame = S.ageFrame;

    ages = ageFrame(ageFrame > 0 & ~isnan(ageFrame));

    allAges{i} = ages;

    if ~isempty(ages)
        maxAge = max(maxAge, max(ages));
    end

    if isfield(S,'currentTime')
        allTimes(i) = double(S.currentTime);
    else
        allTimes(i) = i;
    end
end

%% -------- Define common x grid --------

x = linspace(0, maxAge, 200);

%% -------- Create ridgeline plot --------

figure('Color','w');
hold on;

offset = 0;                % vertical stacking offset
offsetStep = 1.2;          % spacing between ridges

cmap = jet(nFiles);        % blue → red

for i = 1:nFiles

    ages = allAges{i};

    if isempty(ages)
        offset = offset + offsetStep;
        continue;
    end

    % Kernel density estimate
    try
        f = ksdensity(ages, x);
    catch
        % fallback if too few points
        f = histcounts(ages, [x max(x)+1], 'Normalization','pdf');
        f = [f f(end)];
    end

    % Normalize each ridge (optional but cleaner)
    f = f / max(f);

    % Shift vertically
    y = f + offset;

    % Color based on time
    plot(x, y, 'Color', cmap(i,:), 'LineWidth', 1.5);

    % Fill area (optional, looks nicer)
    fill([x fliplr(x)], ...
         [offset*ones(size(x)) fliplr(y)], ...
         cmap(i,:), ...
         'FaceAlpha', 0.3, ...
         'EdgeColor', 'none');

    offset = offset + offsetStep;
end

%% -------- Labels --------

xlabel('Biomass age (hr)');
ylabel('Experiment time progression (stacked)');
title('Ridgeline plot of biomass age distribution over time');

colormap(jet);
cb = colorbar;
cb.Label.String = 'Relative experiment time';
caxis([min(allTimes) max(allTimes)]);

grid on;
box on;


%% Overlay normalized density plots for all timestamps (color = time)

figure('Color','w');
hold on;

% Normalize time to [0,1] for colormap
tNorm = (allTimes - min(allTimes)) / (max(allTimes) - min(allTimes));

cmap = jet(256);

for i = 1:nFiles

    ages = allAges{i};

    if isempty(ages)
        continue;
    end

    % Optional downsampling if huge
    if numel(ages) > 1e5
        ages = ages(1:10:end);
    end

    % KDE
    try
        f = ksdensity(ages, x);
    catch
        f = histcounts(ages, [x max(x)+1], 'Normalization','pdf');
        f = [f f(end)];
    end

    % Normalize (optional, helps comparison of shape)
    f = f / max(f);

    % Map time to color
    colorIdx = max(1, round(tNorm(i)*255)+1);
    color = cmap(colorIdx, :);

    plot(x, f, 'Color', color, 'LineWidth', 1.2);

end

%% -------- Labels --------

xlabel('Biomass age (hr)');
ylabel('Normalized density');
title('Biomass-age distribution over time (overlay)');

colormap(jet);
cb = colorbar;
cb.Label.String = 'Experiment time (normalized)';
caxis([min(allTimes) max(allTimes)]);

grid on;
box on;

%% Overlay density plots for all timestamps (color = time)

figure('Color','w');
hold on;

% Normalize time to [0,1] for colormap
tNorm = (allTimes - min(allTimes)) / (max(allTimes) - min(allTimes));

cmap = jet(256);

for i = 1:nFiles

    ages = allAges{i};

    if isempty(ages)
        continue;
    end

    % Optional downsampling if huge
    if numel(ages) > 1e5
        ages = ages(1:10:end);
    end

    % KDE
    try
        f = ksdensity(ages, x);
    catch
        f = histcounts(ages, [x max(x)+1], 'Normalization','pdf');
        f = [f f(end)];
    end

    % Map time to color
    colorIdx = max(1, round(tNorm(i)*255)+1);
    color = cmap(colorIdx, :);

    plot(x, f, 'Color', color, 'LineWidth', 1.2);

end

%% -------- Labels --------

xlabel('Biomass age (hr)');
ylabel('Normalized density');
title('Biomass-age distribution over time (overlay)');

colormap(jet);
cb = colorbar;
cb.Label.String = 'Experiment time (normalized)';
caxis([min(allTimes) max(allTimes)]);

grid on;
box on;
