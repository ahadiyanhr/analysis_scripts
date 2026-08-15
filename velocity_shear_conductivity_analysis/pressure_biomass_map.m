%% ================================================================
%  REACTOR MAP + PRESSURE/BIOMASS PROFILE BATCH PLOTTER  v1
%  THREE experiment types: cP, cQ_high, cQ_low
%
%  For every (type, timepoint) this produces ONE publication-quality
%  PNG with two stacked, x-aligned panels:
%
%    TOP    : Pressure (Pa, left axis) and spatially-averaged biomass
%             density (right axis) as smooth profiles along the chip
%             length (left -> right), sliced/averaged across the
%             chip width at each x-position.
%
%    BOTTOM : 2D map of the porous medium:
%               - grains            -> flat neutral gray
%               - pore, no biofilm  -> near-white   (biomass == 1)
%               - biomass           -> perceptually-uniform viridis
%                                       colormap, 0 = sparse (raw 0.99)
%                                       -> 1 = dense (raw 0)
%
%  BIOMASS VALUE CONVENTION (per file, unchanged from source data):
%     NaN         -> grain
%     1           -> open pore, no biofilm
%     [0, 0.99]   -> biomass occupancy; 0.99 = very LOW density,
%                     0 = very HIGH density (i.e. inverted scale)
%
%  For plotting/averaging we convert to an intuitive 0->1 "density"
%  scale via:      dens = (0.99 - biomass) / 0.99      (biomass px only)
%  Pore-without-biofilm pixels contribute dens = 0 to spatial averages.
%
%  FILE MATCHING
%  -------------
%   Three folders (one per type). Within each, files matched by shared
%   T### time token:   biomass*  ,  P_*   (P_ file optional per token)
% ================================================================

%% ================================================================
%  SECTION 1 — USER INPUT  (only section you need to edit)
% ================================================================

folder_cP      = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cP';
folder_cQ_high = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_high';
folder_cQ_low  = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_low';
folder_plots   = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\pressure_biomass_map';

% Biomass raw-value convention (edit only if the source files change)
biomass_sparse_val = 0.99;   % raw value meaning "very low density"
biomass_dense_val  = 0.0;    % raw value meaning "very high density"
pore_val_min       = 1.0;    % raw value >= this => open pore, no biofilm

% Smoothing of the along-chip profiles (as a fraction of chip length Nx;
% converted to an odd pixel-window internally). Larger = smoother line.
smooth_frac = 0.03;          % 3% of chip length
smooth_min_px = 5;

% PNG resolution
png_dpi = 300;               % 300 dpi is PNAS figure standard

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
viridis_cmap = flipud(make_viridis_cmap(256));   % biomass density: 0 sparse (light) -> 1 dense (dark)
grain_clr    = [0.55 0.55 0.55];         % flat neutral gray
pore_clr     = [0.975 0.975 0.965];      % near-white

pressure_clr = [0.10 0.28 0.55];         % deep steel blue  (left axis, top panel)
biomass_line_clr = [0.80 0.58 0.05];     % goldenrod, echoes viridis high (dense) end

types = {'cP', 'cQ_high', 'cQ_low'};
groups = struct( ...
    'folder', {folder_cP,   folder_cQ_high,  folder_cQ_low}, ...
    'type',   {'cP',        'cQ_high',       'cQ_low'});

type_title = containers.Map(types, {'cP', 'cQ_high', 'cQ_low'});

%% ================================================================
%  SECTION 3 — BATCH LOOP
% ================================================================

