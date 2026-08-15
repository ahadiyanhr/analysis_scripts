%% ================================================================
%  2D SHEAR STRESS FIELD AT PROXIMATE BIOMASS  — per-timepoint maps
%
%  Output per timepoint:
%    <label>_biomass_proximity.png   — shear stress map with biomass
%                                      overlay (dark green opaque =
%                                      proximate; dark green 50% =
%                                      non-proximate)
%
%  BIOMASS DATA CONVENTION:
%    NaN          -> grains       (gray background)
%    0  – 0.999  -> biomass       (all plotted as dark green overlay)
%    1            -> pore space   (transparent, shear shows through)
%
%  PROXIMITY DEFINITION:
%    High-shear threshold = clim_t(1) + high_shear_pct * range(clim_t)
%    Proximate biomass    = biomass pixel within proximity_px of
%                            high shear
%
%  FILE NAMING (examples):
%    shear_CQ_T053.mat    biomass_CQ_T053.mat
%    shear_CP_T129.mat    biomass_CP_T129.mat
% ================================================================

%% ================================================================
%  SECTION 1 — USER INPUT
% ================================================================

folder_cQ    = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cQ_low';
folder_cP    = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\0 - Simulations data\cP';
folder_plots = 'Z:\Microfluidics\Roche-2026\Ahadiyan_2026\PFP calculations (new)\shearstress_plots';

% Stress color axis (Pa): [] = auto per file,  [vmin vmax] = fixed
clim_tau = [];

% Proximity parameters
proximity_px    = 2;    % biomass pixels within this distance of high shear -> proximate
high_shear_pct  = 0.2;  % top fraction of shear range = "high shear"  (0.5 = upper 50%)

% PNG resolution: 150 = fast preview, 300 = publication
png_dpi = 150;

%% ================================================================
%  SECTION 2 — SETUP
% ================================================================

if ~exist(folder_plots, 'dir'), mkdir(folder_plots); end
fprintf('Output folder: %s\n', folder_plots);

for chk = {folder_cQ, folder_cP}
    f = chk{1};
    if ~exist(f, 'dir')
        error('Folder does not exist: %s', f);
    end
    mats = dir(fullfile(f, '*.mat'));
    fprintf('  Found %d .mat files in: %s\n', numel(mats), f);
end

customMap_t = make_stress_cmap();

groups(1).folder = folder_cQ;  groups(1).type = 'cQ';
groups(2).folder = folder_cP;  groups(2).type = 'cP';

%% ================================================================
%  SECTION 3 — BATCH LOOP
% ================================================================

for g = 1:numel(groups)

    gtype   = groups(g).type;
    gfolder = groups(g).folder;

    fprintf('\n%s\n  Group: %s  |  Folder: %s\n%s\n', ...
        repmat('=',1,60), gtype, gfolder, repmat('=',1,60));

    all_files = dir(fullfile(gfolder, '*.mat'));
    if isempty(all_files)
        warning('No .mat files found in: %s', gfolder); continue;
    end
    names_all = {all_files.name};

    shear_files = names_all(startsWith_ci(names_all, 'shear'));
    bio_files   = names_all(startsWith_ci(names_all, 'biomass'));

    fprintf('  Found: %d shear | %d biomass files\n', ...
        numel(shear_files), numel(bio_files));

    % Drive token loop from shear files
    tokens = cellfun(@extract_time_token, shear_files, 'UniformOutput', false);
    tokens = tokens(~cellfun(@isempty, tokens));
    fprintf('  Timing tokens: %s\n', strjoin(tokens, ', '));

    for ti = 1:numel(tokens)

        token   = tokens{ti};
        time_hr = str2double(token(2:end));

        shear_name = match_by_token(shear_files, token);
        bio_name   = match_by_token(bio_files,   token);

        if isempty(shear_name)
            fprintf('  [SKIP %s] No shear match\n', token); continue;
        end
        if isempty(bio_name)
            fprintf('  [SKIP %s] No biomass match\n', token); continue;
        end

        label = sprintf('%s_%s', gtype, token);
        fprintf('\n  --> %s  (%.0f hr)\n', label, time_hr);

        % ---- Load --------------------------------------------------
        tau     = abs(load_first_var(fullfile(gfolder, shear_name)));
        biomass = load_first_var(fullfile(gfolder, bio_name));

        % ---- Shear color limits ------------------------------------
        if isempty(clim_tau)
            tp_vals = tau(~isnan(tau) & tau > 0);
            clim_t  = [prctile(tp_vals, 1), prctile(tp_vals, 99)];
        else
            clim_t = clim_tau;
        end

        % ---- Meshgrid for pcolor -----------------------------------
        [Nx, Ny] = size(tau);
        [yy, xx] = meshgrid(1:Ny, 1:Nx);

        % ---- High-shear mask & distances ---------------------------
        high_shear_thresh  = clim_t(1) + high_shear_pct * (clim_t(2) - clim_t(1));
        high_shear_mask    = (tau >= high_shear_thresh) & ~isnan(tau);
        dist_to_highshear  = bwdist(high_shear_mask);   % [Nx x Ny]

        % ---- Biomass masks -------------------------------------------
        bio_all    = (biomass >= 0) & (biomass < 1) & ~isnan(biomass);
        bio_close  = bio_all & (dist_to_highshear <= proximity_px);
        bio_far    = bio_all & (~bio_close);

        % ---- Save proximity PNG ------------------------------------
        fname_prox = fullfile(folder_plots, sprintf('%s_biomass_proximity.png', label));
        save_biomass_proximity_png(xx, yy, tau, bio_close, bio_far, ...
            customMap_t, clim_t, high_shear_thresh, proximity_px, ...
            sprintf('Biomass Proximity to High Shear: %s  |  t = %.0f hr', label, time_hr), ...
            fname_prox, png_dpi);
        fprintf('      Saved: %s_biomass_proximity.png\n', label);

    end % token loop
