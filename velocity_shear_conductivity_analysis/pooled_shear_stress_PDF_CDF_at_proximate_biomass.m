%% ================================================================
%  POOLED SHEAR-STRESS DISTRIBUTIONS AT PROXIMATE BIOMASS
%  Experiment types are now derived automatically from the LAST
%  FOLDER NAME of each path in Section 1 (see Section 2), rather
%  than hardcoded 'cP' / 'cQ_high' / 'cQ_low' strings. This means:
%    - The plotted legend label = the folder's name, exactly as
%      named on disk (spaces and underscores both handled correctly;
%      legends use 'Interpreter','none' so an underscore in a folder
%      name like "cQ_low" displays literally and is never treated as
%      a LaTeX/tex subscript).
%    - Internally, a sanitized version of the folder name (via
%      matlab.lang.makeValidName) is used as the MATLAB struct field
%      / map key, since raw folder names may contain characters that
%      are not valid identifiers (e.g. spaces).
%
%  This is a trimmed-down version of the original batch processor.
%  It computes ONLY what is needed to produce:
%
%    1) pdf_shear_proximate_across_types.png
%         Pooled (all timepoints) empirical PDF of shear stress at
%         proximate biomass, one curve per experiment type, absolute
%         x-axis in Pa.
%
%    2) cdf_shear_proximate_across_types.png
%         Pooled (all timepoints) empirical CDF of shear stress at
%         proximate biomass, one curve per experiment type, same
%         x-axis convention (log-scale if pdf_log_scale = true).
%
%  No per-timepoint PNGs, no per-type PDF figure, no normalised PDF,
%  no bubble charts, no ratio table — all removed since not needed
%  for these two figures.
% ================================================================

%% ================================================================
%  SECTION 1 — USER INPUT
% ================================================================

folder_cP      = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cP';
folder_cQ_high = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_high';
folder_cQ_low  = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_low';
folder_plots   = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\pooled_shear_stress_PDF_CDF_at_proximate_biomass';

% Shear color axis (only used to define the high-shear threshold, per file)
clim_tau = [];   % [] = auto (1st-99th percentile per file), [lo hi] = fixed

% Proximity parameters
proximity_px   = 2;     % biomass pixels within this dist of high-shear -> proximate
high_shear_pct = 0.5;   % top fraction of shear range defined as "high shear"

% PDF parameters
pdf_n_bins    = 60;      % number of histogram bins for the empirical PDF
pdf_log_scale = true;    % true = equal-width bins in log10 space (recommended)

% PNG resolution
png_dpi = 150;

% ---- PDF plot: bottom-left inset (zoomed close-up) ----
%  Set inset_on = false to skip the inset entirely.
%  inset_xlim / inset_ylim define the zoomed data range (Pa / Pa^-1).
%  inset_position = [left bottom width height], normalised to the
%  parent axes' position (0-1), so [0.08 0.08 0.34 0.34] sits in the
%  bottom-left corner of the main PDF plot.
inset_on       = true;
inset_xlim     = [0.00025 0.1];    % [lo hi] in Pa — EDIT to the region you want to zoom into
inset_ylim     = [0 140];            % [] = auto-fit to data within inset_xlim; or set [lo hi] manually
inset_position = [0.08 0.08 0.34 0.34];



% ---- PNAS FIGURE STYLE -------------------------------------------
%  Applied uniformly across both output figures (main axes AND their
%  insets) via style_pnas_axes() at the bottom.
pnas_font            = 'Helvetica';
pnas_fontsize        = 8;     % body text / axis labels / legend
pnas_fontsize_inset  = 7;     % insets are smaller physically, so smaller font
pnas_fontsize_title  = 9;     % kept small; consider omitting titles entirely
                               % for the final submission figure and moving
                               % this text into the manuscript caption instead
pnas_linewidth       = 1.2;   % data line width (was 2.4 — too heavy for print)
pnas_linewidth_inset = 1.0;
pnas_axlinewidth     = 0.75;
save_pdf_vector      = true;  % also export a vector .pdf alongside .png
%% ================================================================
%  SECTION 2 — SETUP
%
%  Experiment type identifiers and display labels are derived here
%  from each folder path's LAST FOLDER NAME (e.g. a path ending in
%  '...\Constant low Flow' or '...\cQ_low' both work).
% ================================================================

if ~exist(folder_plots, 'dir'), mkdir(folder_plots); end
fprintf('Output folder: %s\n', folder_plots);

