%% ===== DATA FOLDER =====
data_folder = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\1 - Conservative Transport data';  % <-- update to your subfolder name


%% ===== EXPERIMENT DEFINITIONS =====
experiments(1).label        = 'cQ - 12 µL/min';
experiments(1).conc_file    = 'C_CQ_55_refined.mat';
experiments(1).biomass_file = 'biomass_CQ_T055.mat';
experiments(1).vel_file_x   = 'Ufx_CQ_T055.mat';       % <-- fill in actual filenames
experiments(1).vel_file_y   = 'Ufy_CQ_T055.mat';
experiments(1).Q_uLmin      = 11.28;
experiments(1).color        = [0.0, 0.3, 0.8];

experiments(2).label        = 'cP - 1 µL/min';
experiments(2).conc_file    = 'C_CP_123_refined.mat';
experiments(2).biomass_file = 'biomass_CP_T123.mat';
experiments(2).vel_file_x   = 'Ufx_CP_T123.mat';       % <-- fill in actual filenames
experiments(2).vel_file_y   = 'Ufy_CP_T123.mat';
experiments(2).Q_uLmin      = 0.72;
experiments(2).color        = [0.4, 0.6, 1.0];

experiments(3).label        = 'Bare model - 1 µL/min';
experiments(3).conc_file    = 'C_LowQ_refined.mat';
experiments(3).biomass_file = 'biomass_bare_model.mat';
experiments(3).vel_file_x   = 'Ufx_CQ_T00_Low.mat';       % <-- fill in actual filenames
experiments(3).vel_file_y   = 'Ufy_CQ_T00_Low.mat';
experiments(3).Q_uLmin      = 0.94;
experiments(3).color        = [0.8, 0.1, 0.1];

experiments(4).label        = 'Bare model - 12 µL/min';
experiments(4).conc_file    = 'C_HighQ_refined.mat';
experiments(4).biomass_file = 'biomass_bare_model.mat';
experiments(4).vel_file_x   = 'Ufx_CQ_T00_High.mat';       % <-- fill in actual filenames
experiments(4).vel_file_y   = 'Ufy_CQ_T00_High.mat';
experiments(4).Q_uLmin      = 11.28;
experiments(4).color        = [1.0, 0.5, 0.5];

%% ===== PHYSICAL PARAMETERS =====
img_rows     = 2700;
img_cols     = 1654;

flow_dir_cm  = 1.5;
cross_dir_cm = 1.0;

px_size_row    = (flow_dir_cm  * 1e4) / img_rows;
px_size_col    = (cross_dir_cm * 1e4) / img_cols;
pixel_area_um2 = px_size_row * px_size_col;
depth_um       = 30;
pixel_vol_uL   = pixel_area_um2 * depth_um * 1e-9;

%% ===== SETUP FIGURES =====
fig1 = figure('Name', 'BTC - C* vs Initial PVI');          hold on;
fig2 = figure('Name', 'BTC - C* vs Effective PVI');        hold on;
fig3 = figure('Name', 'BTC - C* vs t/t_mean');             hold on;
fig4 = figure('Name', 'RTD - E(theta) vs theta');          hold on;
fig5 = figure('Name', 'RTD - E(t) vs real time');          hold on;
fig6 = figure('Name', 'RTD - E(PVI) vs Pore Volume');      hold on;

nExp = numel(experiments);

