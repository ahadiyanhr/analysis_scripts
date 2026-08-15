%% ================================================================
%  POOLED VELOCITY MAGNITUDE DISTRIBUTIONS  (all pixels, no masking)
%  --- PNAS PUBLICATION STYLING VERSION ---
%
%  Same architecture as the shear-stress-at-proximate-biomass script:
%    - Experiment types are derived automatically from the LAST
%      FOLDER NAME of each path in Section 1 (see Section 2), not
%      hardcoded 'cP' / 'cQ_high' / 'cQ_low' strings.
%    - Legend label = the folder's name, exactly as named on disk;
%      legends use 'Interpreter','none' so an underscore in a folder
%      name (e.g. "cQ_low") displays literally, never as a subscript.
%    - Internally, a sanitized version of the folder name (via
%      matlab.lang.makeValidName) is used as the struct field / map
%      key, since raw folder names may contain invalid characters.
%
%  KEY DIFFERENCE vs. the shear-stress version:
%    NO proximity mask, NO high-shear threshold, NO biomass file is
%    read at all. Every non-NaN pixel of the velocity magnitude
%    field |U| = sqrt(Ufx^2 + Ufy^2), from every matched timepoint,
%    is pooled into that experiment type's sample.
%
%  Produces (PNG + vector PDF for each):
%    1) pdf_velocity_pooled_across_types
%         Pooled (all timepoints, all pixels) empirical PDF of
%         velocity magnitude, one curve per experiment type.
%    2) cdf_velocity_pooled_across_types
%         Pooled empirical CDF, same x-axis convention.
%    3) pdf_velocity_normalized_across_types
%    4) cdf_velocity_normalized_across_types
%    5) variance_velocity_vs_time_across_types
%
%  NOTE ON ZERO-VELOCITY PIXELS:
%    When pdf_log_scale = true (recommended), x = 0 cannot be placed
%    on a log axis, so pixels with |U| == 0 are excluded from the
%    pooled sample used for the PDF/CDF (the script reports how many
%    were dropped, per type). Set pdf_log_scale = false to include
%    them on a linear axis instead.
% ================================================================

%% ================================================================
%  SECTION 1 — USER INPUT
% ================================================================

folder_cP      = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cP';
folder_cQ_high = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_high';
folder_cQ_low  = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_low';
folder_plots   = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\pooled_velocity_PDF_CDF';

% PDF parameters
pdf_n_bins    = 60;      % number of histogram bins for the empirical PDF
pdf_log_scale = true;    % true = equal-width bins in log10 space (recommended)

% PNG resolution
png_dpi = 150;

% ---- PDF plot: bottom-left inset (zoomed close-up) ----
%  Set inset_on = false to skip the inset entirely.
%  inset_xlim / inset_ylim define the zoomed data range (m/s / (m/s)^-1).
%  inset_position = [left bottom width height], normalised to the
%  parent axes' position (0-1), so [0.08 0.08 0.34 0.34] sits in the
%  bottom-left corner of the main PDF plot.
inset_on       = true;
inset_xlim     = [1e-6 1e-3];   % [lo hi] in m/s — EDIT to the region you want to zoom into
inset_ylim     = [0 2.2e4];            % [] = auto-fit to data within inset_xlim; or set [lo hi] manually
inset_position = [0.08 0.08 0.34 0.34];

% ---- Same inset, for the NORMALIZED PDF plot (Section 6) --------
%  x-axis here is dimensionless (|U| / <U>_type), so the zoom window
%  is specified in normalized units, not m/s.
inset_on_norm       = true;
inset_xlim_norm     = [1e-2 1];   % [lo hi], dimensionless — EDIT to the region you want to zoom into
inset_ylim_norm     = [1e-1 4];            % [] = auto-fit to data within inset_xlim_norm; or set [lo hi] manually
inset_position_norm = [0.08 0.08 0.34 0.34];

% ---- Variance-vs-time plot (Section 8) --------------------------
%  Per-timepoint variance of |U| (computed across all valid pixels
%  in that single frame), plotted vs. time index, one line per type.
var_time_log_scale = true;   % true = log y-axis (variance often spans orders of magnitude)

