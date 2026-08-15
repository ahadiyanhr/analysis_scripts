%% ================================================================
%  BIOMASS DENSITY PDF / CDF BATCH ANALYSIS  v3  (pure-math KDE)
%  THREE experiment types: cP, cQ_high, cQ_low
%
%  Reads density pixel data directly from files named:
%     thresholded_XX.mat   or   thresholded_XXX.mat
%  where XX/XXX is the timepoint (2 or 3 digits, e.g. "07" or "128").
%
%  No ksdensity / Statistics Toolbox dependency. The PDF is a
%  manually-implemented Gaussian kernel density estimate (Silverman's
%  rule-of-thumb bandwidth, boundary-reflected at [0,1] since density
%  is a bounded quantity). The CDF is the exact empirical CDF
%  (sorted values vs. rank/n). Quantiles (for the bandwidth rule) are
%  computed from scratch via linear interpolation on sorted data --
%  no prctile/iqr toolbox calls.
%
%  For each (type, timepoint) this computes the distribution of
%  biofilm density values (BIOFILM PIXELS ONLY -- open pore and grain
%  pixels are excluded from the distribution).
%
%  OUTPUTS:
%   1. Per-type figure: PDF + CDF, all timepoints overlaid as
%      colored curves, labeled by legend (hours).
%   2. Pooled figure: PDF + CDF, one curve per type (all timepoints
%      pooled together per type) for cross-type comparison.
%   3. Variance bar chart: pooled variance per type (all timepoints
%      combined).
%   4. Variance-vs-time line plot: one line per type showing how
%      variance of the density distribution evolves over time.
%
%  BIOMASS VALUE CONVENTION (unchanged from source data):
%     NaN         -> grain
%     1           -> open pore, no biofilm
%     [0, 0.99]   -> biomass occupancy; 0.99 = very LOW density,
%                     0 = very HIGH density (i.e. inverted scale)
%
%  Converted to an intuitive 0->1 "density" scale (BIOFILM PIXELS ONLY):
%     dens = (0.99 - biomass) / 0.99
% ================================================================

%% ================================================================
%  SECTION 1 -- USER INPUT  (only section you need to edit)
% ================================================================

folder_cP      = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\2 - biomass density data\cP';
% folder_cQ_high = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\2 - biomass density data\cQ_high';
folder_cQ_low  = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\2 - biomass density data\cQ_low';
folder_plots   = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\pooled_density_PDF_CDF';

% Which experiment types to actually run this pass.
% Comment/uncomment WHOLE lines here -- never edit inside the cell arrays below.
active_types = {'cP', 'cQ_low'};

% Density file naming convention: thresholded_XX.mat / thresholded_XXX.mat
file_prefix = 'thresholded';

% Biomass raw-value convention (edit only if the source files change)
biomass_sparse_val = 0.99;   % raw value meaning "very low density"
biomass_dense_val  = 0;    % raw value meaning "very high density"
pore_val_min       = 1;    % raw value >= this => open pore, no biofilm (EXCLUDED here)

% KDE controls (pure-math Gaussian KDE, no ksdensity)
kde_grid_n        = 201;     % number of evaluation points on [0,1]
kde_max_points    = 20000;   % subsample cap for speed (CDF/variance use full data)
kde_bandwidth_min = 1e-3;    % floor to avoid a degenerate (zero) bandwidth

% PNG resolution
png_dpi = 300;               % 300 dpi is PNAS figure standard

%% ================================================================
%  SECTION 2 -- SETUP
% ================================================================

if ~exist(folder_plots, 'dir'), mkdir(folder_plots); end
fprintf('Output folder: %s\n', folder_plots);

% Master lookup: every possible type -> its folder and its color.
% Keyed by name (a containers.Map), so excluding a type from
% active_types never shifts anyone else's color or folder.
all_folders = containers.Map( ...
    {'cP', 'cQ_low'}, ...
    {folder_cP, folder_cQ_low});

