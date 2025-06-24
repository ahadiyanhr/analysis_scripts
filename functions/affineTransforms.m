function affineTransforms(channel, imgFolder, logFolder, outputFolder)
    %     channel = {'ch01', 'ch02'};  % Channel identifiers

    % Parameters
    logFilePath = fullfile(logFolder, 'transform.txt');
    
    % Step 1: Read and parse affine matrices from Log.txt
    fid = fopen(logFilePath, 'rt');
    if fid == -1
        error('Cannot open Log.txt at %s', logFilePath);
    end
    lines = textscan(fid, '%s', 'Delimiter', '\n'); fclose(fid);
    lines = lines{1};
    
    % Pattern to extract affine matrix components
    pattern = 'AffineTransform\[\[(.*?), (.*?), (.*?)\], \[(.*?), (.*?), (.*?)\]\]';
    matrices = {};
    for i = 1:length(lines)
        line = strtrim(lines{i});
        if contains(line, 'AffineTransform')
            tokens = regexp(line, pattern, 'tokens');
            if ~isempty(tokens)
                vals = str2double(tokens{1});
                Transforms = [vals(1), vals(2), vals(3), 0;
                     vals(4), vals(5), vals(6), 0;
                     0,       0,       1, 0;
                     0,       0,       0, 1];
                matrices{end+1} = Transforms;
            end
        end
    end
    numFrames = length(matrices);
    
    % Step 2: Start transforming
    chFiles = dir(fullfile(imgFolder, ['*' channel '*.tif']));
    [~, sortIdx] = sort({chFiles.name});
    chFiles = chFiles(sortIdx);

    if length(chFiles) < numFrames+1
        warning('Fewer image files than transformation matrices for %s', channel);
    end

    % Process timepoint 00
    imgPath = fullfile(chFiles(1).folder, chFiles(1).name);
    img = imread(imgPath);

    % Save image
    outName = sprintf('t00_%s.tif', channel);
    outPath = fullfile(outputFolder, outName);
    imwrite(img, outPath);
    
    % Process each timepoint after 00
    Transforms = cell(1, min(numFrames, length(chFiles)));
    Transforms{1} = eye(3);
    
    for i = 2:min(numFrames, length(chFiles))
        imgPath = fullfile(chFiles(i).folder, chFiles(i).name);
        img = imread(imgPath);

        % Convert to grayscale if RGB
        if ndims(img) == 3
            img = rgb2gray(img);
        end
        
        % Apply affine transformation
        if i > 2
            Transforms{i} = matrices{i-1}+Transforms{i-1};
            Transforms{i}(logical(eye(size(Transforms{i})))) = Transforms{i}(logical(eye(size(Transforms{i}))))/2;
        else
            Transforms{i} = matrices{i-1};
        end

        tform = affinetform2d(Transforms{i}(1:3, 1:3));
        outputImg = imwarp(img, tform, 'OutputView', imref2d(size(img)));

        % Save image
        [~, name, ext] = fileparts(chFiles(i).name);
        
        % Extract time index from image order
        timeIndex = sprintf('t%02d', i-1);  % i-1 because t00 is first
        
        % Construct output filename like t00_ch01.tif or t01_ch02.tif
        outName = sprintf('%s_%s.tif', timeIndex, channel);
        outPath = fullfile(outputFolder, outName);
        imwrite(outputImg, outPath);
    end
    
    fprintf('✅ Done: Transformed images for %s saved in modified_images\n', channel);
end