%% =========================================================
% This script calibrates multiple optodes using modified Stern–Volmer fitting.
% Input files must be named results_opt*.csv and contain:
%   column C = mean intensity
%   column D = standard deviation
%   column F = O2 concentration
% with rows alternating Green / Red.
%
% Workflow:
%   1. Read all calibration CSV files
%   2. Compute R = Red/Green
%   3. Propagate uncertainty for R
%   4. Group replicate image pairs by O2 using weighted mean
%   5. Fit each optode independently with modified Stern–Volmer model
%   6. Perform a joint weighted fit with shared alpha and Ksv,
%      and separate Rhigh for each optode
%   7. Plot data, independent fits, and joint fits
%   8. Save summary results to calibration_summary.csv
%% =========================================================

clear; clc;

%% ---------------- USER INPUT ----------------
% Find all optode results CSV files in current folder
fileStruct = dir('opt*.csv');

if isempty(fileStruct)
    error('No files matching results_opt*.csv were found in the current folder.');
end

% Sort files alphabetically
[~, idxSort] = sort({fileStruct.name});
fileStruct = fileStruct(idxSort);

% Extract filenames and labels
files  = strings(numel(fileStruct),1);
labels = strings(numel(fileStruct),1);

for i = 1:numel(fileStruct)
    files(i) = string(fileStruct(i).name);

    % Remove extension for label
    [~, nameOnly, ~] = fileparts(fileStruct(i).name);
    labels(i) = string(nameOnly);
end

% Distinct colors (up to 8)
colors = [ ...
    0     0     1;      % Blue
    1     0     0;      % Red
    0     0.6   0;      % Green
    0     0     0;      % Black
    0.6   0     0.8;    % Purple
    1     0.5   0;      % Orange
    0     0.8   0.8;    % Cyan
    0.5   0     0       % Dark Red
];

if numel(files) > size(colors,1)
    error('You have %d files, but only %d colors are defined. Add more colors.', ...
        numel(files), size(colors,1));
end

%% ---------------- STORAGE ----------------
cal = struct();

