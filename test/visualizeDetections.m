function fig = visualizeDetections(img, dets, options)
% visualizeDetections  Draw detection bounding boxes and centres on an image.
%
%   fig = visualizeDetections(img, dets)
%   fig = visualizeDetections(img, dets, SavePath="out.png")
%
%   img  - uint8 [H x W x 3] RGB image
%   dets - struct with fields (geminiTaskPlannerBus format):
%            .count     — number of valid detections
%            .boxes     — [MaxDetections x 4] [y_min x_min y_max x_max] px
%            .world_xyz — [MaxDetections x 3] world-frame XYZ (m)
%
%   Options:
%     SavePath — file path to save the figure (default: skip)
%     Visible  — figure visibility: "on" | "off" (default: "off")

arguments
    img     (:,:,3) uint8
    dets    struct
    options.SavePath (1,1) string = ""
    options.Visible  (1,1) string = "off"
end

fig = figure('Visible', options.Visible);
imshow(img); hold on;

N      = dets.count;
colors = lines(max(N, 1));

for i = 1:N
    box = dets.boxes(i,:);          % [y_min x_min y_max x_max]
    x0  = box(2);  y0 = box(1);
    w   = box(4) - box(2);
    h   = box(3) - box(1);
    cx  = (box(2) + box(4)) / 2;
    cy  = (box(1) + box(3)) / 2;

    rectangle('Position', [x0, y0, w, h], ...
        'EdgeColor', colors(i,:), 'LineWidth', 2);

    plot(cx, cy, '+', ...
        'Color', colors(i,:), 'MarkerSize', 14, 'LineWidth', 2);

    text(x0, max(y0 - 6, 1), ...
        sprintf('[%.2f, %.2f, %.2f] m', ...
            dets.world_xyz(i,1), dets.world_xyz(i,2), dets.world_xyz(i,3)), ...
        'Color', colors(i,:), 'FontSize', 8, 'FontWeight', 'bold', ...
        'BackgroundColor', [0 0 0 0.6]);
end

title(sprintf('%d detection(s)', N), 'Color', 'w', 'FontSize', 12);
set(gcf, 'Color', 'k');

if strlength(options.SavePath) > 0
    exportgraphics(fig, options.SavePath, 'Resolution', 150);
    fprintf('Saved: %s\n', options.SavePath);
end
end
