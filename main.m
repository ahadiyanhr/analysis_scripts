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