end % group loop

fprintf('\nAll done. Files saved to:\n  %s\n\n', folder_plots);

%% ================================================================
%  LOCAL FUNCTIONS
% ================================================================

function mask = startsWith_ci(names, prefix)
    mask = strncmpi(names, prefix, length(prefix));
end

function token = extract_time_token(fname)
    match = regexp(fname, 'T\d+', 'match', 'once');
    if isempty(match), token = ''; else, token = match; end
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
    S = load(filepath); fields = fieldnames(S); out = S.(fields{1});
end

function save_png(fig, fpath, dpi)
    print(fig, fpath, '-dpng', sprintf('-r%d', dpi));
end

function cmap = make_stress_cmap()
    a    = [1 1 1; 1 .80 .40; 1 .45 0; .80 .10 0; .40 0 0];
    cmap = interp1(linspace(0,1,size(a,1)), a, linspace(0,1,256));
end

% ================================================================
%  Biomass proximity PNG
%
%  Overlay colors (both dark green, different alpha):
%    bio_close (proximate) -> dark green [0, 0.45, 0.06]  alpha = 1.0
%    bio_far   (distant)   -> dark green [0, 0.45, 0.06]  alpha = 0.5
%
%  Both masks are [Nx x Ny] logical, same space as tau.
%  Transposed before image() to align with the rotated pcolor axes.
% ================================================================
function save_biomass_proximity_png(xx, yy, tau, bio_close, bio_far, ...
        cmap, clims, high_shear_thresh, proximity_px, ttl, fpath, dpi)

    dark_green = [0.0, 0.45, 0.06];

    fig = figure('Visible','off','Position',[0 0 850 700]);
    hold on;

    % 1. Gray background for grains
    surface(xx, yy, zeros(size(xx)), ...
        'CData',        repmat(0.7*ones(size(xx)), [1 1 3]), ...
        'FaceColor',    'texturemap', ...
        'EdgeColor',    'none', ...
        'CDataMapping', 'direct');

    % 2. Shear stress field
    pcolor(xx, yy, tau); shading interp;
    colormap(fig, cmap);
    cb = colorbar;
    cb.Label.String   = 'Shear Stress (Pa)';
    cb.Label.FontSize = 11;
    caxis(clims);

    % 3. Build overlay [Nx x Ny]
    [Nx, Ny] = size(tau);
    R = zeros(Nx, Ny); G = zeros(Nx, Ny); B = zeros(Nx, Ny);
    A = zeros(Nx, Ny);

    % Proximate biomass -- fully opaque dark green
    R(bio_close) = dark_green(1);
    G(bio_close) = dark_green(2);
    B(bio_close) = dark_green(3);
    A(bio_close) = 1.0;

    % Non-proximate biomass -- 50% transparent dark green
    R(bio_far)   = dark_green(1);
    G(bio_far)   = dark_green(2);
    B(bio_far)   = dark_green(3);
    A(bio_far)   = 0.5;

    % Transpose to [Ny x Nx] for image() rotated-axis alignment
    overlay_T = permute(cat(3,R,G,B), [2,1,3]);
    alpha_T   = A';

    image('XData', [1,Nx], 'YData', [1,Ny], ...
          'CData', overlay_T, 'AlphaData', alpha_T);

    % 4. Legend
    h_close = patch(NaN, NaN, dark_green, 'EdgeColor','none', 'FaceAlpha',1.0);
    h_far   = patch(NaN, NaN, dark_green, 'EdgeColor','none', 'FaceAlpha',0.5);
    legend([h_close, h_far], ...
        {sprintf('Proximate biomass (within %d px of high shear)', proximity_px), ...
         'Non-proximate biomass'}, ...
        'Location','southeast','FontSize',9, ...
        'Color',[1 1 1],'EdgeColor',[0.5 0.5 0.5]);

    annotation('textbox',[0.01 0.91 0.45 0.07], ...
        'String', sprintf('High-shear threshold: %.4g Pa', high_shear_thresh), ...
        'FontSize',8,'EdgeColor',[.7 .7 .7],'BackgroundColor','w','FitBoxToText','on');

    axis equal off;
    title(ttl,'FontSize',12,'FontWeight','bold');
    hold off;

    save_png(fig, fpath, dpi);
    close(fig);
end