folder_paths = {folder_cP, folder_cQ_high, folder_cQ_low};

% Colorblind-safe palette (Okabe-Ito derived): blue / orange /
% bluish-green. Distinguishable by BOTH hue and lightness, so it
% still separates cleanly when converted to grayscale for print.
STYLE_COLORS = {[0.00 0.45 0.70], ...   % blue          (cP-style role)
                [0.90 0.60 0.00], ...   % orange        (cQ_high-style role)
                [0.00 0.62 0.45]};      % bluish-green  (cQ_low-style role)
STYLE_LINES  = {'-',              '--',               '-.'};

groups = struct('folder', {}, 'type', {}, 'label', {});
clr = containers.Map();   % type_id -> color
lsc = containers.Map();   % type_id -> linestyle

for g = 1:numel(folder_paths)
    f = folder_paths{g};
    if ~exist(f, 'dir')
        error('Folder not found: %s\nCheck paths in Section 1.', f);
    end

    % ---- Derive type identifier + display label from folder name ----
    f_clean = f;
    if endsWith(f_clean, filesep), f_clean = f_clean(1:end-1); end
    [~, folder_name] = fileparts(f_clean);   % last folder name, e.g. 'Constant low Flow' or 'cQ_low'

    type_id = matlab.lang.makeValidName(folder_name);   % safe struct/map key
    % (makeValidName replaces spaces/invalid chars with '_' and
    %  prepends 'x' if the name would otherwise start with a digit)

    groups(g).folder = f;            %#ok<SAGROW>
    groups(g).type    = type_id;      %#ok<SAGROW>
    groups(g).label   = folder_name;  %#ok<SAGROW>  % raw name, used for legend text

    clr(type_id) = STYLE_COLORS{g};
    lsc(type_id) = STYLE_LINES{g};

    fprintf('  Folder: %s  ->  type_id = %s  |  label = %s\n', f, type_id, folder_name);
end

types = {groups.type};

% type_id -> display label (raw folder name). Legends are drawn with
% 'Interpreter','none' throughout, so an underscore in the folder name
% (e.g. "cQ_low") is shown literally rather than triggering subscript
% formatting.
type_labels = containers.Map({groups.type}, {groups.label});

% pool_vec.(type) = pooled vector of tau [Pa] at proximate biomass,
% concatenated across ALL timepoints and ALL matched files for that type
pool_vec = struct();
for k = 1:numel(types)
    pool_vec.(types{k}) = [];
end

%% ================================================================
%  SECTION 3 — BATCH LOOP  (compute tau_prox, pool by type only)
% ================================================================

for g = 1:numel(groups)

    gtype   = groups(g).type;
    gfolder = groups(g).folder;

    fprintf('\n%s\n  Group: %s  (%s)\n%s\n', repmat('=',1,60), groups(g).label, gtype, repmat('=',1,60));

    all_files = dir(fullfile(gfolder, '*.mat'));
    if isempty(all_files)
        warning('No .mat files in: %s', gfolder); continue;
    end
    names_all = {all_files.name};

    shear_files = names_all(startsWith_ci(names_all, 'shear'));
    bio_files   = names_all(startsWith_ci(names_all, 'biomass'));

    fprintf('  Found: %d shear | %d biomass files\n', numel(shear_files), numel(bio_files));

    tokens = cellfun(@extract_time_token, shear_files, 'UniformOutput', false);
    tokens = tokens(~cellfun(@isempty, tokens));
    fprintf('  Tokens: %s\n', strjoin(tokens, ', '));

    for ti = 1:numel(tokens)

        token = tokens{ti};

        shear_name = match_by_token(shear_files, token);
        bio_name   = match_by_token(bio_files,   token);

        if isempty(shear_name)
            fprintf('  [SKIP %s] no shear file\n', token); continue;
        end
        if isempty(bio_name)
            fprintf('  [SKIP %s] no biomass file\n', token); continue;
        end

        % ---- Load --------------------------------------------------
        tau     = abs(load_first_var(fullfile(gfolder, shear_name)));  % Pa
        biomass = load_first_var(fullfile(gfolder, bio_name));

        % ---- Shear color/threshold limits ---------------------------
        if isempty(clim_tau)
            tp_vals = tau(~isnan(tau) & tau > 0);
            clim_t  = [prctile(tp_vals, 1), prctile(tp_vals, 99)];
        else
            clim_t = clim_tau;
        end

        % ---- High-shear mask & distance transform -------------------
        high_shear_thresh = clim_t(1) + high_shear_pct * (clim_t(2) - clim_t(1));
        high_shear_mask   = (tau >= high_shear_thresh) & ~isnan(tau);
        dist_to_highshear = bwdist(high_shear_mask);

        % ---- Biomass masks -------------------------------------------
        bio_all   = (biomass >= 0) & (biomass < 1) & ~isnan(biomass);
        bio_close = bio_all & (dist_to_highshear <= proximity_px);   % proximate

        % ---- Raw shear at proximate biomass, pooled by type ----------
        tau_prox = tau(bio_close & ~isnan(tau) & tau > 0);
        pool_vec.(gtype) = [pool_vec.(gtype); tau_prox(:)];

        fprintf('  --> %s  |  n_prox = %d px\n', token, numel(tau_prox));

    end % token loop
