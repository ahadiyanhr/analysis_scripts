%% rename_tif_sequence.m
%
% Renames .tif files in the CURRENT FOLDER (pwd) from timestamp-based
% filenames (e.g. 202607211658.tif) into a sequential stitched format:
% stitched_t00_ch00.tif, stitched_t01_ch00.tif, ...
%
% Files are ordered by filename (ascending), which is correct as long
% as all filenames are same-length date strings like YYYYMMDDHHMM.tif.
%
% This uses movefile(), which RENAMES the file in place -- it does not
% create a copy or a new file.
%
% USAGE:
%   Put this script in the folder with the .tif files (or cd into that
%   folder first), then run it in MATLAB.

% TIF raw images path
cd('../');
cd('raw_data\images\bf_red_channel\');
folder = pwd;

files = dir(fullfile(folder, '*.tif'));
files = files(~[files.isdir]);

if isempty(files)
    error('No .tif files found in: %s', folder);
end

% Sort by filename ascending (= chronological order for date-stamped names)
[~, sortIdx] = sort({files.name});
files = files(sortIdx);

nFiles = numel(files);
padWidth = 2;
if nFiles > 99
    padWidth = 3;
end

fprintf('Found %d .tif files in: %s\n', nFiles, folder);
fprintf('Renaming in ascending filename (date) order...\n\n');

for i = 1:nFiles
    oldName = files(i).name;
    oldPath = fullfile(folder, oldName);

    idxStr = sprintf(['%0' num2str(padWidth) 'd'], i-1);
    newName = sprintf('stitched_t%s_ch00.tif', idxStr);
    newPath = fullfile(folder, newName);

    if isfile(newPath) && ~strcmp(oldPath, newPath)
        warning('Target name already exists, skipping: %s', newName);
        continue
    end

    fprintf('  %s  -->  %s\n', oldName, newName);
    [ok, msg] = movefile(oldPath, newPath);

    if ~ok
        warning('Failed to rename %s: %s', oldName, msg);
    end
end

fprintf('\nDone. Renamed %d files.\n', nFiles);