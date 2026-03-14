clc
clear

%% --------- Setting ---------
window = 20; % Smooth Time Series window

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

% Sensor reading path
cd(projectPath);
cd('raw_data\sensor_readings\');
sensorReadingPath = pwd;

% Logs path
cd(projectPath);
cd('logs\');
logsPath = pwd;

%% --------- Auto-detect Experiment Type and Files ---------
files = dir(fullfile(sensorReadingPath, '*.txt'));

for i = 1:length(files)
    fname = files(i).name;
    if contains(fname, '__ob1_flowrate')
        flowrate_file = fname;
    elseif contains(fname, '__reader_pressures')
        pressure_file = fname;
        exp_type = 'ConstantFlowRate';
    elseif contains(fname, '__ob1_pressures')
        pressure_file = fname;
    elseif contains(fname, '__reader_flowrate')
        flowrate_file = fname;
        exp_type = 'ConstantPressure';
    end
end

if ~exist('exp_type', 'var')
    error('Experiment type not recognized. Make sure files are named correctly.');
end

fprintf('Detected experiment type: %s\n', exp_type);

%% --- Sensor Offset ---
calibFile = dir(fullfile(logsPath,'sensor_offset.xlsx'));
T = readtable(fullfile(logsPath, calibFile.name));
flowrate_offset = T.flowrate(1);
pressure_diff_offset   = T.pressure_diff(1);

%% --------- Read Pressure Data ---------
p_raw = readtable(fullfile(sensorReadingPath,pressure_file), 'Delimiter', '\t', 'ReadVariableNames', false);
time_str_p = p_raw{:,1};
time_sec_p = p_raw{:,2};

switch exp_type
    case 'ConstantFlowRate'
        p1 = p_raw{:,4};
        p2 = p_raw{:,6};
    case 'ConstantPressure'
        p1 = p_raw{:,8};
        p2 = p_raw{:,10};
end
deltaP = p1 - p2 - pressure_diff_offset;

%% --------- Read Flowrate Data ---------
q_raw = readtable(fullfile(sensorReadingPath,flowrate_file), 'Delimiter', '\t', 'ReadVariableNames', false);
time_str_q = q_raw{:,1};
time_sec_q = q_raw{:,2};

switch exp_type
    case 'ConstantFlowRate'
        q = q_raw{:,8};
    case 'ConstantPressure'
        q = q_raw{:,4};
end

q = q - flowrate_offset;

%% --------- Find first index where increments ≈ 1 sec ---------
tol = 0.15; % tolerance for detecting 1 sec interval

dt_p = diff(time_sec_p);
start_idx_p = find(abs(dt_p - 1) <= tol, 1, 'first');
if isempty(start_idx_p)
    error('No 1 sec interval found in pressure file.');
end
start_idx_p = start_idx_p + 1; % move to row after the change

dt_q = diff(time_sec_q);
start_idx_q = find(abs(dt_q - 1) <= tol, 1, 'first');
if isempty(start_idx_q)
    error('No 1 sec interval found in flowrate file.');
end
start_idx_q = start_idx_q + 1;

% Pick later start point to ensure both are aligned from 1 sec logging
start_idx = max(start_idx_p, start_idx_q);

%% --------- Trim data to start at proper point ---------
time_sec_p = time_sec_p(start_idx:end);
p1 = p1(start_idx:end);
p2 = p2(start_idx:end);
deltaP = deltaP(start_idx:end);
time_str_p = time_str_p(start_idx:end);

time_sec_q = time_sec_q(start_idx:end);
q = q(start_idx:end);
time_str_q = time_str_q(start_idx:end);

%% --------- Normalize time increments ---------
dt_p = diff(time_sec_p);
time_sec_p_corrected = [0; cumsum(round(dt_p))];

dt_q = diff(time_sec_q);
time_sec_q_corrected = [0; cumsum(round(dt_q))];

%% --------- Build datetime vectors ---------
start_time_p = datetime(time_str_p(1), 'InputFormat', 'dd/MM/yyyy_HH:mm:ss');
time_p_corrected = start_time_p + seconds(time_sec_p_corrected);

start_time_q = datetime(time_str_q(1), 'InputFormat', 'dd/MM/yyyy_HH:mm:ss');
time_q_corrected = start_time_q + seconds(time_sec_q_corrected);

%% --------- Align datasets on exact matching time points ---------
[datetime, idx_p, idx_q] = intersect(time_p_corrected, time_q_corrected);

p1_aligned     = p1(idx_p);
p2_aligned     = p2(idx_p);
deltaP_aligned = deltaP(idx_p);
q_aligned      = q(idx_q);

%% --------- Smooth Time Series ---------
deltaP_smooth = movmean(deltaP_aligned, window);
q_smooth      = movmean(q_aligned, window);

%% --------- Create Timetables ---------
TT_p = timetable(datetime, p1_aligned, p2_aligned, deltaP_aligned, deltaP_smooth);
TT_q = timetable(datetime, q_aligned, q_smooth);

TT_p.Properties.VariableNames = {'p1','p2','dP','dP_smooth'};
TT_q.Properties.VariableNames = {'q','q_smooth'};

fprintf('✅ P&Q data are aligned!\nStart: %s\nEnd: %s\nLength: %d rows\n', ...
    datestr(datetime(1)), datestr(datetime(end)), numel(datetime));

%% --------- Save Cleaned Data ---------
writetimetable(TT_p, fullfile(pdCleanedPath,'cleaned_pressures.csv'));
writetimetable(TT_q, fullfile(pdCleanedPath,'cleaned_flowrate.csv'));