% ---- PNAS FIGURE STYLE -------------------------------------------
%  Applied uniformly across all five output figures (main axes AND
%  their insets/variance plot) via style_pnas_axes() at the bottom.
pnas_font            = 'Helvetica';
pnas_fontsize        = 8;     % body text / axis labels / legend
pnas_fontsize_inset  = 7;     % insets are smaller physically, so smaller font
pnas_fontsize_title  = 9;     % kept small; consider omitting titles entirely
                               % for the final submission figure and moving
                               % this text into the manuscript caption instead
pnas_linewidth       = 1.2;   % data line width (was 2.4 — too heavy for print)
pnas_linewidth_inset = 1.0;
pnas_axlinewidth     = 0.75;
pnas_width_cm        = 15;   % PNAS single-column width
pnas_height_cm       = 15;
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

% Fixed style order (position-based): 1st folder = cP-style role,
% 2nd = cQ_high-style role, 3rd = cQ_low-style role, regardless of
% what each folder happens to be named.
%
% Colorblind-safe palette (Okabe-Ito derived): blue / orange /
% bluish-green. Distinguishable by BOTH hue and lightness, so it
% still separates cleanly when converted to grayscale for print —
% a PNAS figure requirement, and safer than the previous red/blue
% pairing which can read ambiguously for red-green color vision
% deficiencies.
STYLE_COLORS = {[0.00 0.45 0.70], ...   % blue          (cP-style role)
                [0.90 0.60 0.00], ...   % orange        (cQ_high-style role)
                [0.00 0.62 0.45]};      % bluish-green  (cQ_low-style role)
STYLE_LINES  = {'-',              '-',               '--'};

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

% pool_vec.(type) = pooled vector of |U| [m/s], concatenated across
% ALL timepoints and ALL matched files for that type, every non-NaN
% pixel (no proximity mask, no threshold)
pool_vec = struct();
for k = 1:numel(types)
    pool_vec.(types{k}) = [];
end

% time_num.(type)/var_time.(type) = per-timepoint numeric time index
% and variance of |U| across that single frame's valid pixels, one
% entry per matched timepoint (used by the Section 8 variance plot)
time_num = struct();
var_time = struct();
for k = 1:numel(types)
    time_num.(types{k}) = [];
    var_time.(types{k}) = [];
end

%% ================================================================
%  SECTION 3 — BATCH LOOP  (compute |U|, pool by type, no masking)
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

    vx_files = names_all(startsWith_ci(names_all, 'Ufx'));
    vy_files = names_all(startsWith_ci(names_all, 'Ufy'));

    fprintf('  Found: %d Ufx | %d Ufy files\n', numel(vx_files), numel(vy_files));

    if isempty(vx_files)
        warning('No Ufx files found in %s', gfolder); continue;
    end

    tokens = cellfun(@extract_time_token, vx_files, 'UniformOutput', false);
    tokens = tokens(~cellfun(@isempty, tokens));
    fprintf('  Tokens: %s\n', strjoin(tokens, ', '));

    for ti = 1:numel(tokens)

        token = tokens{ti};

        vx_name = match_by_token(vx_files, token);
        vy_name = match_by_token(vy_files, token);

        if isempty(vx_name)
            fprintf('  [SKIP %s] no Ufx file\n', token); continue;
        end
        if isempty(vy_name)
            fprintf('  [SKIP %s] no Ufy file\n', token); continue;
        end

        % ---- Load + compute velocity magnitude ----------------------
        Vx = load_first_var(fullfile(gfolder, vx_name));
        Vy = load_first_var(fullfile(gfolder, vy_name));
        U  = sqrt(Vx.^2 + Vy.^2);

        % ---- Pool ALL non-NaN pixels, no mask of any kind ------------
        U_valid = U(~isnan(U));
        pool_vec.(gtype) = [pool_vec.(gtype); U_valid(:)];

        % ---- Track this frame's own variance vs. time (Section 8) ----
        t_val = str2double(regexp(token, '\d+', 'match', 'once'));
        time_num.(gtype) = [time_num.(gtype); t_val];
        var_time.(gtype) = [var_time.(gtype); var(U_valid)];

        fprintf('  --> %s  |  n_valid = %d px\n', token, numel(U_valid));

    end % token loop
