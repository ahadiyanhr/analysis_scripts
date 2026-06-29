clc;
clear;
close all;

%% --------- Setting ---------
window = 20; % Smooth Time Series window

%% --- WINDOW CONFIGURATION ---
hours_to_analyze = 80;
hours_from_end_to_stop = 24;       % <--- SET THIS: How many hours from the very end to stop (t_end offset)

%% -------- Setup Paths --------
mainPath = pwd;
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
        exp_type = 'ConstantFlowRate'; % This means cQ regime -> free variable is deltaP
    elseif contains(fname, '__ob1_pressures')
        pressure_file = fname;
    elseif contains(fname, '__reader_flowrate')
        flowrate_file = fname;
        exp_type = 'ConstantPressure'; % This means cP regime -> free variable is flowrate
    end
end

if ~exist('exp_type', 'var')
    error('Experiment type not recognized. Make sure files are named correctly.');
end

fprintf('Detected experiment type: %s\n', exp_type);

%% --- Sensor Offset ---
calibFile = dir(fullfile(logsPath,'sensor_offset.xlsx'));
T_table = readtable(fullfile(logsPath, calibFile.name));
flowrate_offset = T_table.flowrate(1);
pressure_diff_offset = T_table.pressure_diff(1);

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
start_idx_p = start_idx_p + 1;

dt_q = diff(time_sec_q);
start_idx_q = find(abs(dt_q - 1) <= tol, 1, 'first');
if isempty(start_idx_q)
    error('No 1 sec interval found in flowrate file.');
end
start_idx_q = start_idx_q + 1;

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
[time_aligned, idx_p, idx_q] = intersect(time_p_corrected, time_q_corrected);
p1_aligned     = p1(idx_p);
p2_aligned     = p2(idx_p);
deltaP_aligned = deltaP(idx_p);
q_aligned      = q(idx_q);

%% --------- Smooth Time Series ---------
deltaP_smooth = movmean(deltaP_aligned, window);
q_smooth      = movmean(q_aligned, window);

%% --------- Create Timetables & Save Cleaned Data ---------
TT_p = timetable(time_aligned, p1_aligned, p2_aligned, deltaP_aligned, deltaP_smooth);
TT_q = timetable(time_aligned, q_aligned, q_smooth);

TT_p.Properties.VariableNames = {'p1','p2','dP','dP_smooth'};
TT_q.Properties.VariableNames = {'q','q_smooth'};

fprintf('✅ P&Q data are aligned!\nStart: %s\nEnd: %s\nLength: %d rows\n', ...
    datestr(time_aligned(1)), datestr(time_aligned(end)), numel(time_aligned));

writetimetable(TT_p, fullfile(pdCleanedPath,'cleaned_pressures.csv'));
writetimetable(TT_q, fullfile(pdCleanedPath,'cleaned_flowrate.csv'));

%% =========================================================================
%% --------- PSS ASSESSMENT USING EXPERIMENTAL VARIABLE (CUSTOM WINDOW) ---
%% =========================================================================

% 1. Determine the free hydraulic variable based on experiment type
if strcmp(exp_type, 'ConstantPressure')
    V_free_full = q_smooth; 
    var_label = 'Flowrate Q (smoothed)';
else
    V_free_full = deltaP_smooth; 
    var_label = '\Delta P (smoothed)';
end

% Establish relative time vector in seconds
t_rel_full = seconds(time_aligned - time_aligned(1)); 
dt = 1; % Sampling interval is 1 second

% Convert hours to seconds
seconds_to_analyze = hours_to_analyze * 3600;
seconds_from_end_offset = hours_from_end_to_stop * 3600;

% Define your shifted end point (t_end)
t_final = t_rel_full(end) - seconds_from_end_offset;
t_start_window = t_final - seconds_to_analyze;

% Safety check: Ensure the window boundaries are valid for your dataset
if t_start_window < 0
    error('The requested window exceeds the total duration of the experiment. Reduce hours_to_analyze or hours_from_end_to_stop.');
end

% 2. Isolate the custom window of data
window_indices = (t_rel_full >= t_start_window) & (t_rel_full <= t_final);
t_rel = t_rel_full(window_indices) - t_start_window; % Re-zero time for the window segment
V_free = V_free_full(window_indices);
N_total = length(t_rel);

% 3. Evaluate the backward integral at the final step of this specific window
evaluation_time_idx = N_total;
t_eval = t_rel(evaluation_time_idx);

% Define varying window sizes T (restricted to the isolated window duration)
max_T = t_eval;
T_vec = dt:dt:max_T; 
V_bar = zeros(size(T_vec));

% 4. Solve the backward integral within this frame
for i = 1:length(T_vec)
    T = T_vec(i);
    
    % Find indices corresponding to the window [t_eval - T, t_eval]
    start_idx = round((t_eval - T) / dt) + 1;
    end_idx = evaluation_time_idx;
    
    % Extract the specific experimental segment
    V_segment = V_free(start_idx:end_idx);
    
    % Compute backward average
    V_bar(i) = (1 / T) * trapz(V_segment) * dt;
end

%% --------- Plotting Both Curves on the Same Figure ---------
figure('Color', 'w', 'Position', [100, 100, 850, 500]);
hold on;

% Plot 1: The real-world variable over the last 40 hours
plot(t_rel / 3600, V_free, 'Color', [0.7, 0.7, 0.7], 'LineWidth', 1.5, ...
    'DisplayName', ['Experimental ', var_label]);

% Plot 2: Backward Average vs Window Size T (converted to hours)
t_backward = t_eval - T_vec;
plot(t_backward / 3600, V_bar, 'r-', 'LineWidth', 2, ...
    'DisplayName', 'Backward Average');

% Formatting the plot (X-axis is now cleanly displayed in Hours)
grid on;
xlabel('Experiment Time (Hours)');
ylabel(var_label);
title(['PSS Assessment for ', exp_type, ' (Last ', num2str(hours_to_analyze), ' Hours of Exp)']);
legend('Location', 'best');