end % group loop

types_present = types(cellfun(@(t) numel(pool_vec.(t)) >= 5, types));
if isempty(types_present)
    error('No data collected. Check folder paths and file naming.');
end

% ---- 1st / 99th percentile per type, pooled across all timepoints ----
%  Computed directly from the sorted sample (same convention as
%  empirical_cdf: F(x_i) = i/n), NOT via MATLAB's prctile(), so the
%  percentile marked on the plot corresponds exactly to a point on
%  the plotted empirical CDF/CCDF rather than an interpolated value.
pct_lo = struct();  % 1st percentile (Pa) per type
pct_hi = struct();  % 99th percentile (Pa) per type
for k = 1:numel(types_present)
    tp = types_present{k};
    v_sorted = sort(pool_vec.(tp)(isfinite(pool_vec.(tp)) & pool_vec.(tp) > 0));
    n = numel(v_sorted);
    idx_lo = max(1, round(0.01 * n));
    idx_hi = max(1, round(0.99 * n));
    pct_lo.(tp) = v_sorted(idx_lo);
    pct_hi.(tp) = v_sorted(idx_hi);
    fprintf('  %-20s  1st pct = %.4g Pa | 99th pct = %.4g Pa\n', type_labels(tp), pct_lo.(tp), pct_hi.(tp));
end

%% ================================================================
%  SECTION 4 — PLOT: Pooled PDF across types (absolute Pa)
% ================================================================
fprintf('\nGenerating pooled PDF plot (absolute Pa) ...\n');

fig_ct = figure('Position',[0 0 620 460]);
set(fig_ct, 'Color', 'w');   % figure background (outside the axes box)

ax_ct  = axes(fig_ct); hold(ax_ct,'on');
h_ct   = gobjects(0);
lbl_ct = {};
pdf_curve = struct();   % pdf_curve.(type) = [xi_g(:), fi_g(:)], reused by the inset below

for k = 1:numel(types_present)
    tp     = types_present{k};
    v_pool = pool_vec.(tp);

    [xi_g, fi_g] = pdf_shear(v_pool, pdf_n_bins, pdf_log_scale);
    pdf_curve.(tp) = [xi_g(:), fi_g(:)];
    h = plot(ax_ct, xi_g, fi_g, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', pnas_linewidth, ...
        'DisplayName', type_labels(tp));
    h_ct(end+1)   = h;   %#ok<AGROW>
    lbl_ct{end+1} = type_labels(tp); %#ok<AGROW>
end

if pdf_log_scale
    set(ax_ct, 'XScale', 'log');
    set(ax_ct, 'YScale', 'log');
