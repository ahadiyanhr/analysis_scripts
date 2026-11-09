clear; clc; close all;

%% Single-panel PNAS timeseries figure — REPLICATE / MULTI-EXPERIMENT OVERLAY
%
% Combines multiple experiments/replicates (each already processed once
% with plot_for_manuscripts_1panels.m, which saves a
% "<expLabel>_manuscript_data.mat" file into each project's
% processed_data/plots/replicate_data/ folder) onto ONE single-panel figure.
%
% LEFT  y-axis : hydraulic parameter (flowrate for cP, ΔP for cQ)
% RIGHT y-axis : Biomass occupation (%) and DO (rescaled %)
%
% Colors match plot_for_manuscripts_1panels.m (steel blue = flowrate,
% crimson = ΔP, olive = biomass, teal = DO) so they stay consistent with
% the rest of the manuscript. Replicates/experiments are distinguished by
% LINE STYLE instead (1st = solid, 2nd = dashed, 3rd = dotted, ...), since
% there is normally just one replicate per experiment (solid vs dashed).
% A compact legend (line style → experiment) is placed at the top of the panel.
%
% All combined experiments must share the same experiment type (flag_cP)
% and the same DO_MAX_MGPL — the script errors out otherwise, since mixing
% flowrate/ΔP or differently-scaled DO on one axis would be meaningless.
%
% Export: 8" × 2.5" PDF (vector) + TIF (300 dpi)

%% =========================================================
%  USER SETTINGS  ← edit here
%% =========================================================

% --- Project folders to combine ---
% One entry per replicate/experiment = the MainFolderProject path (the
% folder that contains raw_data/, processed_data/, logs/, etc. — the SAME
% folder plot_for_manuscripts_1panels.m was run from one level up).
repProjectPaths = { ...
    'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\20260207 - cQ 10% inline PS (successful) [BRC]', ...
    'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\20260730 - cQ 10% at highQ (successful) [HIP]', ...
    };

% --- Output location for the combined figure ---
% Defaults to a "combined_plots" folder next to this script; edit if needed.
combinedOutDir = fullfile(repProjectPaths{1}, 'processed_data', 'plots');

% --- Event lines (applied to all replicates, e.g. a shared treatment onset) ---
eventTimes  = [];          % <-- edit: e.g. [24, 48, 72]
eventLabels = {};          % <-- edit: e.g. {'PSS onset', 'Sloughing', 'Re-clogging'}
eventColor  = [0.0 0.0 0.0];
eventLW     = 1;

% --- Reference replicate for ±1σ DO shading ---
% Index into repProjectPaths whose DO band (±1σ) is shown.
% Only one replicate gets a shaded band (all replicates share the same
% teal color, so overlapping bands from several replicates would be
% indistinguishable from each other and just look like clutter).
refReplicateIdx = 1;

%% =========================================================
%  LOAD REPLICATE DATA
%% =========================================================
nRep = numel(repProjectPaths);
if nRep == 0
    error('repProjectPaths is empty — add at least one project folder.');
end

reps = cell(nRep, 1);
for i = 1:nRep
    repDataPath = fullfile(repProjectPaths{i}, 'processed_data', 'plots', 'replicate_data');
    listing = dir(fullfile(repDataPath, '*_manuscript_data.mat'));
    if isempty(listing)
        error('No *_manuscript_data.mat found in:\n%s\nRun plot_for_manuscripts_1panels.m for this experiment first.', repDataPath);
    end
    S = load(fullfile(repDataPath, listing(1).name));
    reps{i} = S.repData;
end

%% =========================================================
%  VALIDATE CONSISTENCY ACROSS REPLICATES
%% =========================================================
flag_cP     = reps{1}.flag_cP;
DO_MAX_MGPL = reps{1}.DO_MAX_MGPL;

