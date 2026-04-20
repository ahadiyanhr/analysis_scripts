%% One combined plot:
% Left axis:
%   - q_smooth from cleaned_flowrate.csv (dark green)
%   - dP_smooth from cleaned_pressures.csv (red)
% Right axis:
%   - biomass occupation from MAT file (orange, line + circles)
%   - bulk DO from MAT file (blue, line + circles)
% X-axis:
%   - experiment time in hours, where earliest datetime across all data = 0

clear; clc; close all;

%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Clean data path
cd(projectPath);
cd('processed_data\pq_cleaned_data\');
pdCleanedPath = pwd;

% Logs path
cd(projectPath);
cd('logs\');
logsPath = pwd;

% Biomass and BulkDO path
cd(projectPath);
cd('processed_data\bioOccu_bulkDO\');
bioDOPath = pwd;

% Plots path
cd(projectPath);
cd('processed_data\plots\');
plotPath = pwd;

%% -------- File paths --------
flowrateFile = 'cleaned_flowrate.csv';
pressFile = 'cleaned_pressures.csv';
timeFile = 'imaging_timestamp.xlsx';
matFile  = 'biomass_images_01.mat';

%% -------- Read flowrate data --------
TTq = readtable(fullfile(pdCleanedPath,flowrateFile), 'TextType', 'string');
TTq.datetime = datetime(TTq.datetime, ...
    'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
t_q = TTq.datetime;
q_smooth = TTq.q_smooth;

%% -------- Read pressure data --------
TTp = readtable(fullfile(pdCleanedPath, pressFile), 'TextType', 'string');
TTp.datetime = datetime(TTp.datetime, ...
    'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
t_p = TTp.datetime;
dp_smooth = TTp.dP_smooth;   % column E in your file

%% -------- Read imaging timestamps --------
imagingTime = readtable(fullfile(logsPath, timeFile), 'TextType', 'string');
% Your Excel file has columns: Image#, Datetime
t_img = datetime(imagingTime.Datetime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');

%% -------- Read MAT file --------
S = load(fullfile(bioDOPath, matFile));

biomass_occ = S.data.biomass_occupation;
bulk_DO     = S.data.bulk_do;

% Make sure they are column vectors
biomass_occ = biomass_occ(:);
bulk_DO     = bulk_DO(:);
t_img       = t_img(:);

% Check lengths
if length(biomass_occ) ~= length(t_img)
    error('Length of biomass occupation does not match imaging timestamps.');
end
if length(bulk_DO) ~= length(t_img)
    error('Length of bulk DO does not match imaging timestamps.');
end

%% -------- Define experiment time zero --------
t0 = min([t_q; t_p; t_img]);

hours_q   = hours(t_q   - t0);
hours_p   = hours(t_p   - t0);
hours_img = hours(t_img - t0);

%% -------- Plot --------
figure('Color','w','Position',[100 80 1250 700]);

%% -------------------------------------------------
% OPTIONAL: crop to first 100 hours
%% -------------------------------------------------
% mask_q   = hours_q   <= 100;
% mask_p   = hours_p   <= 100;
% mask_img = hours_img <= 100;
% 
% hours_q_plot   = hours_q(mask_q);
% q_smooth_plot  = q_smooth(mask_q);
% 
% hours_p_plot   = hours_p(mask_p);
% dp_smooth_plot = dp_smooth(mask_p);
% 
% hours_img_plot   = hours_img(mask_img);
% biomass_occ_plot = biomass_occ(mask_img);
% bulk_DO_plot     = bulk_DO(mask_img);

%% -------------------------------------------------
% Make image labels: t00, t01, t02, ...
%% -------------------------------------------------
step = 10;
idx = 1:step:length(hours_img);
imgLabels = arrayfun(@(k) sprintf('#%02d',k-1), idx, 'UniformOutput', false);

%% -------------------------------------------------
% Layout
%% -------------------------------------------------
tl = tiledlayout(2,1,'TileSpacing','loose','Padding','compact');

%% =================================================
% TOP PLOT: Biomass occupation + Bulk DO
%% =================================================
axTop = nexttile(tl,1);

yyaxis(axTop,'left')

bio_norm = biomass_occ ./ max(biomass_occ, [], 'omitnan');
plot(axTop, hours_img, bio_norm, '-o', ...
    'Color', [1 0.5 0], ...
    'MarkerFaceColor', [1 0.5 0], ...
    'MarkerSize', 4, ...
    'LineWidth', 0.5);
ylabel(axTop,'Normalized biomass (bio / max)','Color',[1 0.5 0],'FontSize',12,'FontWeight','bold');
axTop.YColor = [1 0.5 0];

yyaxis(axTop,'right')
plot(axTop, hours_img, bulk_DO, '-o', ...
    'Color', [0 0.45 0.74], ...
    'MarkerFaceColor', [0 0.45 0.74], ...
    'MarkerSize', 4, ...
    'LineWidth', 0.5);
ylabel(axTop,'Bulk DO [mg/L]','Color',[0 0.45 0.74],'FontSize',12,'FontWeight','bold');
axTop.YColor = [0 0.45 0.74];

grid(axTop,'on');
box(axTop,'on');
axTop.XTickLabel = [];   % hide bottom x-labels on top subplot
axTop.XTick = [];

%% =================================================
% BOTTOM PLOT: Flowrate + Pressure
%% =================================================
axBot = nexttile(tl,2);

yyaxis(axBot,'left')
plot(axBot, hours_q, q_smooth, ...
    'Color', [0 0.35 0], ...
    'LineWidth', 2);
ylabel(axBot,'Flowrate [µL/min]','Color',[0 0.35 0],'FontSize',12,'FontWeight','bold');
axBot.YColor = [0 0.35 0];

yyaxis(axBot,'right')
plot(axBot, hours_p, dp_smooth, ...
    'Color', [1 0 0], ...
    'LineWidth', 0.5);
ylabel(axBot,'Pressure [mbar]','Color',[1 0 0],'FontSize',12,'FontWeight','bold');
axBot.YColor = [1 0 0];

xlabel(axBot,'Experiment time (hours)');
grid(axBot,'on');
box(axBot,'on');

%% -------------------------------------------------
% Link x axes and define x range
%% -------------------------------------------------
linkaxes([axTop axBot],'x');

xMin = 0;
xMax = max([hours_q(:); hours_p(:); hours_img(:)]);
xlim(axTop,[xMin xMax]);
xlim(axBot,[xMin xMax]);

%% -------------------------------------------------
% Add vertical lines at every imaging time
% Draw on BOTH axes so they visually continue through the figure
%% -------------------------------------------------
for i = idx
    xline(axTop, hours_img(i), ':', ...
        'Color',[0.6 0.6 0.6], 'LineWidth',2);

    xline(axBot, hours_img(i), ':', ...
        'Color',[0.6 0.6 0.6], 'LineWidth',2);
end

%% -------------------------------------------------
% Create a top x-axis for image numbers
%% -------------------------------------------------
axTopX = axes('Units','normalized', ...
    'Position', axTop.Position, ...
    'Color', 'none', ...
    'XAxisLocation', 'bottom', ...
    'YAxisLocation', 'right', ...
    'YColor', 'none', ...
    'XColor', 'k', ...
    'Box', 'off', ...
    'HitTest', 'off', ...
    'HandleVisibility', 'off');

axTopX.XTick = hours_img(idx);
axTopX.XTickLabel = imgLabels;
axTopX.TickLength = [0.004 0.004];
xlabel(axTopX,'Image number');

% Hide normal x-axis of the top plot
axTop.XTick = [];
axTop.XColor = 'none';

% Keep x-limits the same
linkaxes([axTop axTopX axBot],'x');

% Force exact initial alignment
axTopX.Position = axTop.Position;
axTopX.XLim = axTop.XLim;

% Listener: whenever axTop position changes, update overlay axis
posListener = addlistener(axTop, 'Position', 'PostSet', ...
    @(~,~) set(axTopX, 'Position', axTop.Position));

% Listener: whenever x-limits change, update overlay axis
xlimListener = addlistener(axTop, 'XLim', 'PostSet', ...
    @(~,~) set(axTopX, 'XLim', axTop.XLim));

% Store listeners so MATLAB does not delete them
setappdata(gcf, 'TopAxisPositionListener', posListener);
setappdata(gcf, 'TopAxisXLimListener', xlimListener);

%% -------------------------------------------------
% Keep bottom hours axis normal, top plot bottom x hidden
%% -------------------------------------------------
axTop.XRuler.Axle.Visible = 'off';

%% -------------------------------------------------
% Make sure the top image-number axis stays aligned if figure redraws
%% -------------------------------------------------
linkaxes([axTop axTopX axBot],'x');

fig = gcf;
fig.SizeChangedFcn = @(~,~) updateTopOverlay(axTop, axTopX);

updateTopOverlay(axTop, axTopX);   % run once
drawnow
updateTopOverlay(axTop, axTopX);   % run again after layout settles

function updateTopOverlay(axTop, axTopX)
    drawnow limitrate
    axTopX.Position = axTop.Position;
    axTopX.XLim = axTop.XLim;
end


%% -------------------------------------------------
% OPTIONAL: set independent y-limits
% Uncomment and adjust if needed
%% -------------------------------------------------
% yyaxis(axTop,'left');  ylim(axTop,[0 1]);     % biomass
% yyaxis(axTop,'right'); ylim(axTop,[0 10]);    % bulk DO
yyaxis(axBot,'left');  ylim(axBot,[-2 13]);    % flowrate
yyaxis(axBot,'right'); ylim(axBot,[2 10]);   % pressure

%% -------------------------------------------------
% OPTIONAL: cleaner legend
%% -------------------------------------------------
%legend(axTop, {'Biomass occupation','Bulk DO'}, 'Location','southeast','FontSize',10, FontWeight='bold');
%legend(axBot, {'Flowrate','Pressure'}, 'Location','northeast','FontSize',10, FontWeight='bold');


%% -------- Optional: save figure --------

%saveas(gcf, 'combined_experiment_plot.png');
exportgraphics(gcf, fullfile(plotPath,'combined_experiment_plot.tif'), 'Resolution', 300);