%% ===== PROCESS EACH EXPERIMENT =====
for e = 1:nExp
    fprintf('\n--- Processing: %s ---\n', experiments(e).label);

    %% Load concentration
    S_conc   = load(fullfile(data_folder, experiments(e).conc_file));
    conc_var = fieldnames(S_conc);
    data     = S_conc.(conc_var{1});
    nT       = size(data, 2);
    %% Load biomass
    S_bio   = load(fullfile(data_folder, experiments(e).biomass_file));
    bio_var = fieldnames(S_bio);
    B       = S_bio.(bio_var{1});
    B       = B(1:img_rows, 1:img_cols);

    %% Load velocity — static fields, same structure as biomass  <-- FINAL
    S_velx  = load(fullfile(data_folder, experiments(e).vel_file_x));
    velx_var = fieldnames(S_velx);
    Vx_field = S_velx.(velx_var{1});
    Vx_field = Vx_field(1:img_rows, 1:img_cols);

    S_vely  = load(fullfile(data_folder, experiments(e).vel_file_y));
    vely_var = fieldnames(S_vely);
    Vy_field = S_vely.(vely_var{1});
    Vy_field = Vy_field(1:img_rows, 1:img_cols);

    Vmag_field       = sqrt(Vx_field.^2 + Vy_field.^2);
    vmag_outlet_base = Vmag_field(end, :);   % outlet velocity profile, reused every timestep

    %% Masks & pore volumes
    grain_mask        = isnan(B);
    pore_mask_initial = ~grain_mask;
    Vp0_uL            = sum(pore_mask_initial(:)) * pixel_vol_uL;

    phi_b             = B;
    phi_b(grain_mask) = 0;
    phi_b(B == 1)     = 0;
    Vp_eff_uL         = sum((1 - phi_b(pore_mask_initial))) * pixel_vol_uL;

    Q_uLs = experiments(e).Q_uLmin / 60;
    ...

    %% BTC extraction loop
    t_vec       = zeros(1, nT);
    C_out_res   = zeros(1, nT);   % resident (simple spatial mean)
    C_out_flux  = zeros(1, nT);   % velocity-weighted (flux-averaged)
    PVI0        = zeros(1, nT);
    PVI_eff     = zeros(1, nT);

    for k = 1:nT
        t_vec(k) = data{1, k};
        C        = data{2, k};
        C        = C(1:img_rows, 1:img_cols);

        outlet          = C(end, :);
        outlet_mask     = grain_mask(end, :);
        outlet(outlet_mask) = NaN;
        C_out_res(k)    = mean(outlet, 'omitnan');

        %% flux-weighted outlet concentration — static velocity field  <-- FINAL
        vmag_outlet = vmag_outlet_base;
        vmag_outlet(outlet_mask) = NaN;

        num = outlet .* vmag_outlet;
        C_out_flux(k) = sum(num, 'omitnan') / sum(vmag_outlet, 'omitnan');

        PVI0(k)    = (Q_uLs * t_vec(k)) / Vp0_uL;
        PVI_eff(k) = (Q_uLs * t_vec(k)) / Vp_eff_uL;
    end

    %% Normalize concentration
    C_star      = C_out_flux / max(C_out_flux);   % primary BTC — flux-weighted, matches ADE boundary condition
    C_star_res  = C_out_res  / max(C_out_res);    % resident version, kept for comparison

    %% ===== RTD — E(t) from washout F-curve =====
    F_curve = 1 - C_star;
    E_t     = gradient(F_curve, t_vec);
    E_t     = max(E_t, 0);

    E_area  = trapz(t_vec, E_t);
    if E_area > 0
        E_t = E_t / E_area;
    end

    %% ===== Moments in absolute time =====
    t_mean = trapz(t_vec, t_vec .* E_t);
    sigma2 = trapz(t_vec, (t_vec - t_mean).^2 .* E_t);
    sigma  = sqrt(sigma2);
    skew   = trapz(t_vec, (t_vec - t_mean).^3 .* E_t) / sigma^3;

    tau0    = Vp0_uL    / Q_uLs;
    tau_eff = Vp_eff_uL / Q_uLs;
    Pe      = t_mean^2  / sigma2;

    %% ===== Dimensionless theta: normalize by t_mean =====
    % theta = t / t_mean
    % E(theta) = E(t) * t_mean   [preserves area = 1]
    theta        = t_vec  / t_mean;
    E_theta      = E_t    * t_mean;
    sigma2_theta = sigma2 / t_mean^2;   % dimensionless variance = 1/Pe
    sigma_theta  = sqrt(sigma2_theta);
    skew_theta   = skew;                % skewness is frame-independent

    %% ===== E vs PVI (effective pore volume) =====
    % PVI axis is already computed as PVI_eff = Q*t / Vp_eff
    % E(PVI) = E(t) * tau_eff   [change of variables: PVI = t/tau_eff]
    % This preserves area = 1 on the PVI axis
    E_PVI        = E_t * tau_eff;

    % PVI-frame moments (dimensionless, analogous to theta but using tau_eff)
    PVI_mean     = t_mean  / tau_eff;   % should be near 1 for ideal transport
    sigma2_PVI   = sigma2  / tau_eff^2;
    sigma_PVI    = sqrt(sigma2_PVI);
    % Skewness unchanged — dimensionless and frame-independent

    fprintf('  t_mean        = %.2f s\n',  t_mean);
    fprintf('  sigma         = %.2f s\n',  sigma);
    fprintf('  tau0          = %.2f s  (initial HRT)\n',   tau0);
    fprintf('  tau_eff       = %.2f s  (effective HRT)\n', tau_eff);
    fprintf('  t_mean/tau0   = %.3f\n',    t_mean / tau0);
    fprintf('  t_mean/tau_eff= %.3f\n',    t_mean / tau_eff);
    fprintf('  Pe            = %.2f\n',    Pe);
    fprintf('  sigma2_theta  = %.4f  (= 1/Pe)\n', sigma2_theta);
    fprintf('  sigma2_PVI    = %.4f\n',    sigma2_PVI);
    fprintf('  PVI_mean      = %.3f\n',    PVI_mean);
    fprintf('  skewness      = %.3f\n',    skew_theta);

    %% Store results
    experiments(e).PVI0         = PVI0;
    experiments(e).PVI_eff      = PVI_eff;
    experiments(e).C_star       = C_star;
    experiments(e).t_vec        = t_vec;
    experiments(e).t_mean       = t_mean;
    experiments(e).sigma        = sigma;
    experiments(e).sigma2       = sigma2;
    experiments(e).theta        = theta;
    experiments(e).E_t          = E_t;
    experiments(e).E_theta      = E_theta;
    experiments(e).E_PVI        = E_PVI;
    experiments(e).sigma2_theta = sigma2_theta;
    experiments(e).sigma_theta  = sigma_theta;
    experiments(e).sigma2_PVI   = sigma2_PVI;
    experiments(e).sigma_PVI    = sigma_PVI;
    experiments(e).PVI_mean     = PVI_mean;
    experiments(e).skew         = skew_theta;
    experiments(e).tau0         = tau0;
    experiments(e).tau_eff      = tau_eff;
    experiments(e).Pe           = Pe;
    experiments(e).Vp0_uL       = Vp0_uL;
    experiments(e).Vp_eff_uL    = Vp_eff_uL;
    experiments(e).t_norm       = theta;

    %% Safe values for log scale
    PVI0_safe    = PVI0;     PVI0_safe(PVI0_safe <= 0)      = NaN;
    PVI_eff_safe = PVI_eff;  PVI_eff_safe(PVI_eff_safe <= 0)= NaN;
    theta_safe   = theta;    theta_safe(theta_safe <= 0)    = NaN;
    C_safe       = C_star;   C_safe(C_safe <= 0)            = NaN;
    E_t_safe     = E_t;      E_t_safe(E_t_safe <= 0)        = NaN;
    E_th_safe    = E_theta;  E_th_safe(E_th_safe <= 0)      = NaN;
    E_PVI_safe   = E_PVI;    E_PVI_safe(E_PVI_safe <= 0)    = NaN;
    t_safe       = t_vec;    t_safe(t_safe <= 0)            = NaN;

    %% ===== y-axis maxima for patch annotations =====
    ymax_et  = max(E_t(~isnan(E_t)     & E_t > 0));
    ymax_eth = max(E_theta(~isnan(E_theta) & E_theta > 0));
    ymax_epv = max(E_PVI(~isnan(E_PVI) & E_PVI > 0));

    %% --- Plot 1: C* vs Initial PVI ---
    figure(fig1);
    plot(PVI0_safe, C_safe, '-', ...
        'Color',           experiments(e).color, ...
        'LineWidth',       1.5, ...
        'MarkerFaceColor', experiments(e).color, ...
        'DisplayName',     experiments(e).label);

    %% --- Plot 2: C* vs Effective PVI ---
    figure(fig2);
    plot(PVI_eff_safe, C_safe, '-', ...
        'Color',           experiments(e).color, ...
        'LineWidth',       1.5, ...
        'MarkerFaceColor', experiments(e).color, ...
        'DisplayName',     experiments(e).label);

    %% --- Plot 3: C* vs t/t_mean ---
    figure(fig3);
    plot(theta_safe, C_safe, '-', ...
        'Color',           experiments(e).color, ...
        'LineWidth',       1.5, ...
        'MarkerFaceColor', experiments(e).color, ...
        'DisplayName',     sprintf('%s  (t_{mean}=%.1fs)', ...
                           experiments(e).label, t_mean));

    %% --- Plot 4: E(theta) vs theta  [flow-rate independent] ---
    figure(fig4);
    plot(theta_safe, E_th_safe, '-', ...
        'Color',       experiments(e).color, ...
        'LineWidth',   1.5, ...
        'DisplayName', sprintf('%s, \\sigma^2_\\theta=%.3f)', ...
                       experiments(e).label, sigma2_theta));

    xline(1, '--k', 'HandleVisibility', 'off');

    patch([1-sigma_theta, 1+sigma_theta, 1+sigma_theta, 1-sigma_theta], ...
          [0, 0, ymax_eth*0.18, ymax_eth*0.18], ...
          experiments(e).color, ...
          'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    %% --- Plot 5: E(t) vs real time  [absolute, flow-rate dependent] ---
    figure(fig5);
    plot(t_safe, E_t_safe, '-', ...
        'Color',       experiments(e).color, ...
        'LineWidth',   1.5, ...
        'DisplayName', sprintf('%s, t_{mean}=%.1fs, \\sigma=%.1fs', ...
                       experiments(e).label, t_mean, sigma));

    % Mark t_mean with vertical dashed line
    xline(t_mean, '--', ...
        'Color',            experiments(e).color, ...
        'LineWidth',        1.2, ...
        'HandleVisibility', 'off');

    % Shaded band: +/- sigma around t_mean
    patch([t_mean-sigma, t_mean+sigma, t_mean+sigma, t_mean-sigma], ...
          [0, 0, ymax_et*0.18, ymax_et*0.18], ...
          experiments(e).color, ...
          'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    %% --- Plot 6: E(PVI) vs PVI_eff  [pore-volume frame] ---
    figure(fig6);
    plot(PVI_eff_safe, E_PVI_safe, '-', ...
        'Color',       experiments(e).color, ...
        'LineWidth',   1.5, ...
        'DisplayName', sprintf('%s, PVI_{mean}=%.2f, \\sigma_{PVI}=%.3f', ...
                       experiments(e).label, PVI_mean, sigma_PVI));

    % Mark PVI_mean with vertical dashed line
    xline(PVI_mean, '--', ...
        'Color',            experiments(e).color, ...
        'LineWidth',        1.2, ...
        'HandleVisibility', 'off');

    % Reference line at PVI = 1 (ideal plug flow breakthrough)
    xline(1, '--k', 'HandleVisibility', 'off');

    % Shaded band: +/- sigma_PVI around PVI_mean
    patch([PVI_mean-sigma_PVI, PVI_mean+sigma_PVI, ...
           PVI_mean+sigma_PVI, PVI_mean-sigma_PVI], ...
          [0, 0, ymax_epv*0.18, ymax_epv*0.18], ...
          experiments(e).color, ...
          'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

end

%% ===== FORMAT PLOT 1: C* vs Initial PVI =====
figure(fig1);
xline(1, '--k', 'PVI = 1', 'LabelVerticalAlignment', 'bottom', ...
      'HandleVisibility', 'off');
set(gca, 'XScale', 'log', 'YScale', 'log');
xlabel('Pore Volumes Injected');
ylabel('C / C_0');
title('BTC — {C* vs Initial PVI  (abiotic)}');
legend('Location', 'southeast');
grid on; axis tight;

%% ===== FORMAT PLOT 2: C* vs Effective PVI =====
figure(fig2);
xline(1, '--k', 'PVI = 1', 'LabelVerticalAlignment', 'bottom', ...
      'HandleVisibility', 'off');
set(gca, 'XScale', 'log', 'YScale', 'log');
xlabel('Pore Volumes Injected');
ylabel('C / C_0');
title('BTC — {C* vs Effective PVI  (biofilm-corrected)}');
legend('Location', 'southeast');
grid on; axis tight;

%% ===== FORMAT PLOT 3: C* vs t/t_mean =====
figure(fig3);
xline(1, '--k', 't / t_{mean} = 1', 'LabelVerticalAlignment', 'bottom', ...
      'HandleVisibility', 'off');
set(gca, 'XScale', 'log', 'YScale', 'log');
xlabel('Normalized Time  \theta = t / t_{mean}');
ylabel('C / C_0');
title('BTC — {C* vs Normalized Residence Time}');
legend('Location', 'southeast');
grid on; axis tight;

%% ===== FORMAT PLOT 4: E(theta) vs theta =====
figure(fig4);
xline(1, '--k', '\theta = 1  (mean)', ...
    'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
set(gca, 'XScale', 'log', 'YScale', 'log');
xlabel('Normalized Time  \theta = t / t_{mean}');
ylabel('E(\theta) = E(t) \cdot t_{mean}  (dimensionless)');
title('RTD — Normalized E(\theta)');
legend('Location', 'northeast');
grid on; axis tight;

%% ===== FORMAT PLOT 5: E(t) vs real time =====
figure(fig5);
set(gca, 'XScale', 'log', 'YScale', 'log');
xlabel('Time  t  (s)');
ylabel('E(t)  (s^{-1})');
title('RTD — {E(t) vs Absolute Time}');
legend('Location', 'northeast');
grid on; axis tight;

%% ===== FORMAT PLOT 6: E(PVI) vs PVI =====
figure(fig6);
xline(1, '--k', 'PVI = 1  (plug flow)', ...
    'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
set(gca, 'XScale', 'log', 'YScale', 'log');
xlabel('Pore Volumes Injected  | PVI_{eff} = Q \cdot t / V_{p,eff}');
ylabel('E(PVI) = E(t) \cdot \tau_{eff}  (dimensionless)');
title('RTD {E(PVI) vs Effective Pore Volumes}');
legend('Location', 'northeast');
grid on; axis tight;
annotation('textbox', [0.13, 0.01, 0.75, 0.04], ...
    'String', 'Dashed colored lines: PVI_{mean} per experiment', ...
    'EdgeColor', 'none', 'FontSize', 8, 'HorizontalAlignment', 'center');

%% ===== SUMMARY TABLE =====
fprintf('\n%-25s %10s %10s %10s %10s %10s %10s %10s %10s\n', ...
    'Experiment', 'Vp0 (µL)', 'Vpeff (µL)', 't_mean (s)', ...
    'tau_eff (s)', 'Pe', 'sig2_theta', 'sig2_PVI', 'Skewness');
fprintf('%s\n', repmat('-', 1, 110));
for e = 1:nExp
    fprintf('%-25s %10.4f %10.4f %10.2f %10.2f %10.2f %10.4f %10.4f %10.3f\n', ...
        experiments(e).label, ...
        experiments(e).Vp0_uL, ...
        experiments(e).Vp_eff_uL, ...
        experiments(e).t_mean, ...
        experiments(e).tau_eff, ...
        experiments(e).Pe, ...
        experiments(e).sigma2_theta, ...
        experiments(e).sigma2_PVI, ...
        experiments(e).skew);
end