for i = 2:nRep
    if reps{i}.flag_cP ~= flag_cP
        error(['Experiment type mismatch: "%s" is %s but "%s" is %s. ' ...
               'Only replicates of the SAME experiment type can be combined on one axis.'], ...
               reps{1}.expLabel, reps{1}.exp_type, reps{i}.expLabel, reps{i}.exp_type);
    end
    if reps{i}.DO_MAX_MGPL ~= DO_MAX_MGPL
        error('DO_MAX_MGPL mismatch between "%s" (%g) and "%s" (%g) — DO %% would not be comparable.', ...
               reps{1}.expLabel, DO_MAX_MGPL, reps{i}.expLabel, reps{i}.DO_MAX_MGPL);
    end
end

if refReplicateIdx < 1 || refReplicateIdx > nRep
    error('refReplicateIdx = %d is out of range (1..%d).', refReplicateIdx, nRep);
end

% Hydraulic parameter always on LEFT, biomass/DO always on RIGHT
hydraulicAxis = 'left';
bioDOAxis     = 'right';

%% =========================================================
%  COLORS  (same tone as plot_for_manuscripts_1panels.m)
%% =========================================================
clrBio = [0.483  0.619  0.243];   % olive       — biomass
clrDO  = [0.004  0.400  0.369];   % teal        — dissolved oxygen
clrQ   = [0.129  0.400  0.675];   % steel blue  — flowrate
clrDP  = [0.698  0.094  0.169];   % crimson     — pressure

if flag_cP
    hydraulicColor = clrQ;
else
    hydraulicColor = clrDP;
end

%% =========================================================
%  LINE STYLES — one per replicate/experiment
%% =========================================================
lineStyleOrder = {'-', '--', ':', '-.'};
repLineStyle = @(i) lineStyleOrder{mod(i-1, numel(lineStyleOrder)) + 1};

%% =========================================================
%  FIGURE SETUP — 8" × 2.5" PNAS single-column
%% =========================================================
figW_in = 8;
figH_in = 2.5;

fig = figure('Color', 'w', ...
    'Units',    'inches', ...
    'Position', [1  1  figW_in  figH_in]);

ax = axes(fig);
hold(ax, 'on');

%% =========================================================
%  LEFT Y-AXIS — hydraulic parameter (all replicates overlaid)
%% =========================================================
yyaxis(ax, hydraulicAxis);

hLines = gobjects(nRep, 1);
maxHydraulic = 0;
for i = 1:nRep
    r = reps{i};
    if flag_cP
        hLines(i) = plot(ax, r.hours_q, r.q_smooth, repLineStyle(i), ...
            'Color', hydraulicColor, 'LineWidth', 1.5, 'DisplayName', r.expLabel);
        maxHydraulic = max(maxHydraulic, max(r.q_smooth, [], 'omitnan'));
    else
        hLines(i) = plot(ax, r.hours_p, r.dp_smooth, repLineStyle(i), ...
            'Color', hydraulicColor, 'LineWidth', 1.5, 'DisplayName', r.expLabel);
        maxHydraulic = max(maxHydraulic, max(r.dp_smooth, [], 'omitnan'));
    end
end

if flag_cP
    ylabel(ax, 'Flowrate (\muL min^{-1})', 'Color', hydraulicColor, 'FontSize', 10, 'FontWeight', 'bold');
    ylim(ax, [-0.5  max(12.5, maxHydraulic*1.15 + eps)]);
    hZ = yline(ax, 0, '--', 'Color', hydraulicColor, 'LineWidth', 0.9, 'Alpha', 0.5);
    hZ.Annotation.LegendInformation.IconDisplayStyle = 'off';
else
    ylabel(ax, '\DeltaP (mbar)', 'Color', hydraulicColor, 'FontSize', 10, 'FontWeight', 'bold');
    ylim(ax, [0  maxHydraulic*1.15 + eps]);
end
ax.YColor = hydraulicColor;

%% =========================================================
%  RIGHT Y-AXIS — Biomass (olive) and DO (teal), per replicate
%  Replicate identity encoded by line style, same as the left axis.
%  ±1σ band shown only for DO, and only for the reference replicate
%  (refReplicateIdx) — overlapping bands from multiple replicates
%  aren't distinguishable, and biomass occupation has no shading here.
%% =========================================================
yyaxis(ax, bioDOAxis);

