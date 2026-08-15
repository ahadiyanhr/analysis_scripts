clc
clear

%% ================================================================
%  VELOCITY FIELD BATCH PLOTTER  (three-group version, fixed ranges)
%  + BIOMASS vs. PORE FLUX SUMMARY  (NEW)
%
%  - Scans three folders: cP, cQ_high, cQ_low
%  - Matches Ufx / Ufy files by shared timing token TXXX
%  - Saves velocity magnitude maps as PNG, same colormap throughout
%  - Color-axis (clim) is FIXED per "range group", where you decide
%    which flow conditions share a range (Section 1)
%  - NEW: also matches the biomass density file for each token,
%    separates "biomass" pixels from "pore" (non-biomass) pixels,
%    computes the local flux (velocity magnitude) within each of the
%    two regions, and produces a single summary figure comparing
%    biomass vs. pore flux across the three experiment types
%    (x-axis = experiment type, y-axis = mean +/- std across all
%    timepoints), styled for a PNAS-quality figure.
%  - NEW: PFP width analysis — per image, the top 20% highest-
%    velocity pixels are treated as one preferential flow path (PFP);
%    their total area is converted to an equivalent width and
%    summarized (mean +/- std across all images) per type.
% ================================================================
%
%  EXPECTED FILE NAMING (examples):
%    Ufx_CQ_T053.mat    Ufy_CQ_T053.mat    biomass_CQ_T053.mat
%    Ufx_CP_T129.mat    Ufy_CP_T129.mat    biomass_CP_T129.mat
%
%  MATCHING RULE:
%    Files are matched by the TXXX token (T followed by digits),
%    e.g. T053, T129, T200 — extracted automatically from filename.
%    One timing token must appear in exactly one Ufx and one Ufy
%    file per folder. The biomass file for that token is optional —
%    if it is missing, the velocity PNG is still produced, but that
%    timepoint is excluded from the biomass/pore flux summary.
%
%  BIOMASS PIXEL CONVENTION:
%    NaN         = grains (excluded from all masks)
%    0           = open pore (no biomass)
%    (0, 1]      = biomass density
%    "Biomass" pixels  = biomass_density > biomass_threshold
%    "Pore" pixels     = 0 <= biomass_density <= biomass_threshold
%
% ================================================================

%% ================================================================
%  SECTION 1 — USER INPUT  (only section you need to edit)
% ================================================================

folder_cP      = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cP';
folder_cQ_high = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_high';
folder_cQ_low  = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_low';
folder_plots   = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\velocity_plots_flux_portion_pfpwidth';

% Grid trim (rows to keep)
x_cut = [101, 2600];

% PNG resolution: 150 = fast preview, 300 = publication
png_dpi = 150;

% ---- RANGE GROUP ASSIGNMENT -------------------------------------
%  Decide which flow conditions should share the SAME fixed color
%  range. Any number of range groups is allowed — this is what
%  keeps the code flexible if you later want e.g. all three
%  sharing one range, or all three on separate ranges.
%
%  Example (current default): cP and cQ_low share 'rangeA',
%  cQ_high gets its own 'rangeB'.
range_group_assignment = containers.Map( ...
    {'cP', 'cQ_high', 'cQ_low'}, ...
    {'rangeA', 'rangeB', 'rangeA'});

% ---- RANGE GROUP COLOR LIMITS (velocity, m/s) -------------------
%  For each range group named above, specify the color-axis limits:
%    []            = auto-compute (1st-99th percentile, pooled
%                     across ALL files belonging to that range
%                     group, across all timesteps)
%    [vmin vmax]   = fixed values you supply (recommended once you
%                     know good publication limits)
range_group_clim = containers.Map( ...
    {'rangeA', 'rangeB'}, ...
    {[1e-6, 0.001], [2.372e-06, 0.0197]});

% ---- FLUX RATIO ANALYSIS (NEW) -----------------------------------
%  Two pixel bands, based on biomass density (see convention above):
%    "biomass" band: not NaN, and biomass_density in [0, 1)
%    "pore"    band: biomass_density == 1 (within full_tol)
%  ratio = sum(velocity over biomass) / sum(velocity over pore)
full_tol = 1e-6;   % tolerance for treating density as exactly 1

% ---- PFP WIDTH ANALYSIS (NEW) ------------------------------------
%  A pixel is treated as part of the PFP if its velocity is at or
%  above an ABSOLUTE threshold set pfp_percentile% of the way up its
%  range group's FIXED color range (rangeA / rangeB, from Section 1's
%  range_group_clim) — e.g. 80 -> threshold sits 80% up from the
%  range's minimum to its maximum, so only the top 20% of the VALUE
%  RANGE (not pixel count) counts as PFP. This threshold is the same
%  absolute velocity for every image within a range group, so faster
%  conditions naturally end up with more PFP pixels than slower ones.
%  Computed for EACH percentile in this list, so the width summary
%  figure shows how the PFP width estimate shifts with stringency.
pfp_percentiles = [30, 50, 80];

