% initSim3DRobotModelParam  Initialize parameters for perception, motion planning, and integration.
%
% This function is for internal use only and may be removed in the future.
%
% This script contains parameters used in the project's perception, motion planning, and integration modules.
% It runs at project initialization. Modify these parameters if using a different setup.

%   Copyright 2025 The MathWorks, Inc.

%% New Define camera parameters
imageSize = [720 1280];
f = 750;
depth_imageSize = [720, 1280];
cx_camera = imageSize(2)/2; % Principal point
cy_camera = imageSize(1)/2; % Principal point
IntrinsicMatrix = [f,0,0; 0,f,0; imageSize(2)/2, imageSize(1)/2,1];

% Camera pose (location and orientation)
camera_loc = [0.48, 0, 1.15];
camera_rot = ([pi/2, pi/2,pi/2]);

%% Get parts
% Synthetic Dataset Generation for Simulink 3D Animation Actors
% Initialize
rng('default');

% load  model point cloud (visualize ground truth)
% model key set
model_keys = ["Ishape", "Xshape", "Lshape", "Tshape"];
%PATCHED: model_ptClouds = struct();
objectCount = 1;
for aKey = model_keys
    ptFile = aKey + ".ply";
    if ~exist(ptFile, "file")
        continue
    end
%PATCHED:     model_ptClouds(objectCount).name = aKey;
%PATCHED:     model_ptClouds(objectCount).ptCloud = pcread(ptFile);
    objectCount = objectCount+1;
end

% make dictionary for name - point cloud dictionary
%PATCHED: model_dict = dictionary(model_keys, horzcat(model_ptClouds(:).ptCloud));
%PATCHED: colorTable = im2uint8(lines(numel(model_keys)));

% Initialize 3D foundation
% Parameters to change
numSynthData = 2;
numInstEachObj = 2; % number of instance of each parts. ex: for 4 classes numInstEachObj = 4 means there will Be 16 parts in the image

% Setting for simulation parameters
param.model_files = model_keys + ".stl";
param.numInstEachObj = numInstEachObj; % number of objects per each model
param.rand_seed = 'default';
param.shininesses = linspace(0, 1, numSynthData); % object shininess params list. If it's array, shininess changes iteratively

% random seed setting
rng(param.rand_seed);
instance_label_offset = 100; % segmentation instance label. small number is reserved as semantic label so plus 100 to skip reserved values

% Simulation model name
simulink_model_name = "simulateManipulatorGrasp";

% Simulation actor configuration table
datasetBboxes = table;
n_sim = 1;
dataInstace =1;
param.Color = [0.85 0.85 0.85];
param.Metallic = 0.4;
param.Flat = 1;
param.TrayColor = [0.2784,0.2667,0.6824];
param.TrayMetallic = 0.4;
param.TrayShininess = 0.4;
param.Shininess =0.1;

% Calculate object spawn points
baseLocations = [0.38 -0.19 0.57;
    0.38 0.06 0.57;
    0.34 0.14 0.57;
    0.47 0.2 0.57;
    0.48 0 0.57;
    0.47 -0.15 0.57;
    0.55 0.10 0.57;
    0.57 -0.1 0.57];
model_pathes = param.model_files;

% Change spawn points randomly
%PATCHED: actorSeed (base workspace, set by the Reshuffle Layout button) replaces
% the shipped spawn points with a random drop layout; [] or unset keeps the
% shipped layout. Spawning here keeps pose_list and the binActor*SequenceInfo
% grasp lookup tables in sync: the gripper attaches the binActor whose spawn
% (x,y) is nearest the grasp point.
%   - (x,y) uniform over the tray floor (inner walls x 0.284..0.676, y +/-0.285),
%     5.5 cm off the walls (a tee's corner reaches 5.4 cm from its origin).
%   - Spawns at least 11 cm apart, so no two parts overlap at release (overlap
%     at spawn can push a part through the tray floor) and the nearest-spawn
%     lookup survives the few cm they slide while settling.
%   - Released at z 0.62, ~5 cm above the resting height (0.57) and ~2.5 cm above
%     the rim (0.596), so parts fall and settle without bouncing out.
if exist('actorSeed', 'var') && ~isempty(actorSeed)
    rng(actorSeed);
    baseLocations(:, 1:2) = sampleSpawnPoints(height(baseLocations), ...
        [0.339 0.621], [-0.23 0.23], 0.11);
    baseLocations(:, 3) = 0.62;
end
access_indices = randperm(param.numInstEachObj * numel(param.model_files));
binActorTranslationSequenceInfo =zeros(8,3);
binActorRotationSequenceInfo =zeros(8,1);

% Save each object parameter in pose list
objectCount = 1; clear pose_list;
for model_path = model_pathes
    for i = 1:param.numInstEachObj
        ai = access_indices(objectCount);
        loc = baseLocations(ai, :);
        binActorTranslationSequenceInfo(objectCount,:) = loc;

        if mod(objectCount,2)~=0
            rot = [0,0,1/12] * 2 * pi;
        else
            rot = [0,0,1/6] * 2 * pi;
        end

        binActorRotationSequenceInfo(objectCount,1)= rot(3);
        [~,name,~] = fileparts(model_path);

        pose_list(objectCount).loc = loc; % location
        pose_list(objectCount).rot = rot; % orientation
        pose_list(objectCount).model_path = model_path; % model path for point cloud
        pose_list(objectCount).model_name = name; % model key name
        pose_list(objectCount).instance_label = instance_label_offset + objectCount; % segmentation instance label. small number is reserved as semantic label so plus 100 to skip reserved values
        objectCount = objectCount + 1;
    end
end

% save pose list as mat In Simulink model load this in 'Initialization scripts'.
param.pose_list = pose_list;
save(fullfile(fileparts(mfilename("fullpath")),"generateParam.mat"), "param");

% LocalWords:  Ishape Xshape Lshape Tshape stl

function xy = sampleSpawnPoints(n, xLimits, yLimits, minSpacing)
%PATCHED: rejection-sample n (x,y) points in the box, pairwise >= minSpacing apart.
xy = zeros(n, 2);
count = 0;
for k = 1:100000
    candidate = [xLimits(1) + diff(xLimits)*rand, yLimits(1) + diff(yLimits)*rand];
    if all(vecnorm(xy(1:count, :) - candidate, 2, 2) >= minSpacing)
        count = count + 1;
        xy(count, :) = candidate;
        if count == n
            return
        end
    end
end
error('sampleSpawnPoints: could not place %d parts %.2f m apart.', n, minSpacing);
end
