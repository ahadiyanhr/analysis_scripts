function tforms = readAffineTransforms(tform0, logFolder)
    % Reads affine transformation matrices from a log file and processes them.

    % Construct the path to the log file
    logFilePath = fullfile(logFolder, 'transform_matrices.txt');
    
    % Step 1: Read and parse affine matrices from the log file
    fid = fopen(logFilePath, 'rt');
    if fid == -1
        error('Cannot open transform_matrices.txt at: %s', logFilePath);
    end

    if ~isa(tform0, 'affine2d')
        disp('This is NOT an affine2d transform.');
        return;
    end
    
    lines = textscan(fid, '%s', 'Delimiter', '\n'); 
    fclose(fid);
    lines = lines{1};

    % Pattern to extract the 6 components of 2D affine transform
    pattern = 'AffineTransform\[\[(.*?), (.*?), (.*?)\], \[(.*?), (.*?), (.*?)\]\]';

    % Initialize cell array to store 4x4 affine matrices
    matrices = {};
    for i = 1:length(lines)
        line = strtrim(lines{i});
        if contains(line, 'AffineTransform')
            tokens = regexp(line, pattern, 'tokens');
            if ~isempty(tokens)
                vals = str2double(tokens{1});
                % Construct a 4x4 affine matrix for 3D compatibility
                matrix = [vals(1), vals(2), vals(3);
                          vals(4), vals(5), vals(6);
                          0, 0, 1];
                matrices{end+1} = matrix;
            end
        end
    end

    numTransforms = length(matrices);
    if numTransforms == 0
        error('No affine matrices found in the log file.');
    end

    % Initialize output variable to store cumulative or adjusted transforms
    tforms = cell(numTransforms+1, 1);
    transforms = cell(numTransforms, 1);

    tforms{1} = tform0;

    for i = 1:numTransforms
        if i > 1
            % Example logic: blend current with previous transform
            transforms{i} = matrices{i} + transforms{i-1};
            transforms{i}(logical(eye(3))) = transforms{i}(logical(eye(3))) / 2;
        else
            transforms{i} = matrices{i};
        end
        
        tform = affine2d(transforms{i}');
        tforms{i+1} = affine2d((tform.T)*(tform0.T));
    end

    % Example display or saving logic
    fprintf('Parsed and processed %d affine transformation matrices.\n', numTransforms);

end