for g = 1:numel(groups)

    gtype   = groups(g).type;
    gfolder = groups(g).folder;

    fprintf('\n%s\n  Group: %s\n%s\n', repmat('=',1,60), gtype, repmat('=',1,60));

    all_files = dir(fullfile(gfolder, '*.mat'));
    if isempty(all_files)
        warning('No .mat files in: %s', gfolder); continue;
    end
    names_all = {all_files.name};

    bio_files  = names_all(startsWith_ci(names_all, 'biomass'));
    pres_files = names_all(startsWith_ci(names_all, 'P_'));

    fprintf('  Found: %d biomass | %d pressure files\n', numel(bio_files), numel(pres_files));

    tokens = cellfun(@extract_time_token, bio_files, 'UniformOutput', false);
    tokens = tokens(~cellfun(@isempty, tokens));
    fprintf('  Tokens: %s\n', strjoin(tokens, ', '));

    for ti = 1:numel(tokens)

        token   = tokens{ti};
        time_hr = str2double(token(2:end));

        bio_name = match_by_token(bio_files, token);
        if isempty(bio_name)
            fprintf('  [SKIP %s] no biomass file\n', token); continue;
        end

        label = sprintf('%s_%s', gtype, token);
        fprintf('  --> %s  (%.0f hr)\n', label, time_hr);

        % ---- Load biomass ------------------------------------------
        biomass = load_first_var(fullfile(gfolder, bio_name));
        [Nx, Ny] = size(biomass);

        % ---- Load pressure (optional) --------------------------------
        pres_name = match_by_token(pres_files, token);
        if ~isempty(pres_name)
            pressure = load_first_var(fullfile(gfolder, pres_name)) * 100;  % mbar -> Pa
            fprintf('     Pressure file: %s\n', pres_name);
        else
            pressure = [];
            fprintf('     [NOTE] no pressure file for %s — pressure line skipped\n', token);
        end

        % ---- Category masks -----------------------------------------
        grain_mask = isnan(biomass);
        pore_mask  = ~grain_mask & (biomass >= pore_val_min);
        bio_mask   = ~grain_mask & ~pore_mask & (biomass >= 0);

        % ---- Density (0 sparse -> 1 dense) for biomass pixels --------
        dens = NaN(Nx, Ny);
        dens(bio_mask)  = (biomass_sparse_val - biomass(bio_mask)) / (biomass_sparse_val - biomass_dense_val);
        dens(bio_mask)  = min(max(dens(bio_mask), 0), 1);
        dens(pore_mask) = 0;   % open pore contributes zero density to spatial averages

        % ---- Along-chip (x) profiles ----------------------------------
        smooth_win = max(smooth_min_px, round(smooth_frac * Nx));
        if mod(smooth_win, 2) == 0, smooth_win = smooth_win + 1; end

        dens_profile_raw = NaN(1, Nx);
        for xi = 1:Nx
            row = dens(xi, ~grain_mask(xi,:));
            row = row(~isnan(row));
            if ~isempty(row), dens_profile_raw(xi) = mean(row); end
        end
        dens_profile = smooth_nan_movmean(dens_profile_raw, smooth_win);

        if ~isempty(pressure)
            pres_profile_raw = NaN(1, Nx);
            for xi = 1:Nx
                row = pressure(xi, ~grain_mask(xi,:));
                row = row(isfinite(row));
                if ~isempty(row), pres_profile_raw(xi) = mean(row); end
            end
            pres_profile = smooth_nan_movmean(pres_profile_raw, smooth_win);
        else
            pres_profile = [];
        end

        % ---- Build composite RGB image ---------------------------------
        R = zeros(Nx, Ny); G = zeros(Nx, Ny); B = zeros(Nx, Ny);
        R(grain_mask) = grain_clr(1); G(grain_mask) = grain_clr(2); B(grain_mask) = grain_clr(3);
        R(pore_mask)  = pore_clr(1);  G(pore_mask)  = pore_clr(2);  B(pore_mask)  = pore_clr(3);

        n_cmap = size(viridis_cmap, 1);
        bio_idx = find(bio_mask);
        cmap_rows = min(max(round(dens(bio_idx) * (n_cmap - 1)) + 1, 1), n_cmap);
        R(bio_idx) = viridis_cmap(cmap_rows, 1);
        G(bio_idx) = viridis_cmap(cmap_rows, 2);
        B(bio_idx) = viridis_cmap(cmap_rows, 3);

        rgb_img = permute(cat(3, R, G, B), [2 1 3]);   % [Nx,Ny,3] -> [Ny,Nx,3] for image()

        % ---- Save figure ----------------------------------------------
        ttl = sprintf('%s  |  t = %.0f hr', type_title(gtype), time_hr);
        fname = fullfile(folder_plots, sprintf('%s_reactor_map_profile.png', label));
        save_reactor_panel_png(rgb_img, Nx, Ny, dens_profile, pres_profile, ...
            viridis_cmap, grain_clr, pore_clr, pressure_clr, biomass_line_clr, ...
            ttl, fname, png_dpi);
        fprintf('     Saved: %s_reactor_map_profile.png\n', label);

    end % token loop
end % group loop

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

