%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Thresholded folder path
cd('processed_images\thresholded_images\');
threshImagesPath = pwd;

% Biomass occupation data folder path
cd(projectPath);
cd('processed_data\biomass_occupation\');
biomassDataPath = pwd;

%% ---- Starting process ----

% Get list of subfolders
subfolders = dir(threshImagesPath);
subfolders = subfolders([subfolders.isdir] & ~startsWith({subfolders.name}, '.'));

% Loop over each subfolder
for k = 1:length(subfolders)
    subfolder_name = subfolders(k).name;
    input_subfolder = fullfile(threshImagesPath, subfolder_name);
    
    % Initialize struct to hold results
    data = struct();
    data.method = subfolder_name;
    data.biomass_occupation = [];
    data.image_names = {};
    
    % Read and parse thresholding parameters
    param_file = fullfile(input_subfolder, 'thresholding_parameters.txt');
    data.parameters = struct(); % initialize empty struct
    if isfile(param_file)
        fid = fopen(param_file, 'r');
        lines = {};
        while ~feof(fid)
            lines{end+1} = strtrim(fgetl(fid)); %#ok<SAGROW>
        end
        fclose(fid);
        
        % Parse lines
        for i = 1:length(lines)
            line = lines{i};
            if contains(line, '=')
                parts = strsplit(line, '=');
                key = strtrim(lower(parts{1}));
                value = strtrim(parts{2});
                
                switch key
                    case 'threshold_method'
                        data.parameters.threshold_method = value;
                    case 'radius'
                        data.parameters.radius = str2double(value);
                    case 'parameters1'
                        data.parameters.parameters1 = str2double(value);
                    case 'parameters2'
                        data.parameters.parameters2 = str2double(value);
                end
            elseif contains(line, 'Saved on Date')
                date_parts = strsplit(line, ':');
                if numel(date_parts) >= 3
                    data.parameters.saved_date = strtrim(strrep(date_parts{2}, 'Time', ''));
                    data.parameters.saved_time = strtrim(date_parts{3});
                end
            end
        end
    else
        warning('Parameter file not found in %s', input_subfolder);
    end

    % Process image files
    image_files = dir(fullfile(input_subfolder, '*.tif')); % change extension if needed
    for i = 1:length(image_files)
        img_path = fullfile(input_subfolder, image_files(i).name);
        img = imread(img_path);
        
        % Convert to logical if necessary
        if ~islogical(img)
            img = img > 0;
        end
        
        biomass_percent = 100 * sum(img(:)) / numel(img);
        data.biomass_occupation(end+1) = biomass_percent;
        data.image_names{end+1} = image_files(i).name;
    end
    
    % Save results
    save_path = fullfile(biomassDataPath, [subfolder_name, '.mat']);
    save(save_path, 'data');
    
    fprintf('Processed %s: %d images, saved to %s\n', subfolder_name, length(image_files), save_path);
end