end % group loop

types_present = types(cellfun(@(t) numel(pool_vec.(t)) >= 5, types));
if isempty(types_present)
    error('No data collected. Check folder paths and file naming.');
end

% ---- Report zero-velocity pixel counts (excluded when log scale) ----
if pdf_log_scale
    for k = 1:numel(types_present)
        tp = types_present{k};
        n_zero = sum(pool_vec.(tp) <= 0);
        n_total = numel(pool_vec.(tp));
        fprintf('  %-20s  %d of %d pixels are zero/negative and will be excluded (log-scale PDF/CDF)\n', ...
            type_labels(tp), n_zero, n_total);
    end
end

% ---- 1st / 99th percentile per type, pooled across all timepoints ----
%  Computed directly from the sorted sample (same convention as
%  empirical_cdf: F(x_i) = i/n), NOT via MATLAB's prctile(), so the
%  percentile marked on the plot corresponds exactly to a point on
%  the plotted empirical CDF rather than an interpolated value.
pct_lo = struct();  % 1st percentile (m/s) per type
pct_hi = struct();  % 99th percentile (m/s) per type
for k = 1:numel(types_present)
    tp = types_present{k};
    if pdf_log_scale
        v_sorted = sort(pool_vec.(tp)(isfinite(pool_vec.(tp)) & pool_vec.(tp) > 0));
    else
        v_sorted = sort(pool_vec.(tp)(isfinite(pool_vec.(tp)) & pool_vec.(tp) >= 0));
    end
    n = numel(v_sorted);
    idx_lo = max(1, round(0.01 * n));
    idx_hi = max(1, round(0.99 * n));
    pct_lo.(tp) = v_sorted(idx_lo);
    pct_hi.(tp) = v_sorted(idx_hi);
    fprintf('  %-20s  1st pct = %.4g m/s | 99th pct = %.4g m/s\n', type_labels(tp), pct_lo.(tp), pct_hi.(tp));
end

%% ================================================================
%  SECTION 4 — PLOT: Pooled PDF across types (velocity, m/s)
% ================================================================
fprintf('\nGenerating pooled velocity PDF plot ...\n');

fig_ct = figure('Position',[0 0 860 540]);
ax_ct  = axes(fig_ct); hold(ax_ct,'on');
h_ct   = gobjects(0);
lbl_ct = {};
pdf_curve = struct();   % pdf_curve.(type) = [xi_g(:), fi_g(:)], reused by the inset below

