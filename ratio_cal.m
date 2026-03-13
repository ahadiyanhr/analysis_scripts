%% === SETTINGS ===
blk     = 20;       % block size (20x20)

clc;

%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Log path
cd(projectPath);
cd('logs\');
logPath = pwd;

% DO ratio path
cd(projectPath);
cd('processed_data\do_ratio\');
doRatioPath = pwd;

% Registered images path
cd(projectPath);
cd('processed_images\registered_images\');
registeredPath = pwd;

% GFP images path
cd(projectPath);
cd('raw_data\images\gfp_channel\');
gfpPath = pwd;



%% ---- Calculate Ratio of FRET to GFP ----
% There is only one GFP image
% Open file selection dialog for images
[file, path] = uigetfile( ...
    {'*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', 'Image Files'}, ...
    'Select an Image', ...
    'MultiSelect', 'off', ...
    gfpPath);

% Check if user selected a file
if isequal(file,0)
    disp('User canceled selection');
else
    fullFileName = fullfile(path, file);
    gfpImg = imread(fullFileName);
end

% Reading all FRET images
fretFiles = dir(fullfile(registeredPath, '*ch01*.tif')); % FRET channel

[~, idx] = sort({fretFiles.name});
fretFiles = fretFiles(idx);

% Start the process
fprintf('\n📈 Computing FRET/GFP ratio for %d images...\n', numel(fretFiles));

% First: Single GFP image
% Convert to double
gfpImg = double(gfpImg);

% Avoid divide-by-zero
gfpImg(gfpImg == 0) = NaN;

% Calculate average GFP intensity
gfpMean = nanmean(gfpImg(:));

for i = 1:numel(fretFiles)
    fretImg = imread(fullfile(registeredPath, fretFiles(i).name));

    % Convert to double
    fretImg = double(fretImg);

    % Ratio calculation
    do_ratio = fretImg ./ gfpMean;
    % ratioImg = fretImg ./ gfpMean;
    % 
    % if i == 1
    %     ratioBias = ratioImg - nanmean(ratioImg(:));
    % end
    % 
    % do_ratio = ratioImg - ratioBias;
  
    %% SAVE RESULTS
      
    % Get timepoint label from filename
    [~, baseName, ~] = fileparts(fretFiles(i).name);
    timeLabel = extractBefore(baseName, '_ch01');
    ratioMapName = fullfile(doRatioPath, sprintf('ratio_%s.mat', timeLabel));
    
    % Save ratio image as .mat
    save(ratioMapName, 'do_ratio', '-v7.3');
    fprintf('✅ Saved ratio image: %s\n', ratioMapName);
    
end

fprintf('\nDone! All ratio images saved in: do_ratio.mat\n');

