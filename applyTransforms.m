%% Introduce folder pathes

% main codes path
mainPath = pwd;

% matlab functions path
cd('functions\');
funcPath = pwd;

% main project path
cd(mainPath);
cd('../');
projectPath = pwd;

% modified images path
cd('processed_images\modified_images\');
modifiedImagesPath = pwd;

% TIF raw images path
cd(projectPath);
cd('raw_data\images\tif_images\');
tifRawImagesPath = pwd;

% logs path
cd(projectPath);
cd('logs\');
logsPath = pwd;

%% Channels transformation and alignment
cd(funcPath);
channel = {'ch01', 'ch02'};
for i = 1:length(channel)
    if ~isfile(fullfile(modifiedImagesPath, ['*', channel{i}, '.tif']))
        fprintf('Transformation for channel %s is starting.\n', channel{i});
        affineTransforms(channel{i}, tifRawImagesPath, logsPath, modifiedImagesPath);
    else
        fprintf('File for channel %s already exists. Skipping transformation.\n', channel{1});
    end
end




