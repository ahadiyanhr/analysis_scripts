%% -------- Setup --------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Biomass occupation data folder path
cd(projectPath);
cd('processed_data\biomass_occupation\');
biomassDataPath = pwd;

% Plot folder path
cd(projectPath);
cd('processed_data\plots\');
plotsPath = pwd;

%% ---- Starting process ----

% Get list of .mat files
mat_files = dir(fullfile(biomassDataPath, '*.mat'));

% Create figure
figure;
hold on;

% Define colors/markers for differentiation
colors = lines(length(mat_files));
legend_entries = {};

for k = 1:length(mat_files)
    % Load data
    file_path = fullfile(biomassDataPath, mat_files(k).name);
    loaded = load(file_path);
    data = loaded.data;
    
    % Clean image names (remove extension)
    raw_names = regexprep(data.image_names, '\.(tif|tiff|png|jpg)$', '', 'ignorecase');

    % Extract last two digits from each name
    image_labels = cell(size(raw_names));
    for i = 1:length(raw_names)
        name = raw_names{i};
        digits_match = regexp(name, '\d{2,}$', 'match');
        if ~isempty(digits_match)
            label = digits_match{1}(end-1:end); % get last two digits
        else
            label = name; % fallback if no digits
        end
        image_labels{i} = label;
    end
    
    % Convert labels to numeric indices for x-axis
    x = 1:length(data.biomass_occupation);
    y_original = data.biomass_occupation;
    y_min = min(y_original);
    y_shifted = y_original - y_min;
    
    % Construct legend string
    legend_str = data.parameters.threshold_method;

    % Add non-zero parameters
    if isfield(data.parameters, 'radius') && data.parameters.radius ~= 0
        legend_str = [legend_str, sprintf(', r=%d', data.parameters.radius)];
    end
    if isfield(data.parameters, 'parameters1') && data.parameters.parameters1 ~= 0
        legend_str = [legend_str, sprintf(', p1=%d', data.parameters.parameters1)];
    end
    if isfield(data.parameters, 'parameters2') && data.parameters.parameters2 ~= 0
        legend_str = [legend_str, sprintf(', p2=%d', data.parameters.parameters2)];
    end

    % Plot
    plot(x, y_shifted, 'o-', 'Color', colors(k,:), 'DisplayName', legend_str);

    % Store x-ticks from the first data file only (assumes same images across methods)
    if k == 1
        xticks(x);
        xticklabels(image_labels);
        xtickangle(45);
    end
end

% Final plot formatting
xlabel('Images timepoints');
ylabel('Biomass Occupation (%)');
title('Biomass Occupation - Across Thresholding Methods');
legend('Location', 'bestoutside');
grid on;
hold off;

% Save plot
fig_name = 'biomass_occupation';
saveas(gcf, fullfile(plotsPath, [fig_name, '.png']));  % Save as PNG
saveas(gcf, fullfile(plotsPath, [fig_name, '.fig']));  % Save as MATLAB figure
