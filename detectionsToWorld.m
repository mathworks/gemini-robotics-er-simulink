function results = detectionsToWorld(detections, depthM, camParams, options)
% DETECTIONSTOWORLD  Back-project bounding box centres to world-frame XYZ.
%
%   Uses the same two-stage camera transform as PoseMaskRCNNModel:
%     tform_cam2pts  = eul2tform([-pi/2, 0, -pi/2], "ZYX")   % frame correction
%     tform_org2cam  = eul2tform([rot(3) rot(2) rot(1)], "ZYX") + translation
%     Tform_org2pts  = tform_org2cam * tform_cam2pts
%
%   Inputs:
%     detections - struct array (from geminiDetector):
%                    .label   - 'I','L','T','X'
%                    .box_2d  - [y_min x_min y_max x_max] in pixels
%     depthM     - double [H x W] depth in metres (channel 1 of Sim3D output)
%     camParams  - struct with fields:
%                    .f          - focal length px (scalar, fx=fy)
%                    .cx, .cy    - principal point in pixels
%                    .camera_loc - [1x3] camera position in world frame (m)
%                    .camera_rot - [1x3] ZYX Euler angles (radians)
%
%   Optional name-value:
%     maxBinDistance - depth (m) from camera to bin floor, used only for
%                     height_m computation. Default 0.6 matches cam1
%                     (camera_loc=[0.48,0,1.15]) and maxBinDistance in
%                     PoseMaskRCNN. Use 0.95 for cam2 (camera_loc=[0.5,0,1.5]).
%     outJson       - file path to save results as JSON (default: skip)
%
%   Output:
%     results - struct array with fields:
%                 .label, .box_2d, .uv, .depth_m, .world_xyz, .height_m

arguments
    detections  struct
    depthM      (:,:) double
    camParams   struct
    options.maxBinDistance (1,1) double = 0.6
    options.outJson string = ""
end

maxBinDistance = options.maxBinDistance;

K = [camParams.f, 0,           camParams.cx;
     0,           camParams.f, camParams.cy;
     0,           0,           1           ];

% Match PoseMaskRCNNModel.setupImpl exactly:
%   tform_org2cam uses reversed Euler order [rot(3) rot(2) rot(1)]
rot = camParams.camera_rot(:)';
tform_cam2pts          = eul2tform([-pi/2, 0, -pi/2], "ZYX");
tform_org2cam          = eul2tform([rot(3), rot(2), rot(1)], "ZYX");
tform_org2cam(1:3, 4)  = camParams.camera_loc(:);
Tform_org2pts          = tform_org2cam * tform_cam2pts;

R_total = Tform_org2pts(1:3, 1:3);
t_total = Tform_org2pts(1:3, 4);

p_floor  = K \ [camParams.cx; camParams.cy; 1] * maxBinDistance;
xyz_floor = R_total * p_floor + t_total;

results = struct('label',{}, 'box_2d',{}, 'uv',{}, 'depth_m',{}, 'world_xyz',{}, 'height_m',{});

for i = 1:numel(detections)
    box = detections(i).box_2d;          % [y_min x_min y_max x_max]
    u   = (box(2) + box(4)) / 2;
    v   = (box(1) + box(3)) / 2;

    row = max(1, min(round(v), size(depthM,1)));
    col = max(1, min(round(u), size(depthM,2)));
    depth = depthM(row, col);

    p_cam = K \ [u; v; 1] * depth;
    xyz   = R_total * p_cam + t_total;

    results(i).label     = detections(i).label;
    results(i).box_2d    = box;
    results(i).uv        = [u, v];
    results(i).depth_m   = depth;
    results(i).world_xyz = xyz(:)';
    results(i).height_m  = abs(xyz_floor(3) - xyz(3));

    fprintf('  %s  uv=(%.0f,%.0f)  depth=%.3fm  xyz=[%.3f, %.3f, %.3f]  height=%.3fm\n', ...
        detections(i).label, u, v, depth, xyz(1), xyz(2), xyz(3), results(i).height_m);
end

if strlength(options.outJson) > 0
    fid = fopen(options.outJson, 'w');
    fprintf(fid, '%s', jsonencode(results, 'PrettyPrint', true));
    fclose(fid);
    fprintf('Saved: %s\n', options.outJson);
end
end
