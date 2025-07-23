function resized_mask = resizeMaskToBFWidth(mask_img, bf_img)
% Resize mask image based on the width of the BF image, preserving aspect ratio

    % Get the target width from the BF image
    target_width = size(bf_img, 2);

    % Get original dimensions of the mask
    [h_mask, w_mask, ~] = size(mask_img);

    % Calculate scale factor to match the width
    scale = target_width / w_mask;

    % Resize mask with preserved aspect ratio
    resized_mask = imresize(mask_img, scale);
end