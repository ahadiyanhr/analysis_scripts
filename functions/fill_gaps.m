function f = fill_gaps(Density_original_reshaped)

new_play = Density_original_reshaped;
[Nx, Ny] = size(new_play);

new_play_updated = new_play;

% Define window size
w = 3; % Half-window: total window is (2*w+1) x (2*w+1) centered on each point

for i = 1:Nx
    for j = 1:Ny
        if new_play(i,j) == 1
            % Define local window boundaries
            iMin = max(1, i-w);
            iMax = min(Nx, i+w);
            jMin = max(1, j-w);
            jMax = min(Ny, j+w);

            % Extract local window
            local_window = new_play(iMin:iMax, jMin:jMax);

            % Find fractional values in the window
            local_fractions = local_window(local_window < 1 & local_window > 0);
            has_nan = any(isnan(local_window), 'all');

            % If both NaN and some fraction exist in window, replace with mean
            if has_nan && ~isempty(local_fractions)
                new_play_updated(i,j) = mean(local_fractions(:), 'omitnan');
            end
        end
    end
end

f = new_play_updated;

end