end
xlabel(ax_ct, 'Shear stress \tau  (Pa)', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
ylabel(ax_ct, 'Probability density  (Pa^{-1})', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
title(ax_ct, 'PDF of Shear Stress at Proximate Biomass', ...
    'FontSize', pnas_fontsize_title, 'FontWeight', 'bold', 'FontName', pnas_font);

% ---- 1st / 99th percentile markers (per type, same line style as that
%      type's own data curve, so the marker reads as "belonging" to it) ----
yl_ct = ylim(ax_ct);
for k = 1:numel(types_present)
    tp = types_present{k};
    plot(ax_ct, [pct_lo.(tp) pct_lo.(tp)], yl_ct, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', 1.3, 'HandleVisibility', 'off');
    plot(ax_ct, [pct_hi.(tp) pct_hi.(tp)], yl_ct, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', 1.3, 'HandleVisibility', 'off');
end
ylim(ax_ct, yl_ct);

legend(ax_ct, h_ct, lbl_ct, 'Location','northeast', ...
    'FontSize', pnas_fontsize, 'FontName', pnas_font, 'Box','off', 'Interpreter','none');
style_pnas_axes(ax_ct, pnas_font, pnas_fontsize, pnas_axlinewidth);
hold(ax_ct,'off');

% ---- Bottom-left inset: zoomed close-up on [inset_xlim, inset_ylim] ----
%  Re-plots the same pooled curves (from pdf_curve, computed once above)
%  restricted to the zoom window, placed in the bottom-left corner of
%  the main axes. A rectangle on the main plot marks the zoomed region.
if inset_on
    % Rectangle on the main plot showing the zoomed data region
    if isempty(inset_ylim)
        rect_ylim = ylim(ax_ct);   % fall back to full y-range if auto
    else
        rect_ylim = inset_ylim;
    end
    rectangle(ax_ct, 'Position', ...
        [inset_xlim(1), rect_ylim(1), diff(inset_xlim), diff(rect_ylim)], ...
        'EdgeColor', [0.3 0.3 0.3], 'LineStyle', '-', 'LineWidth', 0.75);

    % Convert inset_position (fraction of main axes) to absolute
    % figure-normalised coordinates required by axes('Position', ...)
    ax_pos     = get(ax_ct, 'Position');
    inset_abs  = [ax_pos(1) + inset_position(1) * ax_pos(3), ...
                  ax_pos(2) + inset_position(2) * ax_pos(4), ...
                  inset_position(3) * ax_pos(3), ...
                  inset_position(4) * ax_pos(4)];

    ax_inset = axes(fig_ct, 'Position', inset_abs); hold(ax_inset, 'on');
    for k = 1:numel(types_present)
        tp   = types_present{k};
        curv = pdf_curve.(tp);
        plot(ax_inset, curv(:,1), curv(:,2), lsc(tp), ...
            'Color', clr(tp), 'LineWidth', pnas_linewidth_inset, 'HandleVisibility', 'off');
    end
    xlim(ax_inset, inset_xlim);
    if ~isempty(inset_ylim)
        ylim(ax_inset, inset_ylim);
    end
    if pdf_log_scale
        set(ax_inset, 'XScale', 'log');
    end
    style_pnas_axes(ax_inset, pnas_font, pnas_fontsize_inset, pnas_axlinewidth * 0.85);
    ax_inset.Box = 'on';   % insets keep a full box border to read as a distinct panel
    hold(ax_inset, 'off');
end

fpath_ct = fullfile(folder_plots, 'pdf_shear_proximate_across_types');
save_png(fig_ct, fpath_ct, png_dpi, [], [], save_pdf_vector);
fprintf('  Saved: pdf_shear_proximate_across_types.png/.pdf\n');

%% ================================================================
%  SECTION 5 — PLOT: Pooled CDF across types (absolute Pa)
%
%  Empirical CDF computed directly from the pooled tau values for
%  each type (no binning): sort values ascending, F(x_i) = i/n.
%  Same x-axis convention (log scale) as the PDF plot for direct
%  visual comparison.
% ================================================================
fprintf('Generating pooled CDF plot (absolute Pa) ...\n');

fig_cdf = figure('Position',[0 0 620 460]);
set(fig_cdf, 'Color', 'w');   % figure background (outside the axes box)
% set(ax_cdf,  'Color', 'w');   % axes background (the plot area itself)
ax_cdf  = axes(fig_cdf); hold(ax_cdf,'on');
h_cdf   = gobjects(0);
lbl_cdf = {};

for k = 1:numel(types_present)
    tp     = types_present{k};
    v_pool = pool_vec.(tp);

    [xs, Fs] = empirical_cdf(v_pool);
    h = plot(ax_cdf, xs, Fs, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', 3, ...
        'DisplayName', type_labels(tp));
    h_cdf(end+1)   = h;   %#ok<AGROW>
    lbl_cdf{end+1} = type_labels(tp); %#ok<AGROW>
end

if pdf_log_scale
    set(ax_cdf, 'XScale', 'log');
    % set(ax_cdf, 'YScale', 'log');
end
xlabel(ax_cdf, 'Shear stress \tau  (Pa)');
ylabel(ax_cdf, 'Cumulative probability');
ylim(ax_cdf, [0 1]);
title(ax_cdf, 'CDF of Shear Stress at Proximate Biomass', 'FontWeight', 'bold');

set(ax_cdf, 'FontSize', 13.2, 'FontWeight', 'bold', 'XMinorTick', 'on');

% ---- 1st / 99th percentile markers (per type, same line style as that
%      type's own data curve, so the marker reads as "belonging" to it) ----
yl_cdf = ylim(ax_cdf);
for k = 1:numel(types_present)
    tp = types_present{k};
    plot(ax_cdf, [pct_lo.(tp) pct_lo.(tp)], yl_cdf, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', 1.3, 'HandleVisibility', 'off');
    plot(ax_cdf, [pct_hi.(tp) pct_hi.(tp)], yl_cdf, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', 1.3, 'HandleVisibility', 'off');
end

ylim(ax_cdf, yl_cdf);

legend(ax_cdf, h_cdf, lbl_cdf, 'Location','best','FontSize',14,'Interpreter','none');
xl = xlim(ax_cdf);
exp_lo = floor(log10(xl(1)));
exp_hi = ceil(log10(xl(2)));
set(ax_cdf, 'XTick', 100.^(exp_lo:exp_hi), 'XMinorGrid', 'off');
grid(ax_cdf,'on'); box(ax_cdf,'off'); hold(ax_cdf,'off');

fpath_cdf = fullfile(folder_plots, 'cdf_shear_proximate_across_types.png');
save_png(fig_cdf, fpath_cdf, png_dpi);
fprintf('  Saved: cdf_shear_proximate_across_types.png\n');

%% ================================================================
%  SECTION 6 — PLOT: Pooled complementary CDF across types (absolute Pa)
%
%  CCDF(x) = 1 - CDF(x) = P(tau > x), reusing the same sorted values
%  from empirical_cdf. Plotted with a log y-axis, since CCDFs are
%  typically used to inspect tail behaviour (e.g. power-law vs
%  exponential decay shows up as straight vs curved on log-log /
%  semilog-y axes) — linear y would compress the tail into the
%  bottom of the plot.
% ================================================================
% fprintf('Generating pooled CCDF plot (absolute Pa) ...\n');
% 
% fig_ccdf = figure('Position',[0 0 860 540]);
% ax_ccdf  = axes(fig_ccdf); hold(ax_ccdf,'on');
% h_ccdf   = gobjects(0);
% lbl_ccdf = {};
% 
% for k = 1:numel(types_present)
%     tp     = types_present{k};
%     v_pool = pool_vec.(tp);
% 
%     [xs, Fs]  = empirical_cdf(v_pool);
%     ccdf_vals = 1 - Fs;
% 
%     % Drop the last point where ccdf = 0 (undefined on log scale)
%     keep = ccdf_vals > 0;
%     h = plot(ax_ccdf, xs(keep), ccdf_vals(keep), lsc(tp), ...
%         'Color', clr(tp), 'LineWidth', 2.4, ...
%         'DisplayName', type_labels(tp));
%     h_ccdf(end+1)   = h;   %#ok<AGROW>
%     lbl_ccdf{end+1} = type_labels(tp); %#ok<AGROW>
% end
% 
% % set(ax_ccdf, 'YScale', 'log');
% if pdf_log_scale
%     set(ax_ccdf, 'XScale', 'log');
%     xlabel(ax_ccdf, 'Shear stress \tau  (Pa)', 'FontSize', 12);
% else
%     xlabel(ax_ccdf, 'Shear stress \tau  (Pa)', 'FontSize', 12);
% end
% ylabel(ax_ccdf, 'P(\tau'' > \tau)', 'FontSize', 12);
% title(ax_ccdf, 'Complementary CDF of Shear Stress at Proximate Biomass  —  All Timepoints Pooled by Type', ...
%     'FontSize', 13, 'FontWeight', 'bold');
% legend(ax_ccdf, h_ccdf, lbl_ccdf, 'Location','best','FontSize',10,'Interpreter','none');
% grid(ax_ccdf,'on'); box(ax_ccdf,'off'); hold(ax_ccdf,'off');
% 
% fpath_ccdf = fullfile(folder_plots, 'ccdf_shear_proximate_across_types.png');
% save_png(fig_ccdf, fpath_ccdf, png_dpi);
% fprintf('  Saved: ccdf_shear_proximate_across_types.png\n');

fprintf('\nAll done. Output folder:\n  %s\n\n', folder_plots);

%% ================================================================
%  LOCAL FUNCTIONS
% ================================================================

function mask = startsWith_ci(names, prefix)
    mask = strncmpi(names, prefix, length(prefix));
end

function token = extract_time_token(fname)
    m = regexp(fname, 'T\d+', 'match', 'once');
    if isempty(m), token = ''; else, token = m; end
end

function match = match_by_token(file_list, token)
    match = '';
    for i = 1:numel(file_list)
        if ~isempty(regexp(file_list{i}, token, 'once'))
            match = file_list{i}; return;
        end
    end
end

function out = load_first_var(filepath)
    S = load(filepath); f = fieldnames(S); out = S.(f{1});
end

% ----------------------------------------------------------------
%  Save figure as PNG (raster, for quick viewing) AND, optionally,
%  as a vector PDF (for the actual PNAS submission — vector output
%  avoids resampling artifacts at print resolution). Passing []
%  for width_cm/height_cm (as done above) leaves the figure's
%  current on-screen size untouched.
% ----------------------------------------------------------------
function save_png(fig, fpath_noext, dpi, width_cm, height_cm, save_pdf)
    if nargin < 4, width_cm = []; end
    if nargin < 5, height_cm = []; end
    if nargin < 6, save_pdf = false; end

    if ~isempty(width_cm) && ~isempty(height_cm)
        set(fig, 'Units', 'centimeters', ...
            'Position', [0 0 width_cm height_cm], ...
            'PaperUnits', 'centimeters', ...
            'PaperPosition', [0 0 width_cm height_cm], ...
            'PaperSize', [width_cm height_cm]);
    end

    print(fig, [fpath_noext '.png'], '-dpng', sprintf('-r%d', dpi));

    if save_pdf
        print(fig, [fpath_noext '.pdf'], '-dpdf', '-vector');
    end
end
% ----------------------------------------------------------------
%  Apply consistent PNAS-style formatting to any axes: Helvetica
%  font, outward ticks, thin neutral-gray spines, no box, no grid.
%  Call once per axes (main axes AND each inset) right before saving
%  the figure, so every panel in every output figure looks uniform.
% ----------------------------------------------------------------
function style_pnas_axes(ax, font, fsize, axlinewidth)
    set(ax, 'FontName', font, 'FontSize', fsize, ...
        'TickDir', 'out', 'LineWidth', axlinewidth, ...
        'Box', 'off', 'Layer', 'top');
    ax.XAxis.Color = [0.15 0.15 0.15];
    ax.YAxis.Color = [0.15 0.15 0.15];
    grid(ax, 'off');
end
% ----------------------------------------------------------------
%  Empirical PDF via normalised histogram (same method as original)
%
%  When log_scale = true:
%    Bins are equally spaced in log10(tau) space; density is computed
%    per unit log10(tau), then converted to density per Pa via the
%    Jacobian f_Pa(x) = f_log(log10 x) / (x * ln10), so it integrates
%    to 1 on the linear Pa axis.
%  When log_scale = false:
%    Standard equal-width bins in Pa.
% ----------------------------------------------------------------
function [xi, fi] = pdf_shear(v, n_bins, log_scale)
    v = v(isfinite(v) & v > 0);
    if numel(v) < 2, xi = []; fi = []; return; end
    n = numel(v);

    if log_scale
        u         = log10(v);
        edges_u   = linspace(min(u), max(u), n_bins + 1);
        bw_u      = edges_u(2) - edges_u(1);
        counts    = histcounts(u, edges_u);
        centres_u = 0.5 * (edges_u(1:end-1) + edges_u(2:end));

        f_log  = counts / (n * bw_u);
        xi_all = 10.^centres_u;
        fi_all = f_log ./ (xi_all * log(10));
    else
        edges  = linspace(min(v), max(v), n_bins + 1);
        bw     = edges(2) - edges(1);
        counts = histcounts(v, edges);
        xi_all = 0.5 * (edges(1:end-1) + edges(2:end));
        fi_all = counts / (n * bw);
    end

    keep = counts > 0;
    xi   = xi_all(keep);
    fi   = fi_all(keep);
end

% ----------------------------------------------------------------
%  Empirical CDF: sort values ascending, F(x_i) = i / n.
%  No binning, so this is an exact step-function representation of
%  the pooled sample; plotted as a smooth line since n is large.
% ----------------------------------------------------------------
function [xs, Fs] = empirical_cdf(v)
    v = v(isfinite(v) & v > 0);
    v = sort(v);
    n = numel(v);
    if n < 2, xs = []; Fs = []; return; end
    xs = v;
    Fs = (1:n)' / n;
end