%  Reactor physical dimensions (mm). Area of the PFP is computed from
%  its pixel count and converted to physical area using these, then
%  divided by reactor_length_mm to get an equivalent PFP width.
reactor_length_mm = 15;   % divided into to get width (flow direction, inlet -> outlet)
reactor_width_mm  = 10;   % transverse extent (perpendicular to flow)

%% ================================================================
%  SECTION 2 — SETUP
% ================================================================

if ~exist(folder_plots, 'dir'), mkdir(folder_plots); end
fprintf('Output folder: %s\n', folder_plots);

all_folders = {folder_cP, folder_cQ_high, folder_cQ_low};
for chk = all_folders
    f = chk{1};
    if ~exist(f, 'dir')
        error('Folder does not exist: %s\nCheck your folder path in Section 1.', f);
    end
    mats = dir(fullfile(f, '*.mat'));
    fprintf('  Found %d .mat files in: %s\n', numel(mats), f);
    if numel(mats) == 0
        warning('No .mat files in: %s', f);
    else
        fprintf('  First file: %s\n', mats(1).name);
    end
end

customMap_v = make_velocity_cmap(8); % for stepped colormap
% customMap_v = make_velocity_cmap(); % for gradient colormap

groups(1).folder = folder_cP;
groups(1).type   = 'cP';
groups(2).folder = folder_cQ_high;
groups(2).type   = 'cQ_high';
groups(3).folder = folder_cQ_low;
groups(3).type   = 'cQ_low';

% Sanity check: every group type must have a range group assigned
for g = 1:numel(groups)
    if ~isKey(range_group_assignment, groups(g).type)
        error('No range_group_assignment entry for type "%s". Add one in Section 1.', groups(g).type);
    end
end

%% ================================================================
%  SECTION 3 — PASS A: LOAD ALL FILES, COMPUTE VELOCITY, STORE
%  (also loads the matching biomass file, when available, and
%   computes biomass-vs-pore flux for that timepoint; also computes
%   the per-image PFP width)
% ================================================================

items = struct('label',{}, 'type',{}, 'token',{}, 'time_hr',{}, ...
                'rangegroup',{}, 'U_cut',{}, 'xx',{}, 'yy',{}, ...
                'sum_biomass',{}, 'n_biomass',{}, 'sum_pore',{}, 'n_pore',{}, 'flux_ratio',{}, ...
                'width_pfp_mm',{}, 'n_pfp',{}, 'pfp_thresh',{}, 'Nx_full',{}, 'Ny_full',{});