%% =========================================================
% LOOP OVER FILES: read, compute ratio, propagate error, group replicates
%% =========================================================
for f = 1:numel(files)

    %% -------- READ CSV --------
    T = readtable(files(f));

    Mean  = T{:,3};   % column C
    SD    = T{:,4};   % column D
    C_all = T{:,6};   % column F (O2)

    % Remove invalid rows
    m = isfinite(Mean) & isfinite(SD) & isfinite(C_all);
    Mean = Mean(m);
    SD   = SD(m);
    C_all= C_all(m);

    % Ensure even number of rows (Green/Red pairs)
    if mod(numel(Mean),2) ~= 0
        Mean(end)  = [];
        SD(end)    = [];
        C_all(end) = [];
    end

    %% -------- BUILD REPLICATE RATIOS --------
    % Rows alternate Green, Red, Green, Red, ...
    gMean = Mean(1:2:end);
    gSD   = SD(1:2:end);
    rMean = Mean(2:2:end);
    rSD   = SD(2:2:end);
    C_rep = C_all(1:2:end);

    % Ratio
    R_rep = rMean ./ gMean;

    % Propagation of error for R = Red / Green
    Rsd_rep = abs(R_rep) .* sqrt( ...
        (rSD ./ rMean).^2 + ...
        (gSD ./ gMean).^2 );

    % Clean data
    ok = isfinite(R_rep) & isfinite(Rsd_rep) & Rsd_rep > 0 & ...
         isfinite(C_rep) & gMean > 0 & rMean > 0;
    R_rep   = R_rep(ok);
    Rsd_rep = Rsd_rep(ok);
    C_rep   = C_rep(ok);

    %% -------- GROUP BY O2 (WEIGHTED MEAN) --------
    C_unique = unique(C_rep);
    R_mean = nan(size(C_unique));
    R_sd   = nan(size(C_unique));

    for i = 1:numel(C_unique)
        idx = (C_rep == C_unique(i));             % this O2 level
        w   = 1 ./ (Rsd_rep(idx).^2);             % inverse variance weights
        R_mean(i) = sum(w .* R_rep(idx)) / sum(w);% weighted mean
        R_sd(i)   = sqrt(1 / sum(w));             % SE of weighted mean
    end

    % Sort by O2
    [C_unique, srt] = sort(C_unique);
    R_mean = R_mean(srt);
    R_sd   = R_sd(srt);

    % Force column vectors
    C_unique = C_unique(:);
    R_mean   = R_mean(:);
    R_sd     = R_sd(:);

    %% -------- FIT MODIFIED STERN–VOLMER INDEPENDENTLY --------
    % Model: R = R0 * [ alpha + (1-alpha)/(1+Ksv*C) ]
    % p = [alpha, Ksv, R0]
    model_ind = @(p,C) p(3) .* ( p(1) + (1-p(1)) ./ (1 + p(2).*C) );

    w_fit = 1 ./ (R_sd.^2);
    obj_ind = @(p) sum( w_fit .* (R_mean - model_ind(p,C_unique)).^2 );

    p0 = [0.1, 1e-3/max(mean(C_unique),eps), max(R_mean)];
    lb = [0, 0, 0];
    ub = [1, inf, inf];

    opts = optimoptions("fmincon","Display","off","Algorithm","interior-point");

    p_hat = fmincon(obj_ind,p0,[],[],[],[],lb,ub,[],opts);

    %% -------- CONFIDENCE BAND AT DATAPOINTS (INDIVIDUAL FIT) --------
    Cfit = C_unique;
    Rfit = model_ind(p_hat, Cfit);

    epsJ = 1e-6;
    npar = numel(p_hat);
    J = zeros(numel(Cfit), npar);

    for kpar = 1:npar
        dp = zeros(size(p_hat));
        dp(kpar) = epsJ * max(1, abs(p_hat(kpar)));

        Rp = model_ind(p_hat + dp, Cfit);
        Rm = model_ind(p_hat - dp, Cfit);
        J(:,kpar) = (Rp - Rm) / (2*dp(kpar));
    end

    W = diag(w_fit);
    res = R_mean - model_ind(p_hat, C_unique);
    dof = max(1, numel(C_unique) - npar);
    SSEw = sum(w_fit .* (res.^2));
    s2 = SSEw / dof;

    Cov_p = s2 * inv(J.' * W * J);

    varR = sum((J * Cov_p) .* J, 2);
    sigmaR = sqrt(max(varR, 0));

    Rlo = Rfit - 1.96*sigmaR;
    Rhi = Rfit + 1.96*sigmaR;

    %% -------- STORE RESULTS --------
    cal(f).file     = files(f);
    cal(f).label    = labels(f);
    cal(f).C        = C_unique;
    cal(f).R        = R_mean;
    cal(f).Rsd      = R_sd;
    cal(f).wfit     = w_fit;
    cal(f).params   = p_hat;

    cal(f).Cfit     = Cfit;
    cal(f).Rfit     = Rfit;
    cal(f).Rlo      = Rlo;
    cal(f).Rhi      = Rhi;

    fprintf('\nIndependent fit: %s\n', labels(f));
    fprintf('  alpha = %.6f\n', p_hat(1));
    fprintf('  Ksv   = %.6g\n', p_hat(2));
    fprintf('  R0    = %.6f\n', p_hat(3));
end

%% =========================================================
% STEP 2: JOINT WEIGHTED FIT
% Shared alpha, shared Ksv, separate Rhigh for each optode
% Rhigh = ratio at the highest O2 concentration for each optode
%% =========================================================

nOpt = numel(files);

% Stack all calibration points
C_all_joint   = [];
R_all_joint   = [];
Rsd_all_joint = [];
C_high_all    = [];
optode_id     = [];

for f = 1:nOpt
    C_this  = cal(f).C(:);
    R_this  = cal(f).R(:);
    Rsd_this= cal(f).Rsd(:);

    % Highest O2 concentration for this optode
    C_high_f = max(C_this);

    C_all_joint   = [C_all_joint;   C_this];
    R_all_joint   = [R_all_joint;   R_this];
    Rsd_all_joint = [Rsd_all_joint; Rsd_this];
    C_high_all    = [C_high_all;    C_high_f * ones(numel(C_this),1)];
    optode_id     = [optode_id;     f * ones(numel(C_this),1)];
end

% Force column vectors
C_all_joint   = C_all_joint(:);
R_all_joint   = R_all_joint(:);
Rsd_all_joint = Rsd_all_joint(:);
C_high_all    = C_high_all(:);
optode_id     = optode_id(:);

% Weights
w_joint = 1 ./ (Rsd_all_joint.^2);
w_joint = w_joint(:);

% ---------------------------------------------------------
% Joint model:
% p = [alpha, Ksv, Rhigh_1, Rhigh_2, ..., Rhigh_n]
%
% R(C) = Rhigh_f * [ alpha + (1-alpha)/(1+Ksv*C) ] ...
%                  / [ alpha + (1-alpha)/(1+Ksv*C_high_f) ]
% ---------------------------------------------------------
joint_model = @(p, C, C_high, id) local_joint_model_Rhigh(p, C, C_high, id);

% Initial guess from independent fits
alpha0_joint = mean(arrayfun(@(s) s.params(1), cal));
Ksv0_joint   = mean(arrayfun(@(s) s.params(2), cal));

Rhigh_init = zeros(1,nOpt);
for f = 1:nOpt
    idxHigh = cal(f).C == max(cal(f).C);
    Rhigh_init(f) = mean(cal(f).R(idxHigh));
end

% Make sure initial guess is row vector
p0_joint = [alpha0_joint, Ksv0_joint, Rhigh_init(:)'];
lb_joint = [0, 0, zeros(1,nOpt)];
ub_joint = [1, inf, inf(1,nOpt)];

% Weighted objective function
obj_joint = @(p) sum( ...
    w_joint .* ...
    (R_all_joint - joint_model(p, C_all_joint, C_high_all, optode_id)).^2, ...
    'omitnan');

% Optional sanity check
test_val = obj_joint(p0_joint);
fprintf('Initial joint objective = %.6g\n', test_val);

% Joint optimization
p_joint = fmincon(obj_joint, p0_joint, [], [], [], [], lb_joint, ub_joint, [], opts);

alpha_joint = p_joint(1);
Ksv_joint   = p_joint(2);
Rhigh_joint = p_joint(3:end);

fprintf('\n====================================================\n');
fprintf('JOINT FIT (shared alpha, shared Ksv, separate R@highest O2)\n');
fprintf('  alpha_shared = %.6f\n', alpha_joint);
fprintf('  Ksv_shared   = %.6g\n', Ksv_joint);
for f = 1:nOpt
    fprintf('  Rhigh_%d (%s) = %.6f\n', f, labels(f), Rhigh_joint(f));
end
fprintf('====================================================\n');

%% -------- Compute joint-fit predictions per optode at datapoints --------
for f = 1:nOpt
    C_this = cal(f).C(:);
    C_high_f = max(C_this);

    p_this = [alpha_joint, Ksv_joint, Rhigh_joint(f)];

    model_this = @(p,C) p(3) .* ...
        ( p(1) + (1-p(1)) ./ (1 + p(2).*C) ) ./ ...
        ( p(1) + (1-p(1)) ./ (1 + p(2).*C_high_f) );

    cal(f).joint_params = p_this;
    cal(f).joint_Rfit   = model_this(p_this, C_this);
    cal(f).joint_resid  = cal(f).R - cal(f).joint_Rfit;
end

%% =========================================================
% FINAL PLOT
% Individual fit points + CI whiskers + joint fit points
%% =========================================================
figure; hold on;

for f = 1:nOpt
    c = colors(f,:);

    % Individual-fit CI whiskers at datapoints
    errorbar(cal(f).Cfit, cal(f).Rfit, ...
             cal(f).Rfit - cal(f).Rlo, cal(f).Rhi - cal(f).Rfit, ...
             'LineStyle','none', 'Color', c, 'LineWidth', 1);

    % Raw weighted calibration points
    errorbar(cal(f).C, cal(f).R, cal(f).Rsd, ...
             'o', 'Color', c, 'MarkerFaceColor', c, 'LineStyle','none');

    % Individual fit evaluated at datapoints
    plot(cal(f).Cfit, cal(f).Rfit, 's', ...
         'Color', c, 'MarkerFaceColor', 'w', 'LineWidth', 1.2, 'MarkerSize', 7);

    % Joint fit evaluated at datapoints
    plot(cal(f).C, cal(f).joint_Rfit, '-', ...
         'Color', c, 'LineWidth', 2);
end

xlabel('O_2 concentration');
ylabel('R = Red / Green');
grid on;
title('Modified Stern–Volmer calibration: individual fits and joint shared-shape fit');

% Build legend manually
lgdEntries = strings(0);
for f = 1:nOpt
    lgdEntries(end+1) = labels(f) + " data";
    lgdEntries(end+1) = labels(f) + " individual fit";
    lgdEntries(end+1) = labels(f) + " joint fit";
end

legend(lgdEntries, 'Location','bestoutside');

%% =========================================================
% Optional: Save pooled summary including shared parameters
%% =========================================================

summaryTable = table(labels(:), ...
    arrayfun(@(s) s.params(1), cal(:)), ...
    arrayfun(@(s) s.params(2), cal(:)), ...
    arrayfun(@(s) s.params(3), cal(:)), ...
    arrayfun(@(s) s.Cfit(end), cal(:)), ...
    Rhigh_joint(:), ...
    repmat(alpha_joint, numel(labels), 1), ...
    repmat(Ksv_joint, numel(labels), 1), ...
    'VariableNames', { ...
        'Optode', ...
        'alpha_ind', ...
        'Ksv_ind', ...
        'R0_ind', ...
        'C_high',...
        'Rhigh_joint', ...
        'alpha_shared', ...
        'Ksv_shared'});

% Extract base optode name (before "_id")
baseName = extractBefore(labels(1), "_id");
filename = "calibration_summary_"+baseName+".csv";
writetable(summaryTable, filename);

%% =========================================================
% Local joint-model function
%% =========================================================
function R = local_joint_model_Rhigh(p, C, C_high, id)
    % p = [alpha, Ksv, Rhigh_1, Rhigh_2, ..., Rhigh_n]

    alpha  = p(1);
    Ksv    = p(2);
    Rhighs = p(3:end);

    C      = C(:);
    C_high = C_high(:);
    id     = id(:);

    Rhigh = Rhighs(id).';
    Rhigh = Rhigh(:);

    numerator = alpha + (1 - alpha) ./ (1 + Ksv .* C);
    denom     = alpha + (1 - alpha) ./ (1 + Ksv .* C_high);

    R = Rhigh .* (numerator ./ denom);
    R = R(:);
end
