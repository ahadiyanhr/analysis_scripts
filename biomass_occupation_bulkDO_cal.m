%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Thresholded images root path
cd(projectPath);
cd('processed_images\thresholded_images\');
threshRootPath = pwd;
mainResultsFolder = dir(fullfile(threshRootPath, '*_main_results'));
mainThreshPath = fullfile(threshRootPath, mainResultsFolder(1).name);

% DO mapped data folder path
cd(projectPath);
cd('processed_data\do_mapped\');
doMappedPath = pwd;

% Biomass occupation data folder path
cd(projectPath);
cd('processed_data\biomass_occupation_bulkDO\');
biomassDataPath = pwd;

% Add this in the Setup section
cd(projectPath);
cd('logs\');
logsPath = pwd;

%% -------- LOAD MASK FILE --------
% Load saved alignment
alignmentFile = fullfile(logsPath, 'manual_alignment.mat');
load(alignmentFile, 'GM_Final');
disp('Loaded final Grain Mask from logs folder.');
total_pore_pixels = sum(GM_Final(:) == 0);
fprintf('Total pore pixels: %d\n', total_pore_pixels);

%% ---- Starting process ----

% Get list of thresholded files
matFiles = dir(fullfile(mainThreshPath, 'thresholded_*.mat'));
nFiles = length(matFiles);
mapped_files = dir(fullfile(doMappedPath,'*.mat'));

if nFiles == 0
    warning('No .mat files in: %s', mainThreshPath);
    return;
end

% After dir() calls, sort both by name
matFiles     = matFiles(~[matFiles.isdir]);
matFiles     = sortrows(struct2table(matFiles), 'name');
matFiles     = table2struct(matFiles);

mapped_files = mapped_files(~[mapped_files.isdir]);
mapped_files = sortrows(struct2table(mapped_files), 'name');
mapped_files = table2struct(mapped_files);

% Initialize struct to hold results
data = struct();
data.biomass_occupation = 0;
mappedFile = load(fullfile(doMappedPath, mapped_files(1).name));
data.bulk_do = mean(mappedFile.mapped(:));

data.image_names = {};
fprintf('\n--- Processing %d frames ---\n', nFiles);

% Loop over files
for k = 1:nFiles
    matData = load(fullfile(mainThreshPath, matFiles(k).name));
    fields  = fieldnames(matData);
    mat     = matData.(fields{1});
    mappedFile = load(fullfile(doMappedPath, mapped_files(k+1).name));
  
    biomass_percent = (sum(~isnan(mat(:))) / total_pore_pixels) * 100;
    data.biomass_occupation(end+1) = biomass_percent;
    data.bulk_do(end+1) = mean(mappedFile.mapped(:));
    data.image_names{end+1} = matFiles(k).name;

    fprintf('Biomass: %.2f%%  |  Bulk DO: %.4f\n', biomass_percent, mean(mappedFile.mapped(:)));

end
    
    % Save results
    save_path = fullfile(biomassDataPath, [mainResultsFolder(1).name, '.mat']);
    save(save_path, 'data');
    fprintf('Processed %s: %d images, saved to %s\n', mainResultsFolder(1).name, nFiles, save_path);
