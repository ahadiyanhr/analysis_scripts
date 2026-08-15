%% ================================================================
%  BIOMASS FLUX MAP + FLUX-RATIO PROFILE BATCH PLOTTER  v1
%  THREE experiment types: cP, cQ_high, cQ_low
%
%  Adapted from the pressure/biomass reactor-map script. Same batch
%  architecture (type x T### time-token matching), but the two panels
%  now show FLOW/FLUX instead of pressure:
%
%    TOP    : width-mean flux ratio profile along the chip length —
%             at every x-position, sum(local speed over biomass px)
%             divided by sum(local speed over pore px) in that same
%             row. This is the "how much flow still gets through the
%             biofilm vs. the open pore" signature, plotted vs x.
%             Plotted on a log y-axis by default (ratios often span
%             >1 order of magnitude), with a dashed reference line at
%             ratio = 1 (biomass carrying as much flux as pore space)
%             AND a second solid reference line at the OVERALL (whole-
%             image, not per-row) biomass:pore flux ratio — the single
%             headline number for that image. The exact totals (sum of
%             speed over all biomass px, all pore px, and their ratio)
%             are also printed in a small text box in the figure corner.
%
%    BOTTOM : 2D map of the porous medium, now colored by LOCAL FLOW
%             SPEED instead of density:
%               - grains      -> flat neutral gray  (unchanged)
%               - pore space  -> muted/desaturated gray-blue ramp
%                                 (present for context, intentionally
%                                 low-contrast so it recedes visually)
%               - biomass     -> vivid "inferno"-style ramp (this is
%                                 the signature reviewers should see
%                                 first: WHERE and HOW MUCH flow is
%                                 still moving through the biofilm)
%
%  FLUX / SPEED DEFINITION
%  ------------------------
%   flux_component (below) selects what "flow" means per pixel:
%     'speed'  -> sqrt(Ufx.^2 + Ufy.^2)   [default, general]
%     'ufx'    -> abs(Ufx)                 [streamwise component only]
%   Consistent with the "flux proxy" convention used elsewhere in this
%   project: for the RATIO we use SUMMED (not mean) speed per row,
%   because pixel area / channel height cancel out of a ratio anyway.
%
%  COLOR SCALE STRATEGY (IMPORTANT FOR CROSS-CONDITION COMPARISON)
%  ------------------------------------------------------------------
%   cQ_high runs at a much higher flow rate than cP / cQ_low, so ONE
%   shared color scale across all three would either clip cQ_high or
%   wash out all the cP/cQ_low detail. Instead, each type is assigned
%   to a SCALE GROUP (scale_group_map, Section 1) — by default
%   cQ_high -> 'high', cP & cQ_low -> 'low' (mirroring the bare-model
%   reference split: 1 uL/min shared by cP/cQ_low vs 12 uL/min for
%   cQ_high). The biomass and pore color scales are each computed ONCE
%   per scale group, pooled across every file in that group (robust
%   percentile clipping, not min/max) — NOT per-image. This means: two
%   PNGs from the SAME scale group are directly color-comparable, while
%   PNGs from DIFFERENT scale groups are each optimized for their own
%   flow regime (and are labeled accordingly on their colorbars, e.g.
%   "[high-flow scale]" vs "[low-flow scale]") rather than falsely
%   implying one universal scale. Set use_global_scale = false to fall
%   back to per-image auto-scaling instead.
%
%  BIOMASS VALUE CONVENTION (unchanged from source data):
%     NaN         -> grain
%     1           -> open pore, no biofilm
%     [0, 0.99]   -> biomass occupancy (density itself is NOT used
%                     here — only used to build the grain/pore/biomass
%                     masks; the color in this script is flow speed)
%
%  FILE MATCHING
%  -------------
%   Three folders (one per type). Within each, files matched by shared
%   T### time token:  biomass*  ,  Ufx_*  ,  Ufy_*
%   (velocity file prefixes are placeholders below — edit
%   velx_prefix / vely_prefix if your PIV files use different names)
% ================================================================

%% ================================================================
%  SECTION 1 — USER INPUT  (only section you need to edit)
% ================================================================

folder_cP      = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cP';
folder_cQ_high = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_high';
folder_cQ_low  = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_low';
folder_plots   = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\flux_biomass_map';

% ---- File-name prefixes (EDIT to match your actual PIV file names) ----
bio_prefix  = 'biomass';   % biomass matrix files (as before)
velx_prefix = 'Ufx';       % x-component of PIV velocity, e.g. Ufx_T003.mat
vely_prefix = 'Ufy';       % y-component of PIV velocity, e.g. Ufy_T003.mat

% Which flow quantity to visualize / ratio:
%   'speed' -> sqrt(Ufx.^2+Ufy.^2)   (default, general flow magnitude)
%   'ufx'   -> abs(Ufx)              (streamwise component only)
flux_component = 'speed';

% Biomass raw-value convention (edit only if the source files change)
pore_val_min = 1.0;   % raw value >= this => open pore, no biofilm

% ---- Global color-scale settings (for cross-condition comparability) ---
use_global_scale   = true;   % false => per-image auto scaling instead
bio_pctile_lo       = 2;      % lower percentile clip, biomass speed
bio_pctile_hi       = 98;     % upper percentile clip, biomass speed
pore_pctile_lo      = 2;      % lower percentile clip, pore speed
pore_pctile_hi      = 98;     % upper percentile clip, pore speed

% ---- Flow-regime scale grouping --------------------------------------
% cQ_high runs at a much higher flow rate than cP / cQ_low. A single
% shared color scale across all three would either wash out cP/cQ_low
% detail or clip cQ_high. Instead, each type is assigned to a scale
% GROUP; all types sharing a group share one colorbar range (computed
% globally within that group, same percentile-clipping logic as above).
% Edit the grouping below if your regimes are organized differently.
scale_group_map = containers.Map( ...
    {'cP',  'cQ_high', 'cQ_low'}, ...
    {'low', 'high',    'low'});

% ---- Top-panel ratio settings ----
ratio_log_scale = true;   % log y-axis (recommended: ratios span decades)

% Smoothing of the along-chip profiles (as a fraction of chip length Nx;
% converted to an odd pixel-window internally). Larger = smoother line.
smooth_frac   = 0.03;   % 3% of chip length
smooth_min_px = 5;

% PNG resolution
png_dpi = 300;   % 300 dpi is PNAS figure standard

%% ================================================================
%  SECTION 2 — SETUP
% ================================================================

if ~exist(folder_plots, 'dir'), mkdir(folder_plots); end
fprintf('Output folder: %s\n', folder_plots);

folder_list = {folder_cP, folder_cQ_high, folder_cQ_low};
for fi = 1:numel(folder_list)
    f = folder_list{fi};
    if ~exist(f, 'dir')
        error('Folder not found: %s\nCheck paths in Section 1.', f);
    end
    mats = dir(fullfile(f, '*.mat'));
    fprintf('  %d .mat files in: %s\n', numel(mats), f);
end

% ---- Colors -------------------------------------------------------
inferno_cmap = make_inferno_cmap(256);     % biomass flux: vivid, high-contrast
pore_cmap    = make_pore_gray_cmap(256);   % pore flux: muted, low-contrast
grain_clr    = [0.55 0.55 0.55];           % flat neutral gray

types  = {'cP', 'cQ_high', 'cQ_low'};
groups = struct( ...
    'folder', {folder_cP,   folder_cQ_high,  folder_cQ_low}, ...
    'type',   {'cP',        'cQ_high',       'cQ_low'});

type_title = containers.Map(types, {'cP', 'cQ_high', 'cQ_low'});

%% ================================================================
%  SECTION 3 — PASS 1: build file/token lists + global color scale
% ================================================================

% job(k) collects everything needed to plot one (type, token) figure
job = struct('type', {}, 'folder', {}, 'token', {}, 'time_hr', {}, ...
             'bio_name', {}, 'velx_name', {}, 'vely_name', {});

% Pooled speed values, kept SEPARATE per scale group (see scale_group_map)
% so cQ_high's high-flow-rate pixels never influence cP/cQ_low's scale
% or vice versa.
all_bio_speed_vals  = containers.Map('KeyType', 'char', 'ValueType', 'any');
all_pore_speed_vals = containers.Map('KeyType', 'char', 'ValueType', 'any');
for sg = unique(values(scale_group_map))
    all_bio_speed_vals(sg{1})  = [];
    all_pore_speed_vals(sg{1}) = [];
end

for g = 1:numel(groups)
    gtype   = groups(g).type;
    gfolder = groups(g).folder;

    fprintf('\n%s\n  Group: %s\n%s\n', repmat('=',1,60), gtype, repmat('=',1,60));

    all_files = dir(fullfile(gfolder, '*.mat'));
    if isempty(all_files)
        warning('No .mat files in: %s', gfolder); continue;
    end
    names_all = {all_files.name};

    bio_files  = names_all(startsWith_ci(names_all, bio_prefix));
    velx_files = names_all(startsWith_ci(names_all, velx_prefix));
    vely_files = names_all(startsWith_ci(names_all, vely_prefix));

    fprintf('  Found: %d biomass | %d %s | %d %s files\n', ...
        numel(bio_files), numel(velx_files), velx_prefix, numel(vely_files), vely_prefix);

    tokens = cellfun(@extract_time_token, bio_files, 'UniformOutput', false);
    tokens = tokens(~cellfun(@isempty, tokens));
    fprintf('  Tokens: %s\n', strjoin(tokens, ', '));

    for ti = 1:numel(tokens)
        token   = tokens{ti};
        time_hr = str2double(token(2:end));

        bio_name  = match_by_token(bio_files, token);
        velx_name = match_by_token(velx_files, token);
        vely_name = match_by_token(vely_files, token);

        if isempty(bio_name)
            fprintf('  [SKIP %s] no biomass file\n', token); continue;
        end
        if isempty(velx_name) || isempty(vely_name)
            fprintf('  [SKIP %s] missing velocity file(s) (%s / %s)\n', ...
                token, velx_prefix, vely_prefix); continue;
        end

        biomass = load_first_var(fullfile(gfolder, bio_name));
        Ufx     = load_first_var(fullfile(gfolder, velx_name));
        Ufy     = load_first_var(fullfile(gfolder, vely_name));

        if ~isequal(size(biomass), size(Ufx)) || ~isequal(size(biomass), size(Ufy))
            warning(['  [SKIP %s] size mismatch: biomass %s vs velocity %s. ', ...
                     'Check for the known Nx/Ny meshgrid transpose issue.'], ...
                     token, mat2str(size(biomass)), mat2str(size(Ufx)));
            continue;
        end

        grain_mask = isnan(biomass);
        pore_mask  = ~grain_mask & (biomass >= pore_val_min);
        bio_mask   = ~grain_mask & ~pore_mask & (biomass >= 0);

        speed = compute_flux(Ufx, Ufy, flux_component);

        if use_global_scale
            sg = scale_group_map(gtype);
            all_bio_speed_vals(sg)  = [all_bio_speed_vals(sg);  speed(bio_mask)];
            all_pore_speed_vals(sg) = [all_pore_speed_vals(sg); speed(pore_mask)];
        end

        k = numel(job) + 1;
        job(k).type      = gtype;
        job(k).folder    = gfolder;
        job(k).token     = token;
        job(k).time_hr   = time_hr;
        job(k).bio_name  = bio_name;
        job(k).velx_name = velx_name;
        job(k).vely_name = vely_name;
    end
end

if isempty(job)
    error('No matched (biomass, %s, %s) file triplets found. Check prefixes/paths in Section 1.', ...
        velx_prefix, vely_prefix);
end

% ---- Global color-scale bounds, one per scale group (robust percentile
%      clipping) ------------------------------------------------------
scale_bounds = containers.Map('KeyType', 'char', 'ValueType', 'any');
if use_global_scale
    fprintf('\n');
    for sg = unique(values(scale_group_map))
        sg = sg{1}; %#ok<FXSET>
        bvals = all_bio_speed_vals(sg);
        pvals = all_pore_speed_vals(sg);
        if isempty(bvals) || isempty(pvals)
            warning('Scale group "%s" has no matched files — skipping.', sg);
            continue;
        end
        b_lo = prctile(bvals, bio_pctile_lo);  b_hi = prctile(bvals, bio_pctile_hi);
        p_lo = prctile(pvals, pore_pctile_lo); p_hi = prctile(pvals, pore_pctile_hi);
        scale_bounds(sg) = struct('bio_lo', b_lo, 'bio_hi', b_hi, ...
                                   'pore_lo', p_lo, 'pore_hi', p_hi);
        fprintf('Scale group "%s"  ->  biomass flux [%.4g, %.4g]  |  pore flux [%.4g, %.4g]  (p%d-p%d)\n', ...
            sg, b_lo, b_hi, p_lo, p_hi, bio_pctile_lo, bio_pctile_hi);
    end
end

%% ================================================================
%  SECTION 4 — PASS 2: build each figure
% ================================================================

for k = 1:numel(job)

    gtype   = job(k).type;
    gfolder = job(k).folder;
    token   = job(k).token;
    time_hr = job(k).time_hr;
    label   = sprintf('%s_%s', gtype, token);

    fprintf('  --> %s  (%.0f hr)\n', label, time_hr);

    biomass = load_first_var(fullfile(gfolder, job(k).bio_name));
    Ufx     = load_first_var(fullfile(gfolder, job(k).velx_name));
    Ufy     = load_first_var(fullfile(gfolder, job(k).vely_name));
    [Nx, Ny] = size(biomass);

    grain_mask = isnan(biomass);
    pore_mask  = ~grain_mask & (biomass >= pore_val_min);
    bio_mask   = ~grain_mask & ~pore_mask & (biomass >= 0);

    speed = compute_flux(Ufx, Ufy, flux_component);

    % ---- Look up this job's scale-group bounds, or fall back to
    %      per-image auto-scaling if use_global_scale is false ---------
    scale_group = scale_group_map(gtype);
    if use_global_scale
        sb = scale_bounds(scale_group);
        bio_lo = sb.bio_lo; bio_hi = sb.bio_hi;
        pore_lo = sb.pore_lo; pore_hi = sb.pore_hi;
    else
        bio_lo  = prctile(speed(bio_mask),  bio_pctile_lo);
        bio_hi  = prctile(speed(bio_mask),  bio_pctile_hi);
        pore_lo = prctile(speed(pore_mask), pore_pctile_lo);
        pore_hi = prctile(speed(pore_mask), pore_pctile_hi);
    end
    if bio_hi <= bio_lo,  bio_hi  = bio_lo + eps; end
    if pore_hi <= pore_lo, pore_hi = pore_lo + eps; end

    % ---- Along-chip (x) flux-ratio profile ----------------------------
    smooth_win = max(smooth_min_px, round(smooth_frac * Nx));
    if mod(smooth_win, 2) == 0, smooth_win = smooth_win + 1; end

    ratio_raw = NaN(1, Nx);
    for xi = 1:Nx
        bio_row_mask  = bio_mask(xi, :);
        pore_row_mask = pore_mask(xi, :);
        bio_flux_x  = sum(speed(xi, bio_row_mask));
        pore_flux_x = sum(speed(xi, pore_row_mask));
        % Guard against divide-by-zero / empty rows. A row with biomass
        % but zero measured pore flux (or no pore pixels) is left NaN
        % rather than plotted as Inf/0, since neither is meaningful.
        if pore_flux_x > 0 && any(bio_row_mask)
            ratio_raw(xi) = bio_flux_x / pore_flux_x;
        end
    end
    ratio_profile = smooth_nan_movmean(ratio_raw, smooth_win);

    % ---- Overall (whole-image) flux summary ----------------------------
    % Same summed-flux convention as the per-row ratio above, but pooled
    % over the ENTIRE image rather than row-by-row. This is the single
    % headline number for the figure: "does biomass, in total, carry
    % more or less flow than the open pore space, in this image?"
    overall_bio_flux  = sum(speed(bio_mask));
    overall_pore_flux = sum(speed(pore_mask));
    if overall_pore_flux > 0
        overall_ratio = overall_bio_flux / overall_pore_flux;
    else
        overall_ratio = NaN;
    end

    % ---- Build composite RGB flux map ---------------------------------
    R = zeros(Nx, Ny); G = zeros(Nx, Ny); B = zeros(Nx, Ny);
    R(grain_mask) = grain_clr(1); G(grain_mask) = grain_clr(2); B(grain_mask) = grain_clr(3);

    n_pore = size(pore_cmap, 1);
    pore_idx  = find(pore_mask);
    pore_norm = min(max((speed(pore_idx) - pore_lo) / (pore_hi - pore_lo), 0), 1);
    pore_rows = min(max(round(pore_norm * (n_pore - 1)) + 1, 1), n_pore);
    R(pore_idx) = pore_cmap(pore_rows, 1);
    G(pore_idx) = pore_cmap(pore_rows, 2);
    B(pore_idx) = pore_cmap(pore_rows, 3);

    n_bio = size(inferno_cmap, 1);
    bio_idx  = find(bio_mask);
    bio_norm = min(max((speed(bio_idx) - bio_lo) / (bio_hi - bio_lo), 0), 1);
    bio_rows = min(max(round(bio_norm * (n_bio - 1)) + 1, 1), n_bio);
    R(bio_idx) = inferno_cmap(bio_rows, 1);
    G(bio_idx) = inferno_cmap(bio_rows, 2);
    B(bio_idx) = inferno_cmap(bio_rows, 3);

    rgb_img = permute(cat(3, R, G, B), [2 1 3]);   % [Nx,Ny,3] -> [Ny,Nx,3] for image()

    % ---- Save figure ----------------------------------------------
    ttl = sprintf('%s  |  t = %.0f hr', type_title(gtype), time_hr);
    fname = fullfile(folder_plots, sprintf('%s_flux_biomass_map.png', label));
    save_flux_panel_png(rgb_img, Nx, Ny, ratio_profile, ...
        inferno_cmap, pore_cmap, grain_clr, bio_lo, bio_hi, pore_lo, pore_hi, ...
        ratio_log_scale, flux_component, scale_group, ...
        overall_bio_flux, overall_pore_flux, overall_ratio, ttl, fname, png_dpi);
    fprintf('     Saved: %s_flux_biomass_map.png\n', label);

end % job loop

fprintf('\nAll done. Output folder:\n  %s\n\n', folder_plots);

%% ================================================================
%  LOCAL FUNCTIONS
%% ================================================================

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

function speed = compute_flux(Ufx, Ufy, mode)
    switch lower(mode)
        case 'speed'
            speed = hypot(Ufx, Ufy);
        case 'ufx'
            speed = abs(Ufx);
        otherwise
            error('Unknown flux_component: %s (use ''speed'' or ''ufx'')', mode);
    end
end

function out = smooth_nan_movmean(v, win)
    % NaN-aware centred moving mean, edge-shrinking window
    n = numel(v);
    out = NaN(1, n);
    hw = floor(win/2);
    for i = 1:n
        idx = max(1, i-hw) : min(n, i+hw);
        w = v(idx);
        w = w(~isnan(w));
        if ~isempty(w), out(i) = mean(w); end
    end
end

% ----------------------------------------------------------------
%  make_inferno_cmap — vivid, high-contrast ramp (black -> purple ->
%  red -> orange -> pale yellow). Used ONLY for biomass flux, so it
%  is the visual signature that jumps out of the figure.
% ----------------------------------------------------------------
function cmap = make_inferno_cmap(n)
    if nargin < 1, n = 256; end
    anchors = [ ...
          0   0   4; ...
         40  11  84; ...
         87  16 110; ...
        140  41 129; ...
        188  55  84; ...
        221  81  58; ...
        249 142   9; ...
        252 191  73; ...
        252 255 164] / 255;
    cmap = interp1(linspace(0,1,size(anchors,1)), anchors, linspace(0,1,n));
end

% ----------------------------------------------------------------
%  make_pore_gray_cmap — muted, low-saturation gray-blue ramp. Used
%  ONLY for pore-space flow, deliberately low-contrast so it reads as
%  background context rather than competing with the biomass signal.
% ----------------------------------------------------------------
function cmap = make_pore_gray_cmap(n)
    if nargin < 1, n = 256; end
    anchors = [ ...
        0.94 0.94 0.95; ...
        0.82 0.84 0.87; ...
        0.68 0.72 0.78; ...
        0.55 0.60 0.68] ;
    cmap = interp1(linspace(0,1,size(anchors,1)), anchors, linspace(0,1,n));
end

% ----------------------------------------------------------------
%  save_flux_panel_png
%
%  FIGURE LAYOUT (two stacked panels, x-aligned)
%   ┌───────────────────────────────────────────────────┐
%   │ TOP: width-mean biomass-flux / pore-flux ratio      │
%   │      along chip length (log axis, ref. line at 1)  │
%   ├───────────────────────────────────────────────────┤
%   │ BOTTOM: 2D flux map — grain (gray) / pore (muted    │
%   │         gray-blue) / biomass (vivid inferno) +      │
%   │         two colorbars (biomass prominent, pore small)│
%   └───────────────────────────────────────────────────┘
% ----------------------------------------------------------------
function save_flux_panel_png(rgb_img, Nx, Ny, ratio_profile, ...
        inferno_cmap, pore_cmap, grain_clr, bio_lo, bio_hi, pore_lo, pore_hi, ...
        ratio_log_scale, flux_component, scale_group, ...
        overall_bio_flux, overall_pore_flux, overall_ratio, ttl, fpath, dpi)

    % ------------------------------------------------------------------
    % Pixel-exact layout (same approach as the pressure/biomass script):
    % ax_top and ax_map share left/width in pixels; ax_map height is
    % derived from the true Nx:Ny data aspect ratio.
    % ------------------------------------------------------------------
    fig_w_px       = 1150;
    left_px        = 110;     % left margin (shared by both panels)
    map_w_px       = 650;     % shared plotting-box width

    gap_cb1_px     = 45;      % gap: map -> biomass colorbar (prominent)
    cb1_w_px       = 14;
    gap_cb2_px     = 70;      % gap: biomass cbar -> pore colorbar (small)
    cb2_w_px       = 14;

    map_bot_px     = 75;      % bottom margin (x label/ticks)
    gap_top_map_px = 45;      % gap between map and top panel
    top_h_px       = 230;     % top-panel plotting-box height
    top_extra_px   = 70;      % headroom above top panel for legend/title

    map_h_px = map_w_px * (Ny / Nx);          % true data aspect ratio
    map_h_px = min(max(map_h_px, 120), 520);   % keep the figure sane

    fig_h_px = map_bot_px + map_h_px + gap_top_map_px + top_h_px + top_extra_px;

    fig = figure('Visible', 'off', 'Position', [0 0 fig_w_px fig_h_px], 'Color', 'w');

    map_left = left_px / fig_w_px;
    map_w    = map_w_px / fig_w_px;
    map_bot  = map_bot_px / fig_h_px;
    map_h    = map_h_px / fig_h_px;
    top_bot  = (map_bot_px + map_h_px + gap_top_map_px) / fig_h_px;
    top_h    = top_h_px / fig_h_px;

    cb1_left = map_left + map_w + gap_cb1_px / fig_w_px;
    cb1_w    = cb1_w_px / fig_w_px;
    cb2_left = cb1_left + cb1_w + gap_cb2_px / fig_w_px;
    cb2_w    = cb2_w_px / fig_w_px;

    ratio_clr = [0.72 0.20 0.20];   % brick-red line, echoes inferno's warm end

    % =========================== TOP PANEL ===========================
    ax_top = axes(fig, 'Position', [map_left, top_bot, map_w, top_h]);
    hold(ax_top, 'on');

    x = 1:Nx;
    r_valid = isfinite(ratio_profile) & (ratio_profile > 0);

    if ratio_log_scale
        set(ax_top, 'YScale', 'log');
    end

    if any(r_valid)
        r_range = ratio_profile(r_valid);
        r_lo = min(r_range); r_hi = max(r_range);
        if r_lo == r_hi, r_lo = r_lo * 0.5; r_hi = r_hi * 2; end
        if ratio_log_scale
            pad = (log10(r_hi) - log10(r_lo)) * 0.15 + 0.05;
            y_lo = 10^(log10(r_lo) - pad); y_hi = 10^(log10(r_hi) + pad);
        else
            pad = (r_hi - r_lo) * 0.15;
            y_lo = max(r_lo - pad, 0); y_hi = r_hi + pad;
        end
    else
        y_lo = 0.1; y_hi = 10;
    end

    fill(ax_top, [x(r_valid), fliplr(x(r_valid))], ...
        [ratio_profile(r_valid), y_lo * ones(1, sum(r_valid))], ...
        ratio_clr, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    h_ratio = plot(ax_top, x(r_valid), ratio_profile(r_valid), '-', ...
        'Color', ratio_clr, 'LineWidth', 2.4, 'DisplayName', 'Biomass flux / Pore flux');

    ylim(ax_top, [y_lo, y_hi]);
    xlim(ax_top, [1 Nx]);
    yline(ax_top, 1, '--', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, ...
        'Label', 'equal flux density', 'LabelHorizontalAlignment', 'left', ...
        'FontSize', 9, 'HandleVisibility', 'off');

    if isfinite(overall_ratio) && overall_ratio > 0
        yline(ax_top, overall_ratio, '-', 'Color', 'k', 'LineWidth', 1.4, ...
            'Alpha', 0.55, 'Label', sprintf('Overall = %.3g', overall_ratio), ...
            'LabelHorizontalAlignment', 'right', 'FontSize', 9, ...
            'HandleVisibility', 'off');
    end

    set(ax_top, 'FontSize', 10, 'Box', 'off');
    xlabel(ax_top, 'Position along chip length  (px)', 'FontSize', 11);
    ylabel(ax_top, 'Flux ratio (biomass/pore)', ...
        'FontSize', 12, 'Color', ratio_clr, 'FontWeight', 'bold');
    ax_top.YColor = ratio_clr;
    grid(ax_top, 'on'); ax_top.GridAlpha = 0.15;

    legend(ax_top, h_ratio, 'Location', 'northoutside', 'Orientation', 'horizontal', ...
        'FontSize', 10, 'Box', 'off');
    hold(ax_top, 'off');

    % ========================== MAIN MAP PANEL =========================
    ax_map = axes(fig, 'Position', [map_left, map_bot, map_w, map_h]);
    image(ax_map, 'XData', [1 Nx], 'YData', [1 Ny], 'CData', rgb_img);
    set(ax_map, 'YDir', 'normal');
    axis(ax_map, 'off');
    xlim(ax_map, [1 Nx]); ylim(ax_map, [1 Ny]);

    h_grain = patch(ax_map, NaN, NaN, grain_clr, 'EdgeColor', [0.35 0.35 0.35], ...
        'DisplayName', 'Grain');
    legend(ax_map, h_grain, 'Location', 'southoutside', 'Orientation', 'horizontal', ...
        'FontSize', 9, 'Box', 'off', 'TextColor', [0.2 0.2 0.2]);

    % ------------------------ Biomass flux colorbar (prominent) --------
    ax_cb1 = axes(fig, 'Position', [cb1_left, map_bot, cb1_w, map_h], 'Visible', 'off');
    colormap(ax_cb1, inferno_cmap);
    caxis(ax_cb1, [bio_lo, bio_hi]);
    cb1 = colorbar(ax_cb1, 'Position', [cb1_left, map_bot, cb1_w, map_h]);
    cb1.Label.String = 'Biomass flow (m/s)';
    cb1.Label.FontSize = 11;
    cb1.Label.FontWeight = 'bold';
    cb1.FontSize = 9;

    % ------------------------ Pore flow colorbar (muted, secondary) ----
    pore_h_px = round((map_h * fig_h_px) * 0.6);   % shorter, visually subordinate
    pore_bot  = map_bot + (map_h - pore_h_px/fig_h_px)/2;
    ax_cb2 = axes(fig, 'Position', [cb2_left, pore_bot, cb2_w, pore_h_px/fig_h_px], 'Visible', 'off');
    colormap(ax_cb2, pore_cmap);
    caxis(ax_cb2, [pore_lo, pore_hi]);
    cb2 = colorbar(ax_cb2, 'Position', [cb2_left, pore_bot, cb2_w, pore_h_px/fig_h_px]);
    cb2.Label.String = 'Pore flow (m/s)';
    cb2.Label.FontSize = 8;
    cb2.FontSize = 7;
    cb2.Color = [0.45 0.45 0.45];

    % ---------------------- Whole-image flux summary box -----------------
    if isfinite(overall_ratio)
        ratio_str = sprintf('%.3g', overall_ratio);
    else
        ratio_str = 'undefined (no pore flux)';
    end

    print(fig, fpath, '-dpng', sprintf('-r%d', dpi));
    close(fig);
end