function save_png(fig, fpath, dpi)
    print(fig, fpath, '-dpng', sprintf('-r%d', dpi));
end

% ----------------------------------------------------------------
%  make_viridis_cmap — perceptually-uniform, colorblind-safe
%  Built from 8 published anchor colors of the viridis colormap,
%  linearly interpolated in RGB space (matches the pattern used by
%  the original script's make_stress_cmap helper).
% ----------------------------------------------------------------
function cmap = make_viridis_cmap(n)
    if nargin < 1, n = 256; end
    anchors = [ ...
        68   1  84; ...
        72  40 120; ...
        62  74 137; ...
        49 104 142; ...
        38 130 142; ...
        31 158 137; ...
        53 183 121; ...
       109 205  89; ...
       180 222  44; ...
       253 231  37] / 255;
    cmap = interp1(linspace(0,1,size(anchors,1)), anchors, linspace(0,1,n));
end

% ----------------------------------------------------------------
%  save_reactor_panel_png
%
%  FIGURE LAYOUT (two stacked panels, x-aligned)
%   ┌───────────────────────────────────────────────────┐
%   │ TOP: pressure (left axis, blue) +                  │
%   │      mean biomass density (right axis, gold)       │
%   ├───────────────────────────────────────────────────┤
%   │ BOTTOM: 2D reactor map (grain/pore/biomass) +       │
%   │         viridis colorbar for biomass density        │
%   └───────────────────────────────────────────────────┘
% ----------------------------------------------------------------
function save_reactor_panel_png(rgb_img, Nx, Ny, dens_profile, pres_profile, ...
        viridis_cmap, grain_clr, pore_clr, pressure_clr, biomass_line_clr, ...
        ttl, fpath, dpi)

    % ------------------------------------------------------------------
    % Pixel-exact layout.
    % ax_top and ax_map are given the SAME left/width in pixels, and
    % ax_map's height is derived from the true Nx:Ny data aspect ratio
    % (rather than using 'axis equal', which would shrink the rendered
    % image inside its box and break alignment with the panel above).
    % The figure height is then built around that map height, so the
    % left/right edges of both panels always coincide exactly.
    % ------------------------------------------------------------------
    fig_w_px      = 1000;
    left_px       = 110;     % left margin (shared by both panels)
    map_w_px      = 680;     % shared plotting-box width
    gap_cb_px     = 20;
    cb_w_px       = 25;

    map_bot_px    = 75;      % bottom margin (x label/ticks)
    gap_top_map_px= 45;      % gap between map and top panel
    top_h_px      = 230;     % top-panel plotting-box height
    top_extra_px  = 80;      % headroom above top panel for legend/title

    map_h_px = map_w_px * (Ny / Nx);            % true data aspect ratio
    map_h_px = min(max(map_h_px, 120), 520);     % keep the figure sane for extreme aspect ratios

    fig_h_px = map_bot_px + map_h_px + gap_top_map_px + top_h_px + top_extra_px;

    fig = figure('Visible', 'off', 'Position', [0 0 fig_w_px fig_h_px], 'Color', 'w');

    map_left = left_px / fig_w_px;
    map_w    = map_w_px / fig_w_px;
    map_bot  = map_bot_px / fig_h_px;
    map_h    = map_h_px / fig_h_px;
    top_bot  = (map_bot_px + map_h_px + gap_top_map_px) / fig_h_px;
    top_h    = top_h_px / fig_h_px;
    cb_left  = map_left + map_w + gap_cb_px / fig_w_px;
    cb_w     = cb_w_px / fig_w_px;

    % =========================== TOP PANEL ===========================
    ax_top = axes(fig, 'Position', [map_left, top_bot, map_w, top_h]);
    hold(ax_top, 'on');

    x = 1:Nx;

    have_pressure = ~isempty(pres_profile);
    if have_pressure
        yyaxis(ax_top, 'left');
    end

    % Pressure: shaded area + solid line (baseline = axis floor, not zero)
    if have_pressure
        p_valid = isfinite(pres_profile);
        p_range = pres_profile(p_valid);
        p_lo = min(p_range); p_hi = max(p_range);
        if p_lo == p_hi, p_lo = p_lo - 1; p_hi = p_hi + 1; end
        pad = (p_hi - p_lo) * 0.12;
        p_ylo = p_lo - pad; p_yhi = p_hi + pad;

        fill(ax_top, [x(p_valid), fliplr(x(p_valid))], ...
            [pres_profile(p_valid), p_ylo * ones(1, sum(p_valid))], ...
            pressure_clr, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        h_pres = plot(ax_top, x(p_valid), pres_profile(p_valid), '-', ...
            'Color', pressure_clr, 'LineWidth', 2.4, 'DisplayName', 'Pressure');
        ylim(ax_top, [p_ylo, p_yhi]);
        ylabel(ax_top, 'Pressure  (Pa)', 'FontSize', 12, 'Color', pressure_clr, 'FontWeight', 'bold');
        ax_top.YAxis(1).Color = pressure_clr;
    else
        h_pres = gobjects(0);
    end

    if have_pressure, yyaxis(ax_top, 'right'); end
    d_valid = isfinite(dens_profile);
    d_lo = min(dens_profile(d_valid)); d_hi = max(dens_profile(d_valid));
    if ~isfinite(d_lo) || d_lo == d_hi, d_lo = 0; d_hi = 1; end
    pad_d = max((d_hi - d_lo) * 0.15, 0.02);
    d_ylo = max(d_lo - pad_d, 0); d_yhi = d_hi + pad_d;

    fill(ax_top, [x(d_valid), fliplr(x(d_valid))], ...
        [dens_profile(d_valid), d_ylo * ones(1, sum(d_valid))], ...
        biomass_line_clr, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    h_bio = plot(ax_top, x(d_valid), dens_profile(d_valid), '-', ...
        'Color', biomass_line_clr, 'LineWidth', 2.4, 'DisplayName', 'Mean biomass density');
    ylim(ax_top, [d_ylo, d_yhi]);
    ylabel(ax_top, 'Average biomass density', ...
        'FontSize', 12, 'Color', biomass_line_clr, 'FontWeight', 'bold');
    if have_pressure
        ax_top.YAxis(2).Color = biomass_line_clr;
        yyaxis(ax_top, 'left');
    else
        ax_top.YColor = biomass_line_clr;
    end

    xlim(ax_top, [1 Nx]);
    set(ax_top, 'FontSize', 10, 'Box', 'off');
    xlabel(ax_top, 'Position along chip length  (px)', 'FontSize', 11);
    % title(ax_top, ttl, 'FontSize', 14, 'FontWeight', 'bold');
    grid(ax_top, 'on'); ax_top.GridAlpha = 0.15;

    h_all = [h_pres, h_bio];
    legend(ax_top, h_all, 'Location', 'northoutside', 'Orientation', 'horizontal', ...
        'FontSize', 10, 'Box', 'off');
    hold(ax_top, 'off');

    % ========================== MAIN MAP PANEL =========================
    ax_map = axes(fig, 'Position', [map_left, map_bot, map_w, map_h]);
    image(ax_map, 'XData', [1 Nx], 'YData', [1 Ny], 'CData', rgb_img);
    set(ax_map, 'YDir', 'normal');
    axis(ax_map, 'off');   % 'normal' (not 'equal') so the image fills its box exactly,
                           % since the box's aspect ratio was already set to match Nx:Ny above
    xlim(ax_map, [1 Nx]); ylim(ax_map, [1 Ny]);

    h_grain = patch(ax_map, NaN, NaN, grain_clr, 'EdgeColor', [0.35 0.35 0.35], ...
        'DisplayName', 'Grain');
    h_pore  = patch(ax_map, NaN, NaN, pore_clr, 'EdgeColor', [0.6 0.6 0.6], ...
        'DisplayName', 'Pore (no biofilm)');
    legend(ax_map, [h_grain, h_pore], 'Location', 'southoutside', 'Orientation', 'horizontal', ...
        'FontSize', 9, 'Box', 'off', 'TextColor', [0.2 0.2 0.2]);

    % ------------------------ Biomass density colorbar ------------------
    ax_cb = axes(fig, 'Position', [cb_left, map_bot, cb_w, map_h], 'Visible', 'off');
    colormap(ax_cb, viridis_cmap);
    caxis(ax_cb, [0 1]);
    cb = colorbar(ax_cb, 'Position', [cb_left, map_bot, cb_w, map_h]);
    cb.Label.String = 'Biomass density';
    cb.Label.FontSize = 11;
    cb.FontSize = 9;

    print(fig, fpath, '-dpng', sprintf('-r%d', dpi));
    close(fig);
end