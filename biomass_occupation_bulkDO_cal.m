%% -------- Setup --------
mainPath = pwd;
cd(mainPath);
cd('../');
projectPath = pwd;

cd(projectPath);
cd('processed_images\thresholded_images\');
threshRootPath = pwd;
mainResultsFolder = dir(fullfile(threshRootPath, '*_main_results'));
mainThreshPath = fullfile(threshRootPath, mainResultsFolder(1).name);

cd(projectPath);
cd('processed_data\do_mapped\');
doMappedPath = pwd;

cd(projectPath);
cd('processed_data\biomass_occupation_bulkDO\');
biomassDataPath = pwd;

cd(projectPath);
cd('logs\');
logsPath = pwd;

%% -------- CONFIG --------
nPatches = 10;   % number of column strips for spatial std estimation

%% -------- LOAD MASK FILE --------
alignmentFile = fullfile(logsPath, 'manual_alignment.mat');
load(alignmentFile, 'GM_Final');
disp('Loaded final Grain Mask from logs folder.');

%% -------- HELPER: reactor crop indices --------
function [col_start, col_end] = reactor_cols(img_width, img_height)
    reactor_L_px = round(1.5 * img_height);
    col_center   = round(img_width / 2);
    col_start    = max(1,         col_center - round(reactor_L_px / 2));
    col_end      = min(img_width, col_center + round(reactor_L_px / 2));
end

%% -------- HELPER: patch-based biomass occupation --------
function [bm_mean, bm_std] = patch_biomass(mat_reactor, gm_reactor, nPatches)
    cols = round(linspace(1, size(mat_reactor, 2)+1, nPatches+1));
    patch_occ = zeros(1, nPatches);
    for i = 1:nPatches
        patch    = mat_reactor(:, cols(i):cols(i+1)-1);
        gm_patch = gm_reactor(:,  cols(i):cols(i+1)-1);
        pore_px  = sum(gm_patch(:) == 0);
        if pore_px == 0
            patch_occ(i) = NaN;
        else
            biomass_px   = sum(patch(:) < 1 & ~isnan(patch(:)));
            patch_occ(i) = biomass_px / pore_px * 100;
        end
    end
    patch_occ = patch_occ(~isnan(patch_occ));
    bm_mean   = mean(patch_occ);
    bm_std    = std(patch_occ);
end

%% -------- File sorting --------
matFiles = dir(fullfile(mainThreshPath, 'thresholded_*.mat'));
nFiles   = length(matFiles);
if nFiles == 0
    warning('No .mat files in: %s', mainThreshPath);
    return;
end
matFiles = matFiles(~[matFiles.isdir]);
matNums  = arrayfun(@(f) sscanf(f.name, 'thresholded_%d.mat'), matFiles);
[~, idx] = sort(matNums);
matFiles = matFiles(idx);

% --- DO data: check availability, don't assume it exists ---
mapped_files = dir(fullfile(doMappedPath, '*.mat'));
mapped_files = mapped_files(~[mapped_files.isdir]);

hasDO = ~isempty(mapped_files) && length(mapped_files) >= nFiles + 1;
if isempty(mapped_files)
    warning('No DO files found in: %s. Proceeding without DO data.', doMappedPath);
elseif length(mapped_files) < nFiles + 1
    warning(['Found %d DO file(s) but expected at least %d (nFiles+1 for t0 baseline). ' ...
             'Proceeding without DO data.'], length(mapped_files), nFiles + 1);
end

if hasDO
    mapNums  = arrayfun(@(f) sscanf(f.name, 'do_mapped_t%d.mat'), mapped_files);
    [~, idx] = sort(mapNums);
    mapped_files = mapped_files(idx);
end

%% -------- t=0 initialization --------
data = struct();
data.biomass_occupation     = 0;
data.biomass_occupation_std = 0;
data.image_names            = {};

if hasDO
    mappedFile_t0 = load(fullfile(doMappedPath, mapped_files(1).name));
    do_map_t0     = mappedFile_t0.mapped;
    [H0, W0]      = size(do_map_t0);
    [cs0, ce0]    = reactor_cols(W0, H0);
    do_reactor_t0 = do_map_t0(:, cs0:ce0);

    data.bulk_do     = mean(do_reactor_t0(:));
    data.bulk_do_std = std(do_reactor_t0(:));
else
    data.bulk_do     = NaN;
    data.bulk_do_std = NaN;
end

fprintf('\n--- Processing %d frames ---\n', nFiles);

%% -------- Main loop --------
for k = 1:nFiles
    % Load thresholded biomass image
    matData = load(fullfile(mainThreshPath, matFiles(k).name));
    fields  = fieldnames(matData);
    mat     = matData.(fields{1});

    % --- Crop to reactor section ---
    [H_px, W_px]          = size(mat);
    [col_start, col_end]  = reactor_cols(W_px, H_px);

    mat_reactor = mat(:,      col_start:col_end);
    gm_reactor  = GM_Final(:, col_start:col_end);

    % --- Patch-based biomass occupation (reactor only) ---
    [bm_mean, bm_std] = patch_biomass(mat_reactor, gm_reactor, nPatches);

    data.biomass_occupation(end+1)     = bm_mean;
    data.biomass_occupation_std(end+1) = bm_std;
    data.image_names{end+1}            = matFiles(k).name;

    % --- Bulk DO (reactor only), only if DO data is available ---
    if hasDO
        mappedFile = load(fullfile(doMappedPath, mapped_files(k+1).name));
        do_map     = mappedFile.mapped;

        [H_do, W_do]   = size(do_map);
        [cs_do, ce_do] = reactor_cols(W_do, H_do);
        do_reactor     = do_map(:, cs_do:ce_do);

        data.bulk_do(end+1)     = mean(do_reactor(:));
        data.bulk_do_std(end+1) = std(do_reactor(:));

        fprintf('Processed %s | biomass: %.2f%% ± %.2f%%  |  bulk DO: %.4f ± %.4f\n', ...
            matFiles(k).name, bm_mean, bm_std, mean(do_reactor(:)), std(do_reactor(:)));
    else
        data.bulk_do(end+1)     = NaN;
        data.bulk_do_std(end+1) = NaN;

        fprintf('Processed %s | biomass: %.2f%% ± %.2f%%  |  bulk DO: n/a (no DO data)\n', ...
            matFiles(k).name, bm_mean, bm_std);
    end
end

%% -------- Save --------
save_path = fullfile(biomassDataPath, [mainResultsFolder(1).name, '.mat']);
save(save_path, 'data');
fprintf('\nSaved to %s\n  Fields: biomass_occupation, biomass_occupation_std, bulk_do, bulk_do_std\n', save_path);
if ~hasDO
    fprintf('Note: bulk_do / bulk_do_std are all NaN — no DO data was available for this run.\n');
end
