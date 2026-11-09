clear; clc;
%% hydraulics_at_images.m
% Reports ΔP and flowrate at chosen images in the Command Window.
%
% For each image number you enter, the script finds the sensor sample
% closest to the image timestamp and averages N_AVG samples before and
% N_AVG samples after it (window = 2*N_AVG + 1 samples; 1 Hz → ±15 s).
%
% Image numbering follows plot_for_manuscripts_3panels.m:
%   image #00 = row 1 of imaging_timestamp.xlsx, #01 = row 2, ...
%
% Inputs (same folders as the plotting scripts; run from the scripts folder):
%   processed_data\pq_cleaned_data\cleaned_flowrate.csv   (offset removed)
%   processed_data\pq_cleaned_data\cleaned_pressures.csv  (offset removed)
%   logs\imaging_timestamp.xlsx
%
% The average uses the UNSMOOTHED columns (q, dP); the ±N_AVG window
% does the smoothing, so the 20-sample smoothing from pq_cleaning.m is
% not applied twice.

%% -------------------------------------------------
% USER SETTINGS
%% -------------------------------------------------
IMAGE_NUMBERS = [];   % e.g. [0 10 25 40]; leave [] to be asked in the terminal
N_AVG         = 15;   % samples before AND after the image
MAX_GAP_S     = 5;    % warn if the closest sensor sample is farther than this [s]

%% -------------------------------------------------
% Paths (same layout as the plotting scripts)
%% -------------------------------------------------
mainPath = pwd;
cd(mainPath); cd('../');
projectPath = pwd;

cd(projectPath); cd('processed_data\pq_cleaned_data\');
pdCleanedPath = pwd;

cd(projectPath); cd('logs\');
logsPath = pwd;

cd(mainPath);   % return to the scripts folder

%% -------------------------------------------------
% Load sensor data
%% -------------------------------------------------
TTq = readtable(fullfile(pdCleanedPath, 'cleaned_flowrate.csv'), ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
TTq.datetime = datetime(TTq.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');

TTp = readtable(fullfile(pdCleanedPath, 'cleaned_pressures.csv'), ...
    'TextType', 'string', 'VariableNamingRule', 'preserve');
TTp.datetime = datetime(TTp.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');

t_q = TTq.datetime(:);   q  = TTq.q(:);     % µL/min, offset removed
t_p = TTp.datetime(:);   dP = TTp.dP(:);    % mbar,   offset removed

%% -------------------------------------------------
% Load imaging timestamps
%% -------------------------------------------------
imagingTime = readtable(fullfile(logsPath, 'imaging_timestamp.xlsx'), 'TextType', 'string');
t_img = datetime(imagingTime.Datetime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
t_img = t_img(:);
nImg  = numel(t_img);

if ~issorted(t_img)
    bad = find(diff(t_img) <= 0, 1) + 1;
    warning(['imaging_timestamp.xlsx is out of order at row %d ' ...
             '(image #%02d). Check those timestamps.'], bad, bad - 1);
end

% Experiment time origin (same t0 as the plotting scripts)
t0 = min([t_q; t_p; t_img]);

%% -------------------------------------------------
% Ask for image numbers
%% -------------------------------------------------
if isempty(IMAGE_NUMBERS)
    fprintf('Images available: #00 to #%02d\n', nImg - 1);
    IMAGE_NUMBERS = input('Enter image numbers, e.g. [0 10 25 40]: ');
end
IMAGE_NUMBERS = IMAGE_NUMBERS(:)';

bad = IMAGE_NUMBERS ~= round(IMAGE_NUMBERS) | IMAGE_NUMBERS < 0 | IMAGE_NUMBERS > nImg - 1;
if any(bad)
    error('Image numbers must be integers from 0 to %d. Invalid: %s', ...
        nImg - 1, mat2str(IMAGE_NUMBERS(bad)));
end

%% -------------------------------------------------
% Average ±N_AVG samples around each image
%% -------------------------------------------------
fprintf('\nHydraulic data at images (mean ± std of %d samples before and after)\n', N_AVG);
fprintf('%s\n', repmat('-', 1, 104));
fprintf('%-7s %-21s %9s   %-22s %-22s %5s\n', ...
    'Image', 'Timestamp', 'Time (h)', 'ΔP (mbar)', 'Flowrate (µL/min)', 'n');
fprintf('%s\n', repmat('-', 1, 104));

for imgNo = IMAGE_NUMBERS
    ti = t_img(imgNo + 1);   % #00 → row 1

    [dP_m, dP_s, n_p, gap_p] = window_stats(t_p, dP, ti, N_AVG);
    [q_m,  q_s,  n_q, gap_q] = window_stats(t_q, q,  ti, N_AVG);

    fprintf('#%-6s %-21s %9.2f   %8.3f ± %-11.3f %8.3f ± %-11.3f %5d\n', ...
        sprintf('%02d', imgNo), string(ti, 'yyyy-MM-dd HH:mm:ss'), ...
        hours(ti - t0), dP_m, dP_s, q_m, q_s, min(n_p, n_q));

    % Flag images that fall in a logging gap or near the start/end of a log
    if gap_p > MAX_GAP_S || gap_q > MAX_GAP_S
        fprintf('        ⚠ closest sensor sample is %.0f s (ΔP) / %.0f s (Q) from the image\n', ...
            gap_p, gap_q);
    end
    if n_p < 2*N_AVG + 1 || n_q < 2*N_AVG + 1
        fprintf('        ⚠ window cut by the start/end of the log (n = %d ΔP, %d Q)\n', n_p, n_q);
    end
end
fprintf('%s\n', repmat('-', 1, 104));
fprintf('Time (h) = experiment time from the earliest timestamp (t0 = %s)\n', ...
    string(t0, 'yyyy-MM-dd HH:mm:ss'));

%% -------------------------------------------------
% Helper: mean and std over ±nAvg samples around time ti
%% -------------------------------------------------
function [m, s, n, gap_s] = window_stats(t, x, ti, nAvg)
    [gap, iC] = min(abs(t - ti));          % closest sample to the image
    gap_s = seconds(gap);
    i1 = max(1, iC - nAvg);
    i2 = min(numel(x), iC + nAvg);
    w  = x(i1:i2);
    w  = w(~isnan(w));
    n  = numel(w);
    m  = mean(w);
    s  = std(w);
end