for g = 1:numel(groups)

    gtype   = groups(g).type;
    gfolder = groups(g).folder;
    rgroup  = range_group_assignment(gtype);

    fprintf('\n%s\n  Group: %s  |  Folder: %s\n%s\n', ...
            repmat('=',1,60), gtype, gfolder, repmat('=',1,60));

    all_files = dir(fullfile(gfolder, '*.mat'));
    if isempty(all_files)
        warning('No .mat files found in: %s', gfolder); continue;
    end
    names_all = {all_files.name};

    vx_files  = names_all(startsWith_ci(names_all, 'Ufx'));
    vy_files  = names_all(startsWith_ci(names_all, 'Ufy'));
    bio_files = names_all(startsWith_ci(names_all, 'biomass'));

    fprintf('  Found: %d Ufx | %d Ufy | %d biomass files\n', ...
        numel(vx_files), numel(vy_files), numel(bio_files));

    if isempty(vx_files)
        warning('No Ufx files found in %s', gfolder); continue;
    end

    tokens = cellfun(@extract_time_token, vx_files, 'UniformOutput', false);
    tokens = tokens(~cellfun(@isempty, tokens));

    fprintf('  Timing tokens found: %s\n', strjoin(tokens, ', '));

    for ti = 1:numel(tokens)

        token   = tokens{ti};
        time_hr = str2double(token(2:end));

        vx_name  = match_by_token(vx_files,  token);
        vy_name  = match_by_token(vy_files,  token);
        bio_name = match_by_token(bio_files, token);

        if isempty(vx_name)
            fprintf('  [SKIP %s] No Ufx match\n', token); continue;
        end
        if isempty(vy_name)
            fprintf('  [SKIP %s] No Ufy match\n', token); continue;
        end

        label = sprintf('%s_%s', gtype, token);
        fprintf('  --> %s  (%.0f hr)  | range group: %s\n', label, time_hr, rgroup);
        fprintf('      Ufx : %s\n', vx_name);
        fprintf('      Ufy : %s\n', vy_name);

        Vx = load_first_var(fullfile(gfolder, vx_name));
        Vy = load_first_var(fullfile(gfolder, vy_name));
        U  = sqrt(Vx.^2 + Vy.^2);

        % ---- Full (uncropped) grid size, needed for correct mm-per-
        %  pixel conversion factors below (x_cut only trims rows, so
        %  the column count is unaffected by cropping; using the
        %  UNCROPPED row count keeps the physical mm-per-pixel scale
        %  correct even though only a sub-region is analyzed).
        [Nx_full, Ny_full] = size(U);

        U_cut = U(x_cut(1):x_cut(2), :);
        [Nx, Ny] = size(U_cut);
        [yy, xx] = meshgrid(1:Ny, 1:Nx);

        % ---- NEW: biomass-vs-pore flux ratio for this timepoint --
        %  "biomass" = not NaN, density in [0, 1)
        %  "pore"    = density == 1 (within tolerance)
        %  NOTE ON UNITS: volumetric flux through a region is
        %  channel_height * pixel_area * sum(velocity over that
        %  region's pixels). Channel height and pixel area are
        %  constant across pixels AND across all three experiments,
        %  so both cancel in the ratio below — only sum(velocity)
        %  is needed (see header note). Using MEAN here instead of
        %  SUM would silently discard the region-size information
        %  the ratio is meant to reflect, so SUM is used deliberately.
        sum_biomass = NaN; n_biomass = 0;
        sum_pore    = NaN; n_pore    = 0;
        flux_ratio  = NaN;
        if isempty(bio_name)
            fprintf('      [WARN] No biomass match for %s — excluded from flux-ratio summary\n', token);
        else
            fprintf('      biomass : %s\n', bio_name);
            biomass_raw = load_first_var(fullfile(gfolder, bio_name));
            biomass_cut = biomass_raw(x_cut(1):x_cut(2), :);

            if ~isequal(size(biomass_cut), size(U_cut))
                fprintf('      [WARN] biomass/velocity size mismatch for %s — excluded from flux-ratio summary\n', token);
            else
                mask_pore    = (abs(biomass_cut - 1) < full_tol) & ~isnan(biomass_cut);
                mask_biomass = ~isnan(biomass_cut) & (biomass_cut >= 0) & ~mask_pore;

                v_biomass = U_cut(mask_biomass & ~isnan(U_cut));
                v_pore    = U_cut(mask_pore    & ~isnan(U_cut));

                sum_biomass = sum(v_biomass); n_biomass = numel(v_biomass);
                sum_pore    = sum(v_pore);    n_pore    = numel(v_pore);

                if n_pore > 0 && sum_pore > 0
                    flux_ratio = sum_biomass / sum_pore;
                else
                    fprintf('      [WARN] No/zero pore flux for %s — ratio set to NaN\n', token);
                end

                fprintf('      sum(biomass)=%.4g (n=%d px) | sum(pore)=%.4g (n=%d px) | ratio=%.4g\n', ...
                    sum_biomass, n_biomass, sum_pore, n_pore, flux_ratio);
            end
        end

        % ---- PFP width: DEFERRED ---------------------------------
        %  A per-image percentile threshold (prctile of THIS image's
        %  own pixels) always selects ~20% of pixels regardless of
        %  actual velocity, which made every type's width identical.
        %  Instead, the threshold must be an ABSOLUTE velocity value
        %  shared across all images of a range group — specifically
        %  80% of the way up that range group's fixed color range
        %  (rangeA / rangeB, from Section 4) — so a genuinely faster
        %  condition clears the bar with more pixels than a slower
        %  one. That range isn't known until Section 4 has resolved
        %  it, so the actual PFP width computation happens in a
        %  second pass after Section 4 (see Section 4b below). Here
        %  we only keep the grid-size bookkeeping needed for it.
        width_pfp_mm = NaN; n_pfp = 0; pfp_thresh = NaN;

        idx = numel(items) + 1;
        items(idx).label        = label;
        items(idx).type         = gtype;
        items(idx).token        = token;
        items(idx).time_hr      = time_hr;
        items(idx).rangegroup   = rgroup;
        items(idx).U_cut        = U_cut;
        items(idx).xx           = xx;
        items(idx).yy           = yy;
        items(idx).sum_biomass  = sum_biomass;
        items(idx).n_biomass    = n_biomass;
        items(idx).sum_pore     = sum_pore;
        items(idx).n_pore       = n_pore;
        items(idx).flux_ratio   = flux_ratio;
        items(idx).width_pfp_mm = width_pfp_mm;
        items(idx).n_pfp        = n_pfp;
        items(idx).pfp_thresh   = pfp_thresh;
        items(idx).Nx_full      = Nx_full;
        items(idx).Ny_full      = Ny_full;
    end
end

if isempty(items)
    error(['No data was loaded. Check folder paths in Section 1.\n' ...
           '  folder_cP      = %s\n' ...
           '  folder_cQ_high = %s\n' ...
           '  folder_cQ_low  = %s\n'], folder_cP, folder_cQ_high, folder_cQ_low);
end

%% ================================================================
%  SECTION 4 — RESOLVE FIXED COLOR RANGE PER RANGE GROUP
%  (auto-compute via pooled 1st-99th percentile where clim = [])
% ================================================================

resolved_clim = containers.Map('KeyType','char','ValueType','any');

all_rgroups = unique({items.rangegroup});
for r = 1:numel(all_rgroups)
    rg = all_rgroups{r};

    if isKey(range_group_clim, rg) && ~isempty(range_group_clim(rg))
        resolved_clim(rg) = range_group_clim(rg);
        fprintf('Range group "%s": using fixed clim [%.4g, %.4g]\n', ...
            rg, resolved_clim(rg));
        continue;
    end

    % Pool pore-space (>0) velocity values across all items in this group
    pooled = [];
    member_idx = find(strcmp({items.rangegroup}, rg));
    for mi = member_idx
        v = items(mi).U_cut;
        v = v(~isnan(v) & v > 0);
        pooled = [pooled; v(:)]; %#ok<AGROW>
    end

    if isempty(pooled)
        warning('Range group "%s" has no valid velocity data; defaulting clim to [0 1].', rg);
        resolved_clim(rg) = [0 1];
    else
        resolved_clim(rg) = [prctile(pooled,1), prctile(pooled,99)];
    end
    fprintf('Range group "%s": auto clim (pooled 1-99pct) = [%.4g, %.4g]\n', ...
        rg, resolved_clim(rg));
end

%% ================================================================
%  SECTION 4b — PFP WIDTH: RANGE-BASED THRESHOLD, MULTIPLE PERCENTILES
%
%  For EACH value in pfp_percentiles, threshold = clim(1) +
%  (pct/100) * (clim(2) - clim(1)), i.e. a point pct% of the way up
%  the FIXED color range already resolved for this item's range
%  group (rangeA / rangeB). This is an ABSOLUTE velocity value
%  shared by every image in that range group, so a genuinely faster
%  condition naturally clears the bar with more pixels than a
%  slower one — unlike a per-image percentile, which always selects
%  ~(100-pct)% of pixels regardless of the actual velocities.
%
%  WIDTH PROFILE (per image, per percentile):
%    Rather than collapsing PFP area into a single width via
%    area/length (which only tells you the AVERAGE width, and
%    whose only source of variability was image-to-image drift),
%    we now build a width PROFILE along the flow direction: at each
%    row (= each position from inlet to outlet), count PFP pixels
%    in that cross-section and convert to a physical width (mm).
%      width_pfp_mean_mm = mean(profile)   -> that image's average width
%      width_pfp_std_mm  = std(profile)    -> how much the width
%                          fluctuates ALONG THE PATH within that
%                          SAME image (branching/narrowing), i.e.
%                          the within-image spatial variability —
%                          NOT variability between different images.
%
%  Results are stored in LONG format (one row per type/token/
%  percentile combination) in pfp_results.
% ================================================================

fprintf('\n--- PFP width: resolving range-based thresholds (multiple percentiles) ---\n');

pfp_results = table();

for p = 1:numel(pfp_percentiles)
    pct = pfp_percentiles(p);

    pfp_thresh_by_rgroup = containers.Map('KeyType','char','ValueType','any');
    for r = 1:numel(all_rgroups)
        rg   = all_rgroups{r};
        clim = resolved_clim(rg);
        pfp_thresh_by_rgroup(rg) = clim(1) + (pct/100) * (clim(2) - clim(1));
        fprintf('  [pct=%d]  Range group "%s": PFP threshold = %.4g m/s  (%.0f%% up from [%.4g, %.4g])\n', ...
            pct, rg, pfp_thresh_by_rgroup(rg), pct, clim(1), clim(2));
    end

    for idx = 1:numel(items)
        it     = items(idx);
        thresh = pfp_thresh_by_rgroup(it.rangegroup);

        mask_pfp = (it.U_cut >= thresh) & ~isnan(it.U_cut);
        n_pfp    = sum(mask_pfp(:));

        % Transverse (column) physical spacing — columns are never
        % cropped by x_cut, so Ny_full is the right conversion factor
        % regardless of whether the analyzed region is cropped in rows.
        dy_mm_per_px = reactor_width_mm / it.Ny_full;

        % One PFP-pixel count per row = one cross-section along the
        % flow direction, over the analyzed (possibly row-cropped)
        % region -> converted directly to a physical width (mm).
        counts_per_row    = sum(mask_pfp, 2);
        width_profile_mm  = counts_per_row * dy_mm_per_px;

        width_pfp_mean_mm = mean(width_profile_mm);
        width_pfp_std_mm  = std(width_profile_mm);

        row = table({it.type}, {it.token}, it.time_hr, pct, ...
            width_pfp_mean_mm, width_pfp_std_mm, n_pfp, thresh, ...
            'VariableNames', {'type','token','time_hr','percentile', ...
                'width_pfp_mean_mm','width_pfp_std_mm','n_pfp','pfp_thresh'});
        pfp_results = [pfp_results; row]; %#ok<AGROW>
    end
end

%% ================================================================
%  SECTION 5 — PASS B: PLOT + SAVE VELOCITY PNGS
% ================================================================

fprintf('\n--- Saving velocity field PNGs ---\n');

% for idx = 1:numel(items)
%     it     = items(idx);
%     %clim_v = resolved_clim(it.rangegroup);
%     clim_v = range_group_clim(it.rangegroup);
% 
%     fname_v = fullfile(folder_plots, sprintf('%s_velocity.png', it.label));
%     save_field_png(it.xx, it.yy, it.U_cut, customMap_v, clim_v, ...
%         'Velocity magnitude (m/s)', ...
%         sprintf('%s  |  t = %.0f hr  (range: %s)', it.label, it.time_hr, it.rangegroup), ...
%         fname_v, png_dpi);
%     fprintf('  Saved: %s_velocity.png\n', it.label);
% end

fprintf('\nAll velocity PNGs saved to:\n  %s\n\n', folder_plots);

% ---- NEW: one horizontal colorbar per range group -----------------
fprintf('\n--- Saving standalone horizontal colorbars ---\n');
for r = 1:numel(all_rgroups)
    rg       = all_rgroups{r};
    clim_hcb = range_group_clim(rg);   % matches what Section 5 actually plots with
    fname_hcb = fullfile(folder_plots, sprintf('colorbar_horizontal_%s.png', rg));
    save_horizontal_colorbar(customMap_v, clim_hcb, 'Velocity magnitude (m/s)', fname_hcb, png_dpi);
end

%% ================================================================
%  SECTION 6 — FLUX RATIO SUMMARY  (NEW)
%  x-axis: experiment type  |  y-axis: mean +/- std of the per-
%  timepoint ratio [sum(velocity, partial/open) / sum(velocity,
%  fully-clogged)], across all timepoints of that type.
% ================================================================

fprintf('\n--- Section 6: Flux Ratio Summary ---\n');

flux_table = struct2table(items);
flux_table = flux_table(:, {'type','token','time_hr','sum_biomass','n_biomass','sum_pore','n_pore','flux_ratio'});

types_order = {'cP','cQ_high','cQ_low'};
types_order = types_order(ismember(types_order, unique(flux_table.type)));

flux_stats = table();
for k = 1:numel(types_order)
    tp   = types_order{k};
    rows = strcmp(flux_table.type, tp);

    r = flux_table.flux_ratio(rows); r = r(isfinite(r));

    row = table({tp}, mean_or_nan(r), std_or_nan(r), numel(r), ...
        'VariableNames', {'type','ratio_mean','ratio_std','ratio_n'});
    flux_stats = [flux_stats; row]; %#ok<AGROW>

    fprintf('  [%s]  ratio: mean=%.4g std=%.4g (n=%d valid timepoints out of %d total)\n', ...
        tp, row.ratio_mean, row.ratio_std, row.ratio_n, sum(rows));
end

if any(isnan(flux_stats.ratio_mean))
    warning(['At least one experiment type has no valid flux ratio ' ...
             '(missing biomass files, or zero flux through pore (density==1) pixels at every timepoint).']);
end

fprintf('\nSection 6 complete.\n\n');

%% ================================================================
%  SECTION 7 — PFP WIDTH SUMMARY  (NEW)
%  x-axis: experiment type  |  y-axis: mean width (mm), averaged
%  across all images of that type, for EACH percentile separately.
%  ERROR BAR = the ALONG-PATH (within-image) std, averaged across
%  images — i.e. how much the PFP's width fluctuates from inlet to
%  outlet WITHIN a single snapshot (branching/narrowing), not how
%  much the image-average width drifts from one timepoint to
%  another. (That across-image drift is still available as
%  width_std_across_images_mm below, but is NOT what's plotted.)
% ================================================================

fprintf('\n--- Section 7: PFP Width Summary ---\n');

width_stats = table();
for p = 1:numel(pfp_percentiles)
    pct = pfp_percentiles(p);
    for k = 1:numel(types_order)
        tp   = types_order{k};
        rows = strcmp(pfp_results.type, tp) & (pfp_results.percentile == pct);

        w_mean = pfp_results.width_pfp_mean_mm(rows); w_mean = w_mean(isfinite(w_mean));
        w_std  = pfp_results.width_pfp_std_mm(rows);  w_std  = w_std(isfinite(w_std));

        row = table({tp}, pct, mean_or_nan(w_mean), mean_or_nan(w_std), ...
            std_or_nan(w_mean), numel(w_mean), ...
            'VariableNames', {'type','percentile','width_mean_mm', ...
                'width_std_mm', 'width_std_across_images_mm', 'width_n'});
        width_stats = [width_stats; row]; %#ok<AGROW>

        fprintf(['  [%s, pct=%d]  PFP width: mean=%.4g mm | along-path std=%.4g mm ' ...
                 '(across-image std of the mean=%.4g mm, for reference) | n=%d images\n'], ...
            tp, pct, row.width_mean_mm, row.width_std_mm, row.width_std_across_images_mm, row.width_n);
    end
end

if any(isnan(width_stats.width_mean_mm))
    warning('At least one experiment type/percentile combination has no valid PFP width.');
end

plot_combined_summary(flux_stats, flux_table, width_stats, pfp_results, ...
    types_order, pfp_percentiles, folder_plots, png_dpi);

% NEW — standalone flux-ratio-only figure
plot_flux_ratio_only(flux_stats, types_order, folder_plots, png_dpi);

fprintf('\nSection 7 complete.\n\n');

%% ================================================================
%  LOCAL FUNCTIONS
% ================================================================

% --- Case-insensitive startsWith for a cell array of filenames --
function mask = startsWith_ci(names, prefix)
    mask = strncmpi(names, prefix, length(prefix));
end

% --- Extract TXXX token (T followed by digits) from filename ----
function token = extract_time_token(fname)
    match = regexp(fname, 'T\d+', 'match', 'once');
    if isempty(match), token = ''; else, token = match; end
end

% --- Find file in list that contains the given TXXX token -------
function match = match_by_token(file_list, token)
    match = '';
    for i = 1:numel(file_list)
        if ~isempty(regexp(file_list{i}, token, 'once'))
            match = file_list{i}; return;
        end
    end
end

% --- Load the first variable from a .mat ------------------------
function out = load_first_var(filepath)
    S = load(filepath); fields = fieldnames(S); out = S.(fields{1});
end

% --- Mean of a vector, NaN if empty ------------------------------
function m = mean_or_nan(v)
    if isempty(v), m = NaN; else, m = mean(v); end
end

% --- Std of a vector, NaN if fewer than 2 elements ---------------
function s = std_or_nan(v)
    if numel(v) < 2, s = NaN; else, s = std(v); end
end

% --- Velocity colormap -------------------------------------------
function cmap = make_velocity_cmap(n_steps)
    % Stepwise colormap: N discrete bands, HIGH velocity -> dark,
    % LOW velocity -> pale (reversed plasma anchors).
    if nargin < 1, n_steps = 8; end   % number of discrete color bands

    anchors = [ ...
        0.050383 0.029803 0.527975;
        0.417642 0.000564 0.658390;
        0.692840 0.165141 0.564522;
        0.881443 0.392529 0.383229;
        0.988260 0.652325 0.211364;
        0.940015 0.975158 0.131326];

    x_anchor = linspace(0, 1, size(anchors,1));
    x_steps  = linspace(0, 1, n_steps);
    step_colors = interp1(x_anchor, anchors, x_steps, 'pchip');
    % step_colors = flipud(step_colors);   % high velocity -> dark

    % Expand each of the n_steps colors into a solid block so the
    % 256-row colormap reads as discrete bands, not a gradient
    reps = round(256 / n_steps);
    cmap = repelem(step_colors, reps, 1);
    cmap = cmap(1:min(size(cmap,1),256), :);   % trim to exactly 256
    if size(cmap,1) < 256
        cmap = [cmap; repmat(cmap(end,:), 256-size(cmap,1), 1)];
    end
end

% --- Plot a 2D field and save as PNG ------------------------------
function save_field_png(xx, yy, data, cmap, clims, cbar_lbl, ttl, fpath, dpi)
    fig = figure('Visible','off','Position',[0 0 850 700]);
    hold on;
    surface(xx, yy, zeros(size(xx)), ...
        'CData', repmat(0.3*ones(size(xx)),[1 1 3]), ...
        'FaceColor','texturemap','EdgeColor','none','CDataMapping','direct');
    pcolor(xx, yy, data); shading flat; % for stepped colormap %shading interp; % for gradient colormap
    colormap(fig, cmap);
    cb = colorbar; cb.Label.String = cbar_lbl; cb.Label.FontSize = 11;
    caxis(clims); axis equal off;
    title(ttl, 'FontSize',12, 'FontWeight','bold');
    hold off;
    save_png(fig, fpath, dpi);
    close(fig);
end

% --- Save figure as PNG -------------------------------------------
function save_png(fig, fpath, dpi)
    print(fig, fpath, '-dpng', sprintf('-r%d', dpi));
end

% ------------------------------------------------------------------
%  PNAS-style COMBINED figure: ONE panel, two y-axes, sharing the
%  same x-axis (experiment type).
%    LEFT axis:  PFP width, grouped bars by percentile stringency
%                (pfp_percentiles), sequential single-hue palette
%                (colorblind-safe, monotonic in grayscale).
%    RIGHT axis: Flux ratio (biomass / pore), plotted as a LINE with
%                markers and error bars connecting the three types.
%  Both series: mean +/- std, lower whisker clipped at 0 (neither
%  quantity can be physically negative). PFP width bars additionally
%  show individual per-image values as small jittered points; the
%  flux-ratio line is left uncluttered (no jitter) since overlaying
%  raw points from a different y-scale in the same panel gets busy.
% ------------------------------------------------------------------
function plot_combined_summary(flux_stats, flux_table, width_stats, pfp_results, ...
        types_order, pfp_percentiles, folder_plots, png_dpi)

    n_types = numel(types_order);
    n_pct   = numel(pfp_percentiles);

    % ---- Colors -----------------------------------------------------
    % LEFT axis (PFP width): 3-class sequential "Blues" (ColorBrewer),
    % light->dark mapped to increasing percentile (increasing
    % stringency). Colorblind-safe and converts monotonically to
    % grayscale — both standard requirements for PNAS figures.
    col_pct = [ ...
        0.871 0.922 0.969;   % lightest -> lowest percentile (e.g. 30)
        0.620 0.792 0.882;   % medium   -> middle percentile (e.g. 50)
        0.192 0.510 0.741];  % darkest  -> highest percentile (e.g. 80)
    if n_pct > 3
        col_pct = interp1(linspace(0,1,3), col_pct, linspace(0,1,n_pct));
    else
        col_pct = col_pct(1:n_pct, :);
    end

    % RIGHT axis (flux ratio): warm accent, deliberately far from the
    % blue family above so the two axes are unambiguous at a glance —
    % a muted brick-red, a common complementary pairing for two-axis
    % figures that still reads cleanly in grayscale (mid-gray, not
    % confusable with the light/dark blue bars once desaturated).
    col_flux = [0.72 0.28 0.16];

    fig = figure('Visible','on','Units','inches','Position',[0 0 5.4 3.8]);
    ax  = axes(fig); hold(ax,'on');

    % ================= LEFT AXIS: PFP WIDTH (bars) ===================
    yyaxis(ax, 'left');

    means_B = zeros(n_types, n_pct);
    stds_B  = zeros(n_types, n_pct);
    for t = 1:n_types
        for p = 1:n_pct
            row = strcmp(width_stats.type, types_order{t}) & ...
                  (width_stats.percentile == pfp_percentiles(p));
            means_B(t,p) = width_stats.width_mean_mm(row);
            stds_B(t,p)  = width_stats.width_std_mm(row);
        end
    end

    hb = bar(ax, means_B, 'grouped');
    for p = 1:n_pct
        hb(p).FaceColor = col_pct(p,:);
        hb(p).EdgeColor = 'none';
        hb(p).FaceAlpha = 0.95;
    end

    groupwidth = min(0.8, n_pct/(n_pct + 1.5));
    xpos = zeros(n_types, n_pct);
    for p = 1:n_pct
        xpos(:,p) = (1:n_types)' - groupwidth/2 + (2*p-1) * groupwidth / (2*n_pct);
    end
    for p = 1:n_pct
        % Asymmetric error bar, lower whisker clipped at 0: width can
        % never be negative, but a symmetric mean-std whisker can dip
        % below zero when std is large relative to the mean (e.g. a
        % right-skewed, intermittent PFP).
        neg_p = min(stds_B(:,p), means_B(:,p));
        errorbar(ax, xpos(:,p), means_B(:,p), neg_p, stds_B(:,p), 'k', ...
            'LineStyle','none', 'LineWidth', 1.0, 'CapSize', 5, 'HandleVisibility','off');
    end

    ylabel(ax, 'Equivalent single-PFP width (mm)', 'FontSize', 10, 'FontName','Helvetica');
    ax.YAxis(1).Color = [0.15 0.15 0.15];   % neutral dark gray, not tied to any one bar color

    % ================= RIGHT AXIS: FLUX RATIO (line + errorbar) ======
    yyaxis(ax, 'right');

    means_A = flux_stats.ratio_mean;
    stds_A  = flux_stats.ratio_std;
    neg_A   = min(stds_A, means_A);   % same zero-floor clipping as the width bars

    hline = errorbar(ax, 1:n_types, means_A, neg_A, stds_A, '-o', ...
        'Color', col_flux, 'MarkerFaceColor', col_flux, 'MarkerEdgeColor', col_flux, ...
        'MarkerSize', 6, 'LineWidth', 1.5, 'CapSize', 6);

    ylabel(ax, 'Flux ratio (biomass/pores)', 'FontSize', 10, 'FontName','Helvetica');
    ax.YAxis(2).Color = col_flux;

    % ================= SHARED X-AXIS + STYLING =======================
    set(ax, 'XTick', 1:n_types, 'XTickLabel', types_order, ...
        'TickLabelInterpreter','none', 'FontSize', 9, 'FontName','Helvetica');
    xlabel(ax, 'Experiments', 'FontSize', 10, 'FontName','Helvetica');
    xlim(ax, [0.4, n_types + 0.6]);

    box(ax,'off');
    set(ax, 'TickDir','out', 'LineWidth', 0.8, 'Layer','top');
    ax.XGrid = 'off';

    pct_labels = arrayfun(@(p) sprintf('Top %d%%', 100-p), pfp_percentiles, 'UniformOutput', false);
    legend(ax, hb, pct_labels, ...
        'Location','northoutside', 'Orientation','horizontal', ...
        'FontSize', 8, 'Box','off', 'FontName','Helvetica');

  

    hold(ax,'off');

    fpath = fullfile(folder_plots, 'flux_pfp_combined_summary.png');
    print(fig, fpath, '-dpng', sprintf('-r%d', png_dpi));
    fprintf('  Saved: flux_pfp_combined_summary.png\n');
end


% ------------------------------------------------------------------
%  PNAS-style STANDALONE figure: flux ratio (biomass/pore) only,
%  plotted as a line with markers and error bars across the three
%  experiment types. Same data and styling convention as the RIGHT
%  axis of plot_combined_summary, but on its own y-axis/figure so it
%  can be read or shared independently of the PFP width bars.
% ------------------------------------------------------------------
function plot_flux_ratio_only(flux_stats, types_order, folder_plots, png_dpi)

    n_types = numel(types_order);

    % Same warm accent color used for flux ratio in the combined figure
    col_flux = [0.72 0.28 0.16];

    fig = figure('Visible','on','Units','inches','Position',[0 0 4.2 3.4]);
    ax  = axes(fig); hold(ax,'on');

    means_A = flux_stats.ratio_mean;
    stds_A  = flux_stats.ratio_std;
    neg_A   = min(stds_A, means_A);   % zero-floor clipping — ratio can't be negative

    errorbar(ax, 1:n_types, means_A, neg_A, stds_A, '-o', ...
        'Color', col_flux, 'MarkerFaceColor', col_flux, 'MarkerEdgeColor', col_flux, ...
        'MarkerSize', 7, 'LineWidth', 1.6, 'CapSize', 6);

    ylabel(ax, 'Flux ratio (biomass/pores)', 'FontSize', 10, 'FontName','Helvetica');
    xlabel(ax, 'Experiments', 'FontSize', 10, 'FontName','Helvetica');

    set(ax, 'XTick', 1:n_types, 'XTickLabel', types_order, ...
        'TickLabelInterpreter','none', 'FontSize', 9, 'FontName','Helvetica');
    xlim(ax, [0.4, n_types + 0.6]);

    box(ax,'off');
    set(ax, 'TickDir','out', 'LineWidth', 0.8, 'Layer','top');
    ax.XGrid = 'off';

    hold(ax,'off');

    fpath = fullfile(folder_plots, 'flux_ratio_only_summary.png');
    print(fig, fpath, '-dpng', sprintf('-r%d', png_dpi));
    fprintf('  Saved: flux_ratio_only_summary.png\n');
end

function save_horizontal_colorbar(cmap, clims, cbar_lbl, fpath, dpi, n_ticks)
    if nargin < 6, n_ticks = 6; end

    fig = figure('Visible','off','Position',[0 0 700 160]);
    ax  = axes(fig, 'Position', [0.08 0.45 0.84 0.15]);

    colormap(fig, cmap);
    imagesc(ax, clims, [0 1], linspace(clims(1), clims(2), 256));
    ax.YAxis.Visible = 'off';
    caxis(ax, clims);

    tick_vals = nice_ticks(clims(1), clims(2), n_ticks);

    % ---- Shared exponent for the WHOLE colorbar, based on the
    %  largest-magnitude tick (matches MATLAB's own axis-exponent
    %  convention) -----------------------------------------------------
    shared_exp = common_exponent(tick_vals);
    labels     = format_ticks_shared(tick_vals, shared_exp);

    set(ax, 'TickDir','out', 'FontSize', 9, 'FontName','Helvetica', ...
        'XTick', tick_vals, 'XTickLabel', labels);

    xlabel(ax, cbar_lbl, 'FontSize', 10, 'FontName','Helvetica');
    box(ax, 'on');

    % ---- Single "x10^n" annotation at the right end of the colorbar --
    if shared_exp ~= 0
        text(ax, 1.02, 0.5, sprintf('\\times10^{%d}', shared_exp), ...
            'Units', 'normalized', 'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'middle', 'FontSize', 9, 'FontName','Helvetica');
    end

    print(fig, fpath, '-dpng', sprintf('-r%d', dpi));
    close(fig);
    fprintf('  Saved: %s\n', fpath);
end

% ----------------------------------------------------------------
%  Pick n "nice" round tick values that fall within [lo, hi],
%  snapping to a clean step size (1/2/5 x 10^k), same convention
%  MATLAB's own auto-ticks use.
% ----------------------------------------------------------------
function ticks = nice_ticks(lo, hi, n_desired)
    if hi <= lo, ticks = [lo hi]; return; end

    raw_step = (hi - lo) / max(n_desired - 1, 1);
    mag      = 10^floor(log10(raw_step));
    residual = raw_step / mag;

    if residual < 1.5
        step = 1 * mag;
    elseif residual < 3
        step = 2 * mag;
    elseif residual < 7
        step = 5 * mag;
    else
        step = 10 * mag;
    end

    first = ceil(lo / step) * step;
    ticks = first:step:hi;

    if isempty(ticks) || ticks(1) > lo + step
        ticks = [lo, ticks];
    end
end

% ----------------------------------------------------------------
%  Pick a single exponent shared by all ticks, based on the
%  largest-magnitude value.
% ----------------------------------------------------------------
function exp_shared = common_exponent(vals)
    vals_nz = vals(vals ~= 0);
    if isempty(vals_nz)
        exp_shared = 0; return;
    end
    exp_shared = floor(log10(max(abs(vals_nz))));
end

% ----------------------------------------------------------------
%  Format tick labels using ONE shared exponent: each label shows
%  only its mantissa (rounded).
% ----------------------------------------------------------------
function labels = format_ticks_shared(vals, exp_shared)
    labels = cell(size(vals));
    for i = 1:numel(vals)
        v = vals(i);
        if v == 0
            labels{i} = '0';
        else
            mantissa = v / 10^exp_shared;
            labels{i} = sprintf('%g', round(mantissa, 2));
        end
    end
end