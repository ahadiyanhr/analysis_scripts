% plot_1panel_for_manuscripts.m
%
% Single-panel time series for the PNAS manuscript.
%   Left axis    : flowrate (cP) or dP (cQ), colored by hydraulic condition
%   Right axis 1 : total biomass (%)
%   Right axis 2 : bulk DO (mg/L), offset to the right of axis 1
%
% t = 0 is the early peak in bulk permeability (k ~ Q/dP); data before the
% peak are dropped. Also saves *_manuscript_data.mat for the replicate script.
% Export: 7 x 2.5 in (PNAS two-column, 17.8 cm), PDF (vector) + TIF (600 dpi).

clear; clc; close all;

%% ---- Settings ----------------------------------------------------------

% event markers above the panel
eventTimes  = [5.5,19.6,36.7,69.8,112.1];          % <-- edit: e.g. [24, 48, 72]
eventLabels = {'a', 'b','c','d', 'e'};          % <-- edit: e.g. {'PSS onset', 'Sloughing', 'Re-clogging'}
eventColor  = [1 0 0];
eventTickLW  = 1.5;      % pt
eventTickLen = 0.05;    % fraction of panel height
USER_TIMES_IN_EXPERIMENT_TIME = false;   % true: eventTimes are in raw experiment time

% truncation, in plotted (shifted) hours; inf = keep everything
t_DO_end_h  = 121.8;
t_bio_end_h = 121.8;

% DO axis range (mg/L)
DO_MAX_MGPL = 8;

% time origin at peak permeability (same rule as perm_calc_new.m)
SHIFT_TO_PEAK   = true;
K_SMOOTH_WINDOW = 5000;   % samples
DP_MIN_MBAR     = 0.1;    % dP below this -> k undefined
PEAK_SEARCH_H   = 12;     % search the peak only in the first 12 h

% cQ level can't be read from the file names: 'high' (rose) or 'low' (gold)
CQ_LEVEL = 'high';

LEG_LOCATION = 'northeast';
PANEL_NOTE     = 'cP experiment starts at 12 \muL min^{-1}';
NOTE_LOCATION  = [0.5 0.85];   % normalized [x y] inside the panel, top-left

% line widths
lwHyd = 2;
lwBio = 2;
lwDO  = 1.2;

% colors (Paul Tol high-contrast for hydraulics, neutrals for biology)
darkBlue = [0.0000 0.2667 0.5333];   % cP flowrate
rose     = [0.7333 0.3333 0.4000];   % cQ high dP
gold     = [0.8667 0.6667 0.2000];   % cQ low dP
clrBio   = [0 0 0];
clrDO    = [0 0 0];
bandAlpha = 0.15;

% figure layout (inches)
figW_in   = 8;
figH_in   = 2.8;
marginL   = 0.60;
marginR   = 1.15;   % room for two right axes and their labels
marginB   = 0.45;
marginT   = 0.30;   % room for event labels
doOffset  = 0.65;   % gap between the biomass axis and the DO axis

%% ---- Paths -------------------------------------------------------------

projectPath = fileparts(pwd);   % script lives one level below the project
pqPath      = fullfile(projectPath, 'processed_data', 'pq_cleaned_data');
logsPath    = fullfile(projectPath, 'logs');
bioDOPath   = fullfile(projectPath, 'processed_data', 'biomass_occupation_bulkDO');
plotPath    = fullfile(projectPath, 'processed_data', 'plots');
repDataPath = fullfile(plotPath, 'replicate_data');
sensorPath  = fullfile(projectPath, 'raw_data', 'sensor_readings');

if ~exist(repDataPath, 'dir')
    mkdir(repDataPath);
end
[~, expLabel] = fileparts(projectPath);

%% ---- Experiment type (same naming rule as pq_cleaning.m) ----------------

exp_type = '';
files = dir(fullfile(sensorPath, '*.txt'));
for i = 1:numel(files)
    if contains(files(i).name, '__reader_pressures')
        exp_type = 'ConstantFlowRate';
    elseif contains(files(i).name, '__reader_flowrate')
        exp_type = 'ConstantPressure';
    end
end
if isempty(exp_type)
    error('Could not detect experiment type from %s (expected __reader_pressures or __reader_flowrate).', sensorPath);
end
flag_cP = strcmp(exp_type, 'ConstantPressure');
fprintf('Experiment type: %s\n', exp_type);

%% ---- Load data -----------------------------------------------------------