for k = 1:numel(types_present)
    tp     = types_present{k};
    v_pool = pool_vec.(tp);

    [xi_g, fi_g] = pdf_empirical(v_pool, pdf_n_bins, pdf_log_scale);
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
xlabel(ax_ct, 'Velocity magnitude  |U|  (m s^{-1})', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
ylabel(ax_ct, 'Probability density  ((m s^{-1})^{-1})', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
title(ax_ct, 'PDF of Velocity Magnitude  —  All Pixels Pooled by Type', ...
    'FontSize', pnas_fontsize_title, 'FontWeight', 'bold', 'FontName', pnas_font);

% ---- 1st / 99th percentile markers (dashed vertical lines, per type) ----
% yl_ct = ylim(ax_ct);
% for k = 1:numel(types_present)
%     tp = types_present{k};
%     plot(ax_ct, [pct_lo.(tp) pct_lo.(tp)], yl_ct, ':', ...
%         'Color', clr(tp), 'LineWidth', 1.0, 'HandleVisibility', 'off');
%     plot(ax_ct, [pct_hi.(tp) pct_hi.(tp)], yl_ct, ':', ...
%         'Color', clr(tp), 'LineWidth', 1.0, 'HandleVisibility', 'off');
% end
% ylim(ax_ct, yl_ct);
% 
% legend(ax_ct, h_ct, lbl_ct, 'Location','northeast', ...
%     'FontSize', pnas_fontsize, 'FontName', pnas_font, 'Box','off', 'Interpreter','none');
% style_pnas_axes(ax_ct, pnas_font, pnas_fontsize, pnas_axlinewidth);
% hold(ax_ct,'off');

% ---- Bottom-left inset: zoomed close-up on [inset_xlim, inset_ylim] ----
if inset_on
    if isempty(inset_ylim)
        rect_ylim = ylim(ax_ct);   % fall back to full y-range if auto
    else
        rect_ylim = inset_ylim;
    end
    rectangle(ax_ct, 'Position', ...
        [inset_xlim(1), rect_ylim(1), diff(inset_xlim), diff(rect_ylim)], ...
        'EdgeColor', [0.3 0.3 0.3], 'LineStyle', '-', 'LineWidth', 0.75);

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

fpath_ct = fullfile(folder_plots, 'pdf_velocity_pooled_across_types');
save_png(fig_ct, fpath_ct, png_dpi, pnas_width_cm, pnas_height_cm, save_pdf_vector);
fprintf('  Saved: pdf_velocity_pooled_across_types.png/.pdf\n');

%% ================================================================
%  SECTION 5 — PLOT: Pooled CDF across types (velocity, m/s)
%
%  Empirical CDF computed directly from the pooled |U| values for
%  each type (no binning): sort values ascending, F(x_i) = i/n.
%  Same x-axis convention (log scale) as the PDF plot for direct
%  visual comparison.
% ================================================================
fprintf('Generating pooled velocity CDF plot ...\n');

fig_cdf = figure('Position',[0 0 860 540]);
ax_cdf  = axes(fig_cdf); hold(ax_cdf,'on');
h_cdf   = gobjects(0);
lbl_cdf = {};

for k = 1:numel(types_present)
    tp     = types_present{k};
    v_pool = pool_vec.(tp);

    [xs, Fs] = empirical_cdf(v_pool, pdf_log_scale);
    h = plot(ax_cdf, xs, Fs, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', pnas_linewidth, ...
        'DisplayName', type_labels(tp));
    h_cdf(end+1)   = h;   %#ok<AGROW>
    lbl_cdf{end+1} = type_labels(tp); %#ok<AGROW>
end

if pdf_log_scale
    set(ax_cdf, 'XScale', 'log');
end
xlabel(ax_cdf, 'Velocity magnitude  |U|  (m s^{-1})', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
ylabel(ax_cdf, 'Cumulative probability', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
ylim(ax_cdf, [0 1]);
title(ax_cdf, 'CDF of Velocity Magnitude  —  All Pixels Pooled by Type', ...
    'FontSize', pnas_fontsize_title, 'FontWeight', 'bold', 'FontName', pnas_font);

% ---- 1st / 99th percentile markers (dashed vertical lines, per type) ----
yl_cdf = ylim(ax_cdf);
for k = 1:numel(types_present)
    tp = types_present{k};
    plot(ax_cdf, [pct_lo.(tp) pct_lo.(tp)], yl_cdf, ':', ...
        'Color', clr(tp), 'LineWidth', 1.0, 'HandleVisibility', 'off');
    plot(ax_cdf, [pct_hi.(tp) pct_hi.(tp)], yl_cdf, ':', ...
        'Color', clr(tp), 'LineWidth', 1.0, 'HandleVisibility', 'off');
end
ylim(ax_cdf, yl_cdf);

legend(ax_cdf, h_cdf, lbl_cdf, 'Location','best', ...
    'FontSize', pnas_fontsize, 'FontName', pnas_font, 'Box','off', 'Interpreter','none');
style_pnas_axes(ax_cdf, pnas_font, pnas_fontsize, pnas_axlinewidth);
hold(ax_cdf,'off');

fpath_cdf = fullfile(folder_plots, 'cdf_velocity_pooled_across_types');
save_png(fig_cdf, fpath_cdf, png_dpi, pnas_width_cm, pnas_height_cm, save_pdf_vector);
fprintf('  Saved: cdf_velocity_pooled_across_types.png/.pdf\n');

%% ================================================================
%  SECTION 6 — PLOT: Pooled PDF of NORMALIZED velocity across types
%
%  Each type's pooled |U| values are normalized by that SAME type's
%  own pooled mean (|U| / <U>_type), so the x-axis is dimensionless.
%  This puts all three types on a common scale regardless of their
%  absolute velocity magnitude, making it easy to compare the SHAPE
%  of the distribution (spread, tail behavior) independent of the
%  overall flow rate. A dotted vertical line at x = 1 marks each
%  type's own mean.
% ================================================================
fprintf('\nGenerating pooled NORMALIZED velocity PDF plot ...\n');

norm_vec  = struct();   % norm_vec.(type) = pool_vec.(type) / mean(pool_vec.(type))
mean_type = struct();   % mean_type.(type) = that type's own pooled mean |U| (m/s)

for k = 1:numel(types_present)
    tp = types_present{k};
    if pdf_log_scale
        v = pool_vec.(tp)(isfinite(pool_vec.(tp)) & pool_vec.(tp) > 0);
    else
        v = pool_vec.(tp)(isfinite(pool_vec.(tp)) & pool_vec.(tp) >= 0);
    end
    mean_type.(tp) = mean(v);
    norm_vec.(tp)  = v / mean_type.(tp);
    fprintf('  %-20s  <U> = %.4g m/s  (used to normalize this type''s x-axis)\n', ...
        type_labels(tp), mean_type.(tp));
end

fig_npdf = figure('Position',[0 0 860 540]);
ax_npdf  = axes(fig_npdf); hold(ax_npdf,'on');
h_npdf   = gobjects(0);
lbl_npdf = {};
pdf_curve_norm = struct();   % pdf_curve_norm.(type) = [xi_n(:), fi_n(:)], reused by the inset below

for k = 1:numel(types_present)
    tp   = types_present{k};
    v_nn = norm_vec.(tp);

    [xi_n, fi_n] = pdf_empirical(v_nn, pdf_n_bins, pdf_log_scale);
    pdf_curve_norm.(tp) = [xi_n(:), fi_n(:)];
    h = plot(ax_npdf, xi_n, fi_n, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', pnas_linewidth, ...
        'DisplayName', type_labels(tp));
    h_npdf(end+1)   = h;   %#ok<AGROW>
    lbl_npdf{end+1} = type_labels(tp); %#ok<AGROW>
end

if pdf_log_scale
    set(ax_npdf, 'XScale', 'log');
    set(ax_npdf, 'YScale', 'log');
end
xlabel(ax_npdf, 'Normalized velocity magnitude  |U| / \langleU\rangle_{type}  (dimensionless)', ...
    'FontSize', pnas_fontsize, 'FontName', pnas_font);
ylabel(ax_npdf, 'Probability density  (dimensionless^{-1})', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
title(ax_npdf, 'PDF of Normalized Velocity Magnitude  —  Pooled by Type, Normalized by Own Mean', ...
    'FontSize', pnas_fontsize_title, 'FontWeight', 'bold', 'FontName', pnas_font);

legend(ax_npdf, h_npdf, lbl_npdf, 'Location','northeast', ...
    'FontSize', pnas_fontsize, 'FontName', pnas_font, 'Box','off', 'Interpreter','none');
% xline(ax_npdf, 1, 'k:', 'LineWidth', 1.0, 'HandleVisibility', 'off');
style_pnas_axes(ax_npdf, pnas_font, pnas_fontsize, pnas_axlinewidth);

% ---- Bottom-left inset: zoomed close-up on [inset_xlim_norm, inset_ylim_norm] ----
if inset_on_norm
    if isempty(inset_ylim_norm)
        rect_ylim_norm = ylim(ax_npdf);   % fall back to full y-range if auto
    else
        rect_ylim_norm = inset_ylim_norm;
    end
    rectangle(ax_npdf, 'Position', ...
        [inset_xlim_norm(1), rect_ylim_norm(1), diff(inset_xlim_norm), diff(rect_ylim_norm)], ...
        'EdgeColor', [0.3 0.3 0.3], 'LineStyle', '-', 'LineWidth', 0.75);

    ax_pos_n    = get(ax_npdf, 'Position');
    inset_abs_n = [ax_pos_n(1) + inset_position_norm(1) * ax_pos_n(3), ...
                   ax_pos_n(2) + inset_position_norm(2) * ax_pos_n(4), ...
                   inset_position_norm(3) * ax_pos_n(3), ...
                   inset_position_norm(4) * ax_pos_n(4)];

    ax_inset_n = axes(fig_npdf, 'Position', inset_abs_n); hold(ax_inset_n, 'on');
    for k = 1:numel(types_present)
        tp   = types_present{k};
        curv = pdf_curve_norm.(tp);
        plot(ax_inset_n, curv(:,1), curv(:,2), lsc(tp), ...
            'Color', clr(tp), 'LineWidth', pnas_linewidth_inset, 'HandleVisibility', 'off');
    end
    % xline(ax_inset_n, 1, 'k:', 'LineWidth', 0.75, 'HandleVisibility', 'off');
    xlim(ax_inset_n, inset_xlim_norm);
    if ~isempty(inset_ylim_norm)
        ylim(ax_inset_n, inset_ylim_norm);
    end
    if pdf_log_scale
        set(ax_inset_n, 'XScale', 'log');
    end
    style_pnas_axes(ax_inset_n, pnas_font, pnas_fontsize_inset, pnas_axlinewidth * 0.85);
    ax_inset_n.Box = 'on';   % insets keep a full box border to read as a distinct panel
    hold(ax_inset_n, 'off');
end

hold(ax_npdf,'off');

fpath_npdf = fullfile(folder_plots, 'pdf_velocity_normalized_across_types');
save_png(fig_npdf, fpath_npdf, png_dpi, pnas_width_cm, pnas_height_cm, save_pdf_vector);
fprintf('  Saved: pdf_velocity_normalized_across_types.png/.pdf\n');

%% ================================================================
%  SECTION 7 — PLOT: Pooled CDF of NORMALIZED velocity across types
%
%  Same normalization as Section 6 (|U| / <U>_type), empirical CDF
%  (no binning): sort ascending, F(x_i) = i/n. Same dotted line at
%  x = 1 marking each type's own mean.
% ================================================================
fprintf('Generating pooled NORMALIZED velocity CDF plot ...\n');

fig_ncdf = figure('Position',[0 0 860 540]);
ax_ncdf  = axes(fig_ncdf); hold(ax_ncdf,'on');
h_ncdf   = gobjects(0);
lbl_ncdf = {};

for k = 1:numel(types_present)
    tp   = types_present{k};
    v_nn = norm_vec.(tp);

    [xs, Fs] = empirical_cdf(v_nn, pdf_log_scale);
    h = plot(ax_ncdf, xs, Fs, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', pnas_linewidth, ...
        'DisplayName', type_labels(tp));
    h_ncdf(end+1)   = h;   %#ok<AGROW>
    lbl_ncdf{end+1} = type_labels(tp); %#ok<AGROW>
end

if pdf_log_scale
    set(ax_ncdf, 'XScale', 'log');
end
xlabel(ax_ncdf, 'Normalized velocity magnitude  |U| / \langleU\rangle_{type}  (dimensionless)', ...
    'FontSize', pnas_fontsize, 'FontName', pnas_font);
ylabel(ax_ncdf, 'Cumulative probability', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
ylim(ax_ncdf, [0 1]);
title(ax_ncdf, 'CDF of Normalized Velocity Magnitude  —  Pooled by Type, Normalized by Own Mean', ...
    'FontSize', pnas_fontsize_title, 'FontWeight', 'bold', 'FontName', pnas_font);

legend(ax_ncdf, h_ncdf, lbl_ncdf, 'Location','best', ...
    'FontSize', pnas_fontsize, 'FontName', pnas_font, 'Box','off', 'Interpreter','none');
% xline(ax_ncdf, 1, 'k:', 'LineWidth', 1.0, 'HandleVisibility', 'off');
style_pnas_axes(ax_ncdf, pnas_font, pnas_fontsize, pnas_axlinewidth);
hold(ax_ncdf,'off');

fpath_ncdf = fullfile(folder_plots, 'cdf_velocity_normalized_across_types');
save_png(fig_ncdf, fpath_ncdf, png_dpi, pnas_width_cm, pnas_height_cm, save_pdf_vector);
fprintf('  Saved: cdf_velocity_normalized_across_types.png/.pdf\n');

%% ================================================================
%  SECTION 8 — PLOT: Variance of velocity vs. timepoint, across types
%
%  For each type, at each matched timepoint, the variance of |U|
%  is computed across that single frame's valid pixels (this is
%  DIFFERENT from the pooled-sample statistics above, which mix all
%  timepoints together). Plotting these per-frame variances against
%  time index, one line per type, shows whether a type's flow field
%  becomes more or less heterogeneous over the course of the
%  experiment, and lets the three types be compared directly.
% ================================================================
fprintf('\nGenerating velocity-variance-vs-time plot ...\n');

fig_var = figure('Position',[0 0 860 540]);
ax_var  = axes(fig_var); hold(ax_var,'on');
h_var   = gobjects(0);
lbl_var = {};

for k = 1:numel(types_present)
    tp = types_present{k};

    t_raw = time_num.(tp);
    v_raw = var_time.(tp);

    % sort by time index so lines are drawn left-to-right correctly
    [t_sorted, sort_idx] = sort(t_raw);
    v_sorted = v_raw(sort_idx);

    h = plot(ax_var, t_sorted, v_sorted, lsc(tp), ...
        'Color', clr(tp), 'LineWidth', pnas_linewidth, 'Marker', 'o', ...
        'MarkerSize', 3.5, 'MarkerFaceColor', clr(tp), 'MarkerEdgeColor', 'none', ...
        'DisplayName', type_labels(tp));
    h_var(end+1)   = h;   %#ok<AGROW>
    lbl_var{end+1} = type_labels(tp); %#ok<AGROW>
end

if var_time_log_scale
    set(ax_var, 'YScale', 'log');
end
xlabel(ax_var, 'Time index (frame token number)', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
ylabel(ax_var, 'Variance of  |U|  across frame  ((m s^{-1})^2)', 'FontSize', pnas_fontsize, 'FontName', pnas_font);
title(ax_var, 'Velocity-Magnitude Variance vs. Time  —  Compared Across Types', ...
    'FontSize', pnas_fontsize_title, 'FontWeight', 'bold', 'FontName', pnas_font);

legend(ax_var, h_var, lbl_var, 'Location','best', ...
    'FontSize', pnas_fontsize, 'FontName', pnas_font, 'Box','off', 'Interpreter','none');
style_pnas_axes(ax_var, pnas_font, pnas_fontsize, pnas_axlinewidth);
hold(ax_var,'off');

fpath_var = fullfile(folder_plots, 'variance_velocity_vs_time_across_types');
save_png(fig_var, fpath_var, png_dpi, pnas_width_cm, pnas_height_cm, save_pdf_vector);
fprintf('  Saved: variance_velocity_vs_time_across_types.png/.pdf\n');

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
%  avoids resampling artifacts at print resolution). When width_cm
%  is supplied, the figure is resized to PNAS's physical page
%  dimensions (default: 8.7 cm single-column width) before export,
%  so what you see in the PNG matches the final print size.
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
%  Empirical PDF via normalised histogram (same method as the
%  shear-stress reference script's pdf_shear, renamed generic here
%  since it is now used for velocity, not shear).
%
%  When log_scale = true:
%    Zero/negative values are excluded (log undefined at 0). Bins
%    are equally spaced in log10(v) space; density is computed per
%    unit log10(v), then converted to density per (m/s) via the
%    Jacobian f_lin(x) = f_log(log10 x) / (x * ln10), so it
%    integrates to 1 on the linear m/s axis.
%  When log_scale = false:
%    Standard equal-width bins in m/s; zero values ARE included.
% ----------------------------------------------------------------
function [xi, fi] = pdf_empirical(v, n_bins, log_scale)
    if log_scale
        v = v(isfinite(v) & v > 0);
    else
        v = v(isfinite(v) & v >= 0);
    end
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
%  When log_scale = true, zero/negative values are excluded (can't
%  be placed on a log x-axis); when false, zeros are included.
% ----------------------------------------------------------------
function [xs, Fs] = empirical_cdf(v, log_scale)
    if log_scale
        v = v(isfinite(v) & v > 0);
    else
        v = v(isfinite(v) & v >= 0);
    end
    v = sort(v);
    n = numel(v);
    if n < 2, xs = []; Fs = []; return; end
    xs = v;
    Fs = (1:n)' / n;
end