rRef = reps{refReplicateIdx};

% DO band (reference replicate only)
if rRef.hasDO
    xFill_DO = [rRef.hours_img_DO(:); flipud(rRef.hours_img_DO(:))];
    yFill_DO = [rRef.DO_pct_plot(:) + rRef.DO_std_plot(:); ...
                flipud(rRef.DO_pct_plot(:) - rRef.DO_std_plot(:))];
    yFill_DO = max(yFill_DO, 0);
    hDOband = fill(ax, xFill_DO, yFill_DO, clrDO, ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none');
    hDOband.Annotation.LegendInformation.IconDisplayStyle = 'off';
end

for i = 1:nRep
    r = reps{i};
    if r.hasDO
        plot(ax, r.hours_img_DO, r.DO_pct_plot, repLineStyle(i), ...
            'Color', clrDO, 'LineWidth', 1.5);
    end
end

% Biomass drawn after DO so it stays on top
for i = 1:nRep
    r = reps{i};
    plot(ax, r.hours_img_bio, r.biomass_plot, repLineStyle(i), ...
        'Color', clrBio, 'LineWidth', 2);
end

ylim(ax, [0  100]);
ax.YTick      = 0:20:100;
ax.YTickLabel = arrayfun(@(v) sprintf('%d%%', v), 0:20:100, 'UniformOutput', false);
ax.YColor     = [0.25 0.25 0.25];
ylabel(ax, 'Biomass occ. (%) / DO (%)', 'FontSize', 10, 'FontWeight', 'bold');

%% =========================================================
%  X-AXIS
%% =========================================================
xMax_h = max(cellfun(@(r) r.xMax_h, reps));
xlim(ax, [0  xMax_h]);
xTicks = ax.XTick;
ax.XTick = xTicks(2:end-1);
xlabel(ax, 'Experiment time (h)', 'FontSize', 10, 'FontWeight', 'bold');

%% =========================================================
%  GRID + BOX
%% =========================================================
grid(ax, 'on');
box(ax, 'on');
ax.GridAlpha  = 0.15;
ax.LineWidth  = 0.8;
ax.FontSize   = 9;
ax.FontWeight = 'bold';

%% =========================================================
%  VERTICAL EVENT LINES
%% =========================================================
for ev = 1:length(eventTimes)
    h1 = xline(ax, eventTimes(ev), '--', ...
        'Color', eventColor, 'LineWidth', eventLW, 'Alpha', 0.75);
    h1.Annotation.LegendInformation.IconDisplayStyle = 'off';
end

%% =========================================================
%  LEGEND — replicate/experiment key (by line style)
%% =========================================================
% repLabels = cellfun(@(r) r.expLabel, reps, 'UniformOutput', false);
% lgd = legend(ax, hLines, repLabels, ...
%     'Location', 'northoutside', 'Orientation', 'horizontal', ...
%     'Box', 'off', 'FontSize', 8, 'TextColor', [0.25 0.25 0.25]);
% title(lgd, sprintf('line style identifies replicate/experiment | DO shaded band = %s (±1σ)', rRef.expLabel), ...
%     'FontWeight', 'normal', 'FontSize', 7);

%% =========================================================
%  EXPORT — 8" × 2.5", PDF vector + TIF 300 dpi
%% =========================================================
if ~exist(combinedOutDir, 'dir')
    mkdir(combinedOutDir);
end

fig.Units    = 'inches';
fig.Position = [1  1  figW_in  figH_in];

pdfOut = fullfile(combinedOutDir, 'timeseries_1panel_PNAS_replicates.pdf');
tifOut = fullfile(combinedOutDir, 'timeseries_1panel_PNAS_replicates.tif');

exportgraphics(fig, pdfOut, 'ContentType', 'vector');
exportgraphics(fig, tifOut, 'Resolution', 300);

fprintf('Saved combined replicate plot:\n  %s\n  %s\n', pdfOut, tifOut);