TTq = readtable(fullfile(pqPath, 'cleaned_flowrate.csv'), 'TextType', 'string');
t_q      = datetime(TTq.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
q_smooth = TTq.q_smooth(:);

TTp = readtable(fullfile(pqPath, 'cleaned_pressures.csv'), 'TextType', 'string');
t_p       = datetime(TTp.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
dp_smooth = TTp.dP_smooth(:);

imgLog = readtable(fullfile(logsPath, 'imaging_timestamp.xlsx'), 'TextType', 'string');
t_img  = datetime(imgLog.Datetime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');

matFiles = dir(fullfile(bioDOPath, '*_main_results.mat'));
if isempty(matFiles)
    error('No *_main_results.mat file in %s', bioDOPath);
end
S = load(fullfile(bioDOPath, matFiles(1).name));

biomass     = S.data.biomass_occupation(:);
biomass_std = S.data.biomass_occupation_std(:);

hasDO = isfield(S.data, 'bulk_do') && isfield(S.data, 'bulk_do_std') ...
        && any(~isnan(S.data.bulk_do));
if hasDO
    DO     = S.data.bulk_do(:);       % mg/L
    DO_std = S.data.bulk_do_std(:);
end

if numel(biomass) ~= numel(t_img) || (hasDO && numel(DO) ~= numel(t_img))
    error('Biomass/DO length does not match the imaging timestamps.');
end

%% ---- Time axis ----------------------------------------------------------

t_q = t_q(:);  t_p = t_p(:);  t_img = t_img(:);
t0 = min([t_q; t_p; t_img]);
h_q   = hours(t_q   - t0);
h_p   = hours(t_p   - t0);
h_img = hours(t_img - t0);

t_peak_h = 0;
if SHIFT_TO_PEAK
    % k ~ Q/dP (mu, L, A constant), so the peak needs no geometry
    [t_k, iq, ip] = intersect(t_q, t_p);
    q_k  = movmean(q_smooth(iq),  K_SMOOTH_WINDOW);
    dp_k = movmean(dp_smooth(ip), K_SMOOTH_WINDOW);
    k    = q_k ./ dp_k;
    k(dp_k < DP_MIN_MBAR | k <= 0) = NaN;

    h_k = hours(t_k - t0);
    k(h_k > h_k(1) + PEAK_SEARCH_H) = NaN;

    [kMax, iPeak] = max(k, [], 'omitnan');
    if isnan(kMax)
        error('No measurable k (dP > %.2f mbar) in the first %.1f h.', DP_MIN_MBAR, PEAK_SEARCH_H);
    end
    t_peak_h = h_k(iPeak);
    fprintf('Peak k at %.2f h (%s) -> t = 0\n', t_peak_h, string(t_k(iPeak)));

    h_q   = h_q   - t_peak_h;
    h_p   = h_p   - t_peak_h;
    h_img = h_img - t_peak_h;

    keep = h_q >= 0;   h_q = h_q(keep);   q_smooth  = q_smooth(keep);
    keep = h_p >= 0;   h_p = h_p(keep);   dp_smooth = dp_smooth(keep);

    keep = h_img >= 0;
    fprintf('Dropped %d images before the peak\n', sum(~keep));
    h_img       = h_img(keep);
    biomass     = biomass(keep);
    biomass_std = biomass_std(keep);
    if hasDO
        DO     = DO(keep);
        DO_std = DO_std(keep);
    end

    if USER_TIMES_IN_EXPERIMENT_TIME
        eventTimes = eventTimes - t_peak_h;
    end
    early = eventTimes < 0;
    if any(early)
        fprintf('Events before the peak, not drawn: %s\n', strjoin(eventLabels(early), ', '));
    end
    eventTimes  = eventTimes(~early);
    eventLabels = eventLabels(~early);
end

% truncate biology
inBio      = h_img <= t_bio_end_h;
h_bio      = h_img(inBio);
bioPlot    = biomass(inBio);
bioStdPlot = biomass_std(inBio);

if hasDO
    inDO     = h_img <= t_DO_end_h;
    h_DO     = h_img(inDO);
    DOPlot   = DO(inDO);
    DOStdPlot = DO_std(inDO);
end

xMax_h = max([h_q; h_p; h_img]);

%% ---- Save data for the replicate figure ----------------------------------

repData = struct();
repData.expLabel      = expLabel;
repData.exp_type      = exp_type;
repData.flag_cP       = flag_cP;
repData.DO_MAX_MGPL   = DO_MAX_MGPL;
repData.t_peak_h      = t_peak_h;
repData.shiftedToPeak = SHIFT_TO_PEAK;

repData.hours_q   = h_q;
repData.q_smooth  = q_smooth;
repData.hours_p   = h_p;
repData.dp_smooth = dp_smooth;

repData.hours_img_bio    = h_bio;
repData.biomass_plot     = bioPlot;
repData.biomass_std_plot = bioStdPlot;

repData.hasDO = hasDO;
if hasDO
    repData.hours_img_DO = h_DO;
    repData.DO_mgpl_plot = DOPlot;                         % new: mg/L
    repData.DO_mgpl_std  = DOStdPlot;
    repData.DO_pct_plot  = DOPlot    / DO_MAX_MGPL * 100;  % kept for the replicate script
    repData.DO_std_plot  = DOStdPlot / DO_MAX_MGPL * 100;
end

repData.eventTimes  = eventTimes;
repData.eventLabels = eventLabels;
repData.xMax_h      = xMax_h;

repFile = fullfile(repDataPath, sprintf('%s_manuscript_data.mat', expLabel));
save(repFile, 'repData');
fprintf('Saved %s\n', repFile);

%% ---- Figure and axes ---------------------------------------------------

if flag_cP
    hydColor = darkBlue;
    h_hyd = h_q;   y_hyd = q_smooth;
    hydLabel  = 'Flowrate (\muL min^{-1})';
    hydLegend = 'Flowrate (left)';
elseif strcmpi(CQ_LEVEL, 'low')
    hydColor = gold;
    h_hyd = h_p;   y_hyd = dp_smooth;
    hydLabel  = '\DeltaP (mbar)';
    hydLegend = '\DeltaP (left)';
else
    hydColor = rose;
    h_hyd = h_p;   y_hyd = dp_smooth;
    hydLabel  = '\DeltaP (mbar)';
    hydLegend = '\DeltaP (left)';
end

fig = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 figW_in figH_in]);

% fixed panel position so the offset DO axis lines up exactly
axW = figW_in - marginL - marginR;
axH = figH_in - marginB - marginT;
pos = [marginL/figW_in, marginB/figH_in, axW/figW_in, axH/figH_in];

% FIX: three separate axes instead of yyaxis (yyaxis allows only two).
% axHyd : left y-axis + x-axis + grid
% axBio : right y-axis on the panel edge
% axDO  : right y-axis pushed out by doOffset. The axes is widened by the
%         offset and its XLim stretched by the same ratio, so its data still
%         line up with the other two axes.
axHyd = axes(fig, 'Units', 'normalized', 'Position', pos);
axBio = axes(fig, 'Units', 'normalized', 'Position', pos);

stretch = (axW + doOffset) / axW;
axDO  = axes(fig, 'Units', 'normalized', ...
    'Position', [pos(1), pos(2), pos(3)*stretch, pos(4)]);

allAx = [axHyd axBio axDO];
set(allAx, 'PositionConstraint', 'innerposition', ...
    'FontName', 'Arial', 'FontSize', 9, 'FontWeight', 'bold', ...
    'LineWidth', 0.8, 'TickDir', 'in', 'NextPlot', 'add');

%% ---- Left axis: hydraulics ----------------------------------------------

plot(axHyd, h_hyd, y_hyd, '-', 'Color', hydColor, 'LineWidth', lwHyd);
axHyd.YColor = hydColor;
ylabel(axHyd, hydLabel, 'Color', hydColor, 'FontSize', 10);

if flag_cP
    ylim(axHyd, [-0.5 12.5]);
    axHyd.YTick = 0:2:12;
    yline(axHyd, 0, '--', 'Color', hydColor, 'LineWidth', 0.9, 'Alpha', 0.5);
else
    ylim(axHyd, [0, max(dp_smooth)*1.15 + eps]);
end

xlim(axHyd, [0 xMax_h]);
xt = axHyd.XTick;
axHyd.XTick = xt(xt > 0 & xt < xMax_h);   % no labels on the limits
xlabel(axHyd, 'Experiment time (h)', 'FontSize', 10);
grid(axHyd, 'on');
axHyd.GridAlpha = 0.15;
box(axHyd, 'on');

%% ---- Right axis 1: total biomass (%) ------------------------------------

plot(axBio, h_bio, bioPlot, ':', 'Color', clrBio, 'LineWidth', lwBio);
set(axBio, 'Color', 'none', 'YAxisLocation', 'right', 'XColor', 'none', ...
    'YColor', clrBio, 'XLim', [0 xMax_h], 'YLim', [0 100], 'YTick', 0:20:100);
ylabel(axBio, 'Total biomass (%)', 'FontSize', 9);
% pin the label a fixed distance from the right spine
bioLabelGap = 0.23;                          % inches from spine to label; tune this
axBio.YLabel.Units    = 'normalized';
axBio.YLabel.Position = [1 + bioLabelGap/axW, 0.5, 0];
axBio.YLabel.VerticalAlignment = 'top';      % anchor the label's near edge at that x

%% ---- Right axis 2: bulk DO (mg/L) ----------------------------------------

% FIX: DO now on its own axis in mg/L (0 to DO_MAX_MGPL), no % rescaling
if hasDO
    xBand = [h_DO; flipud(h_DO)];
    yBand = [DOPlot + DOStdPlot; flipud(max(DOPlot - DOStdPlot, 0))];
    fill(axDO, xBand, yBand, clrDO, 'FaceAlpha', bandAlpha, 'EdgeColor', 'none');
    plot(axDO, h_DO, DOPlot, '--', 'Color', clrDO, 'LineWidth', lwDO);

    set(axDO, 'Color', 'none', 'YAxisLocation', 'right', 'XColor', 'none', ...
        'YColor', clrDO, 'XLim', [0 xMax_h*stretch], ...
        'YLim', [0 DO_MAX_MGPL], 'YTick', 0:2:DO_MAX_MGPL);
    ylabel(axDO, 'Bulk Dissolved O2 (mg L^{-1})', 'FontSize', 9);
else
    axDO.Visible = 'off';
end

%% ---- Legend ---------------------------------------------------------------

% legend() only takes lines from one axes, so draw invisible stand-ins on axHyd
legLines = plot(axHyd, NaN, NaN, '-', 'Color', hydColor, 'LineWidth', lwHyd);
legText  = {hydLegend};
legLines(end+1) = plot(axHyd, NaN, NaN, ':', 'Color', clrBio, 'LineWidth', lwBio);
legText{end+1}  = 'Total biomass (right)';
if hasDO
    legLines(end+1) = plot(axHyd, NaN, NaN, '--', 'Color', clrDO, 'LineWidth', lwDO);
    legText{end+1}  = 'Bulk DO (right)';
end

lgd = legend(axHyd, legLines, legText, 'Location', LEG_LOCATION, ...
    'Orientation', 'horizontal', 'Box', 'off', 'FontName', 'Arial', ...
    'FontSize', 8, 'FontWeight', 'normal', 'AutoUpdate', 'off');
lgd.ItemTokenSize = [18 8];

%% ---- Event markers above the panel -------------------------------------

if ~isempty(eventTimes)
    axEvt = axes(fig, 'Units', 'normalized', 'Position', pos, ...
        'Color', 'none', 'XLim', [0 xMax_h], 'YLim', [0 1], ...
        'XColor', 'none', 'YColor', 'none', 'HitTest', 'off', ...
        'HandleVisibility', 'off', 'NextPlot', 'add');

    for i = 1:numel(eventTimes)
        line(axEvt, eventTimes(i)*[1 1], [1-eventTickLen 1], ...
            'Color', eventColor, 'LineWidth', eventTickLW, 'Clipping', 'off');
        text(axEvt, eventTimes(i), 1.01, eventLabels{i}, ...
            'Color', eventColor, 'FontName', 'Arial', 'FontSize', 11, ...
            'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'Interpreter', 'none', 'Clipping', 'off');
    end
end

%% ---- Panel label ----------------------------------------------------------

% FIX: text label in a corner of the panel
if ~isempty(PANEL_NOTE)
    text(axHyd, NOTE_LOCATION(1), NOTE_LOCATION(2), PANEL_NOTE, ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'FontName', 'Arial', 'FontSize', 10, 'FontWeight', 'bold', ...
        'Color', hydColor, ...               % matches the condition color
        'BackgroundColor', 'w', 'Margin', 1, ...   % stays readable over the grid
        'Interpreter', 'tex');
end

%% ---- Export ---------------------------------------------------------------

pdfOut = fullfile(plotPath, 'timeseries_1panel_PNAS.pdf');
tifOut = fullfile(plotPath, 'timeseries_1panel_PNAS.tif');
exportgraphics(fig, pdfOut, 'ContentType', 'vector');
exportgraphics(fig, tifOut, 'Resolution', 600);
fprintf('Saved:\n  %s\n  %s\n', pdfOut, tifOut);