all_colors = containers.Map( ...
    {'cP', 'cQ_high', 'cQ_low'}, ...
    { [0.16 0.49 0.72], ...   % cP       - steel blue
      [0.85 0.33 0.10], ...   % cQ_high  - burnt orange/red
      [0.47 0.25 0.65] });    % cQ_low   - deep purple

types   = active_types;
folders = cellfun(@(t) all_folders(t), types, 'UniformOutput', false);
type_colors = cell2mat(cellfun(@(t) all_colors(t), types, 'UniformOutput', false)');

for fi = 1:numel(folders)
    if ~exist(folders{fi}, 'dir')
        error('Folder not found: %s\nCheck paths in Section 1.', folders{fi});
    end
end

xi_grid = linspace(0, 1, kde_grid_n)';   % shared evaluation grid for all PDFs

%% ================================================================
%  SECTION 3 -- DATA COLLECTION (biofilm-pixel density vectors)
% ================================================================

data = struct('type', types, 'time_hr', [], 'dens', {{}}, 'var', []);

for g = 1:numel(types)

    gtype   = types{g};
    gfolder = folders{g};

    fprintf('\n%s\n  Group: %s\n%s\n', repmat('=',1,60), gtype, repmat('=',1,60));

    all_files = dir(fullfile(gfolder, '*.mat'));
    if isempty(all_files)
        warning('No .mat files in: %s', gfolder); continue;
    end
    names_all = {all_files.name};

    % Keep only thresholded_XX.mat / thresholded_XXX.mat files
    is_match = startsWith_ci(names_all, file_prefix);
    file_list = names_all(is_match);

    tokens = cellfun(@extract_time_token, file_list, 'UniformOutput', false);
    valid  = ~cellfun(@isempty, tokens);
    file_list = file_list(valid);
    tokens    = tokens(valid);

    time_hr = cellfun(@str2double, tokens);
    [time_hr, order] = sort(time_hr, 'ascend');
    file_list = file_list(order);

    fprintf('  Found: %d thresholded files | %d timepoints\n', numel(names_all), numel(file_list));

    nT = numel(file_list);
    dens_cell = cell(1, nT);
    var_vec   = NaN(1, nT);

    for ti = 1:nT
        biomass = load_first_var(fullfile(gfolder, file_list{ti}));
        dens_vec = compute_bio_density(biomass, biomass_sparse_val, biomass_dense_val, pore_val_min);

        dens_cell{ti} = dens_vec;
        var_vec(ti)   = var(dens_vec);

        fprintf('  --> %s  (%.0f hr)  n=%d biofilm px  var=%.4f\n', ...
            file_list{ti}, time_hr(ti), numel(dens_vec), var_vec(ti));
    end

    data(g).type    = gtype;
    data(g).time_hr = time_hr;
    data(g).dens    = dens_cell;
    data(g).var     = var_vec;
end

%% ================================================================
%  SECTION 4 -- PER-TYPE PDF/CDF, TIMEPOINTS OVERLAID (legend-labeled)
% ================================================================

for g = 1:numel(types)
    gtype   = data(g).type;
    time_hr = data(g).time_hr;
    nT = numel(time_hr);
    if nT == 0, continue; end

    cmap_t = parula(nT);

    fig = figure('Visible', 'off', 'Position', [0 0 1100 460], 'Color', 'w');
    tl = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    ax_pdf = nexttile(tl); hold(ax_pdf, 'on');
    ax_cdf = nexttile(tl); hold(ax_cdf, 'on');

    h_t = gobjects(1, nT);   % one legend handle per timepoint

    for ti = 1:nT
        vals = data(g).dens{ti};
        if isempty(vals), continue; end

        kvals = subsample_for_kde(vals, kde_max_points);
        f = manual_kde_reflected(kvals, xi_grid, kde_bandwidth_min);
        h_t(ti) = plot(ax_pdf, xi_grid, f, '-', 'Color', cmap_t(ti,:), 'LineWidth', 1.8, ...
            'DisplayName', sprintf('%.0f hr', time_hr(ti)));

        [xs, ys] = manual_ecdf(vals);
        plot(ax_cdf, xs, ys, '-', 'Color', cmap_t(ti,:), 'LineWidth', 1.8);
    end

    xlabel(ax_pdf, 'Biofilm density'); ylabel(ax_pdf, 'Probability density');
    title(ax_pdf, sprintf('%s -- PDF', gtype), 'FontWeight', 'bold');
    set(ax_pdf, 'FontSize', 10, 'Box', 'off'); grid(ax_pdf, 'on'); ax_pdf.GridAlpha = 0.15;
    xlim(ax_pdf, [0 1]);
    legend(ax_pdf, h_t(isgraphics(h_t)), 'Location', 'northeast', 'Box', 'off', 'FontSize', 8);

    xlabel(ax_cdf, 'Biofilm density'); ylabel(ax_cdf, 'Cumulative probability');
    title(ax_cdf, sprintf('%s -- CDF', gtype), 'FontWeight', 'bold');
    set(ax_cdf, 'FontSize', 10, 'Box', 'off'); grid(ax_cdf, 'on'); ax_cdf.GridAlpha = 0.15;
    xlim(ax_cdf, [0 1]); ylim(ax_cdf, [0 1]);

    fname = fullfile(folder_plots, sprintf('%s_density_pdf_cdf_timepoints.png', gtype));
    print(fig, fname, '-dpng', sprintf('-r%d', png_dpi));
    close(fig);
    fprintf('Saved: %s\n', fname);
end

%% ================================================================
%  SECTION 5 -- POOLED PDF/CDF ACROSS TYPES (all timepoints combined)
% ================================================================

pooled_vals = cell(1, numel(types));
for g = 1:numel(types)
    pooled_vals{g} = vertcat(data(g).dens{:});
end

fig = figure('Visible', 'off', 'Position', [0 0 1100 460], 'Color', 'w');
tl = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

ax_pdf = nexttile(tl); hold(ax_pdf, 'on');
ax_cdf = nexttile(tl); hold(ax_cdf, 'on');

h_leg = gobjects(1, numel(types));
for g = 1:numel(types)
    vals = pooled_vals{g};
    if isempty(vals), continue; end

    kvals = subsample_for_kde(vals, kde_max_points);
    f = manual_kde_reflected(kvals, xi_grid, kde_bandwidth_min);
    h_leg(g) = plot(ax_pdf, xi_grid, f, '-', 'Color', type_colors(g,:), 'LineWidth', 2.2, ...
        'DisplayName', types{g});

    [xs, ys] = manual_ecdf(vals);
    plot(ax_cdf, xs, ys, '-', 'Color', type_colors(g,:), 'LineWidth', 2.2);
end

xlabel(ax_pdf, 'Biofilm density'); ylabel(ax_pdf, 'Probability density');
title(ax_pdf, 'Pooled PDF (all timepoints)', 'FontWeight', 'bold');
set(ax_pdf, 'FontSize', 10, 'Box', 'off'); grid(ax_pdf, 'on'); ax_pdf.GridAlpha = 0.15;
xlim(ax_pdf, [0 1]);
legend(ax_pdf, h_leg(isgraphics(h_leg)), 'Location', 'northeast', 'Box', 'off');

xlabel(ax_cdf, 'Biofilm density'); ylabel(ax_cdf, 'Cumulative probability');
title(ax_cdf, 'Pooled CDF (all timepoints)', 'FontWeight', 'bold');
set(ax_cdf, 'FontSize', 10, 'Box', 'off'); grid(ax_cdf, 'on'); ax_cdf.GridAlpha = 0.15;
xlim(ax_cdf, [0 1]); ylim(ax_cdf, [0 1]);

fname = fullfile(folder_plots, 'pooled_density_pdf_cdf_by_type.png');
print(fig, fname, '-dpng', sprintf('-r%d', png_dpi));
close(fig);
fprintf('Saved: %s\n', fname);

%% ================================================================
%  SECTION 6 -- VARIANCE ACROSS TYPES
% ================================================================

% ---- (a) Pooled variance per type (bar chart) ----------------------
pooled_var = NaN(1, numel(types));
for g = 1:numel(types)
    if ~isempty(pooled_vals{g})
        pooled_var(g) = var(pooled_vals{g});
    end
end

fig = figure('Visible', 'off', 'Position', [0 0 560 460], 'Color', 'w');
ax = axes(fig);
b = bar(ax, pooled_var, 'FaceColor', 'flat');
b.CData = type_colors;
set(ax, 'XTick', 1:numel(types), 'XTickLabel', types, 'FontSize', 11, 'Box', 'off');
ylabel(ax, 'Variance of biofilm density (pooled)');
title(ax, 'Pooled density variance by experiment type', 'FontWeight', 'bold');
grid(ax, 'on'); ax.GridAlpha = 0.15;

fname = fullfile(folder_plots, 'pooled_variance_by_type.png');
print(fig, fname, '-dpng', sprintf('-r%d', png_dpi));
close(fig);
fprintf('Saved: %s\n', fname);

% ---- (b) Variance vs time per type (line plot) ----------------------
fig = figure('Visible', 'off', 'Position', [0 0 700 460], 'Color', 'w');
ax = axes(fig); hold(ax, 'on');

h_leg = gobjects(1, numel(types));
for g = 1:numel(types)
    if isempty(data(g).time_hr), continue; end
    h_leg(g) = plot(ax, data(g).time_hr, data(g).var, '-o', ...
        'Color', type_colors(g,:), 'MarkerFaceColor', type_colors(g,:), ...
        'LineWidth', 1.8, 'MarkerSize', 5, 'DisplayName', types{g});
end

xlabel(ax, 'Time (hr)'); ylabel(ax, 'Variance of biofilm density');
title(ax, 'Density variance over time by experiment type', 'FontWeight', 'bold');
set(ax, 'FontSize', 11, 'Box', 'off'); grid(ax, 'on'); ax.GridAlpha = 0.15;
legend(ax, h_leg(isgraphics(h_leg)), 'Location', 'best', 'Box', 'off');
hold(ax, 'off');

fname = fullfile(folder_plots, 'variance_vs_time_by_type.png');
print(fig, fname, '-dpng', sprintf('-r%d', png_dpi));
close(fig);
fprintf('Saved: %s\n', fname);

fprintf('\nAll done. Output folder:\n  %s\n\n', folder_plots);

%% ================================================================
%  LOCAL FUNCTIONS
%% ================================================================

function mask = startsWith_ci(names, prefix)
    mask = strncmpi(names, prefix, length(prefix));
end

% ----------------------------------------------------------------
%  extract_time_token -- pulls the numeric timepoint out of
%  "thresholded_XX.mat" or "thresholded_XXX.mat" (2 or 3 digits).
%  Returns '' if the pattern isn't found.
% ----------------------------------------------------------------
function token = extract_time_token(fname)
    m = regexp(fname, 'thresholded_(\d{2,3})', 'tokens', 'once');
    if isempty(m), token = ''; else, token = m{1}; end
end

function out = load_first_var(filepath)
    S = load(filepath); f = fieldnames(S); out = S.(f{1});
end

% ----------------------------------------------------------------
%  compute_bio_density -- returns a column vector of density values
%  for BIOFILM PIXELS ONLY (excludes grain and open pore).
%  dens in [0,1], 0 = sparse, 1 = dense (same convention as the
%  reactor-map plotter's inversion).
% ----------------------------------------------------------------
% function dens_vec = compute_bio_density(biomass, sparse_val, dense_val, pore_val_min)
%     grain_mask = isnan(biomass);
%     pore_mask  = ~grain_mask & (biomass >= pore_val_min);
%     bio_mask   = ~grain_mask & ~pore_mask & (biomass >= 0);
% 
%     raw = biomass(bio_mask);
%     dens_vec = (sparse_val - raw) / (sparse_val - dense_val);
%     dens_vec = min(max(dens_vec, 0), 1);
%     dens_vec = dens_vec(:);
% end

function dens_vec = compute_bio_density(biomass, sparse_val, dense_val, pore_val_min)
    grain_mask = isnan(biomass);
    pore_mask  = ~grain_mask & (biomass >= pore_val_min);
    bio_mask   = ~grain_mask & ~pore_mask & (biomass >= 0);

    raw = biomass(bio_mask);
    dens_vec = (sparse_val - raw) / (sparse_val - dense_val);
    dens_vec = min(max(dens_vec, 0), 1);
    dens_vec = dens_vec(:);
end

% ----------------------------------------------------------------
%  subsample_for_kde -- random subsample (without replacement) capped
%  at max_n points, used only to speed up the KDE curve. Variance/CDF
%  elsewhere use the FULL vector.
% ----------------------------------------------------------------
function out = subsample_for_kde(vals, max_n)
    n = numel(vals);
    if n <= max_n
        out = vals;
    else
        idx = randperm(n, max_n);
        out = vals(idx);
    end
end

% ----------------------------------------------------------------
%  manual_quantile -- linear-interpolation quantile on sorted data,
%  implemented from scratch (no prctile/iqr toolbox calls).
% ----------------------------------------------------------------
function q = manual_quantile(vals, p)
    xs = sort(vals(:));
    n = numel(xs);
    if n == 1, q = xs; return; end
    pos = p * (n - 1) + 1;
    lo = floor(pos); hi = ceil(pos);
    frac = pos - lo;
    lo = min(max(lo, 1), n);
    hi = min(max(hi, 1), n);
    q = xs(lo) * (1 - frac) + xs(hi) * frac;
end

% ----------------------------------------------------------------
%  manual_kde_reflected -- pure-math Gaussian kernel density estimate,
%  no ksdensity / Statistics Toolbox call.
%
%    f_hat(x) = (1/(n*h)) * sum_i  phi( (x - x_i) / h )
%
%  Bandwidth h via Silverman's (1986) rule of thumb:
%    h = 0.9 * min(sigma, IQR/1.34) * n^(-1/5)
%
%  Data are reflected across both boundaries of [0,1] before the
%  kernel sum (x -> -x and x -> 2-x), correcting the negative bias a
%  plain unbounded Gaussian KDE would otherwise have near the edges.
% ----------------------------------------------------------------
function f = manual_kde_reflected(vals, xi, h_min)
    vals = vals(:);
    n = numel(vals);

    sigma = std(vals);
    iqr_val = manual_quantile(vals, 0.75) - manual_quantile(vals, 0.25);
    A = min(sigma, iqr_val / 1.34);
    if A <= 0, A = sigma; end
    if A <= 0, A = h_min; end
    h = 0.9 * A * n^(-1/5);
    h = max(h, h_min);

    vals_reflected = [vals; -vals; 2 - vals];   % reflect at 0 and at 1

    f = zeros(size(xi));
    two_pi_sqrt = sqrt(2 * pi);
    for k = 1:numel(xi)
        u = (xi(k) - vals_reflected) / h;
        f(k) = sum(exp(-0.5 * u.^2)) / (two_pi_sqrt * h * n);
    end
end

% ----------------------------------------------------------------
%  manual_ecdf -- exact empirical CDF (sorted values vs. rank/n).
% ----------------------------------------------------------------
function [xs, ys] = manual_ecdf(vals)
    xs = sort(vals(:));
    n  = numel(xs);
    ys = (1:n)' / n;
end