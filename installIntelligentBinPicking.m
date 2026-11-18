function installIntelligentBinPicking
% Fetch the IBP example into dependencies/ and apply project-specific patches (Robotics System Toolbox).

projectRoot = fileparts(mfilename('fullpath'));
ibpDir = fullfile(projectRoot, 'dependencies', 'IntelligentBinPickingExample');

fprintf('Fetching IntelligentBinPickingExample...\n');
fprintf('  Dest   : %s\n', ibpDir);
if ~isfolder(ibpDir)
    mkdir(ibpDir);
end

% Fetch example files without opening editors or changing directory
% (extracted from openExample internals)
exampleId = matlab.internal.examples.identifyExample('robotics/IntelligentBinPickingExample');
metadata = findExample(exampleId);
setupExample(metadata, ibpDir);

% Add to path so Simulink can resolve model references during patching
addpath(ibpDir);

% Apply project-specific patches
% Replace files first: loading the models below runs the shipped PreLoadFcn,
% which calls initSim3DRobotModelParam (pcread needs Lidar Toolbox, and the
% unpatched script saves generateParam.mat to pwd).
fprintf('Applying customizations...\n');
patchReplaceFiles(projectRoot, ibpDir);
patchSim3DModel(ibpDir);            % loads Simulink_3D_IBP_Target once, applies all its patches
patchChompCallbacks(ibpDir);

fprintf('Done. Verify the install with runtests("test/testBinPickingExample.m").\n');
end

% Target model patches (loaded once)

function patchSim3DModel(ibpDir)
% Load Simulink_3D_IBP_Target once, apply all its patches in memory, then save and close once.

    modelName = 'Simulink_3D_IBP_Target';
    modelPath = fullfile(ibpDir, [modelName '.slx']);
    if ~isfile(modelPath)
        fprintf('  patchSim3DModel: %s not found, skipping.\n', modelName);
        return
    end

    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    load_system(modelPath);
    patchActorScript(modelName);
    patchMotionRequestPort(modelName);
    patchModelCallbacks(modelName);
    patchCameraViewOutputs(modelName);
    patchExportCameraView(modelName);
    patchDisableSimWindow(modelName);

    save_system(modelName, modelPath);
    close_system(modelName, 0);
end


function patchCameraViewOutputs(modelName)
% Tap the Simulation 3D Camera Image output with a live display.
%   - "Camera View" (To Video Display) shows the camera feed during simulation.

    cameraBlock = [modelName '/Simulation 3D Camera'];
    if getSimulinkBlockHandle(cameraBlock, true) == -1
        fprintf('  patchCameraViewOutputs: Simulation 3D Camera not found, skipping.\n');
        return
    end

    % Image is output port 1 of the camera.
    imagePort = get_param(cameraBlock, 'PortHandles').Outport(1);

    % To Video Display named "Camera View"
    displayBlock = [modelName '/Camera View'];
    if getSimulinkBlockHandle(displayBlock, true) == -1
        add_block('visionsinks/To Video Display', displayBlock);
        camPos = get_param(cameraBlock, 'Position');
        set_param(displayBlock, 'Position', camPos + [420 -80 420 -80]);
        dispPort = get_param(displayBlock, 'PortHandles').Inport(1);
        add_line(modelName, imagePort, dispPort, 'autorouting', 'on');
        fprintf('  patchCameraViewOutputs: added Camera View (To Video Display).\n');
    else
        fprintf('  patchCameraViewOutputs: Camera View already present.\n');
    end
end

function patchExportCameraView(modelName)
% Add a second overhead camera ("Simulation 3D Camera 2") feeding a live
% display ("3D View") and a frame logger ("Video To Workspace").
%   - Simulation 3D Camera 2 : documentation viewpoint of the bin and tables.
%   - 3D View (To Video Display) : live feed during simulation.
%   - Video To Workspace : logs frames to base workspace variable "vout".
%     Commented out by default; uncomment only to export frames for GIFs.

    cameraBlock = [modelName '/Simulation 3D Camera 2'];
    displayBlock = [modelName '/3D View'];
    loggerBlock = [modelName '/Video To Workspace'];

    % Idempotent: skip if the camera is already present.
    if getSimulinkBlockHandle(cameraBlock, true) ~= -1
        fprintf('  patchExportCameraView: already present.\n');
        return
    end

    % Second camera: documentation viewpoint. Copy the first camera's
    % configuration (coordinate system, Scene Origin mount parent, optics
    % referencing base-workspace f/cx_camera/imageSize, FOV) so the two cameras
    % agree on frame and intrinsics; only the mounting pose differs. The pose
    % offsets below were tuned in the Scene Origin / ISO8855 frame, so the
    % coordinate system MUST match Camera 1 for them to land on the intended
    % side view of the bin and both tables.
    add_block('sim3dcameralib/Simulation 3D Camera', cameraBlock);
    set_param(cameraBlock, 'Position', [2185 1730 2385 1840]);
    set_param(cameraBlock, 'sensorName', 'Sim3dSensor');

    sourceCamera = [modelName '/Simulation 3D Camera'];
    inheritedParams = {'CoordinateSystem', 'vehTag', 'mountLoc', 'offsetFlag', ...
        'FocalLength', 'OpticalCenter', 'ImageSize', 'RadialDistortion', ...
        'TangentialDistortion', 'SensorSkew', 'FieldOfViewRange', ...
        'VisualizeFieldOfView'};
    for k = 1:numel(inheritedParams)
        set_param(cameraBlock, inheritedParams{k}, ...
            get_param(sourceCamera, inheritedParams{k}));
    end

    % Mounting pose: tuned side view (differs from the overhead Camera 1).
    % tmountOffset moved in from Y=2.3->1.9 and lowered 1.6->1.5; rmountOffset
    % is the iterB side-view angle.
    set_param(cameraBlock, 'tmountOffset', '[0.5 1.9 1.5]');
    set_param(cameraBlock, 'rmountOffset', '[0 20 270]');

    % Documentation camera needs only the image output; keep depth off so there
    % is no dangling depth port (Camera 1 enables depth for the detection path).
    set_param(cameraBlock, 'DepthOutportEnabled', 'off');

    % Live display of the documentation camera feed.
    add_block('visionsinks/To Video Display', displayBlock);
    set_param(displayBlock, 'Position', [2460 1731 2660 1839]);

    % Frame logger: export the full simulation, skipping frames to keep the
    % logged variable manageable. DataLimit=inf keeps every logged frame (not
    % just the last); DecimationFactor=10 logs every 10th frame. Commented out
    % by default; uncomment only when exporting frames for documentation GIFs.
    add_block('visionsinks/Video To Workspace', loggerBlock);
    set_param(loggerBlock, 'Position', [2525 1877 2625 1953]);
    set_param(loggerBlock, 'VariableName', 'vout');
    set_param(loggerBlock, 'NumInputs', '1');
    set_param(loggerBlock, 'InPortLabels', 'R|G|B');
    set_param(loggerBlock, 'DataLimit', 'inf');
    set_param(loggerBlock, 'DecimationFactor', '10');
    set_param(loggerBlock, 'Commented', 'on');

    % Wire camera image (output port 1) to both sinks.
    imagePort = get_param(cameraBlock, 'PortHandles').Outport(1);
    add_line(modelName, imagePort, ...
        get_param(displayBlock, 'PortHandles').Inport(1), 'autorouting', 'on');
    add_line(modelName, imagePort, ...
        get_param(loggerBlock, 'PortHandles').Inport(1), 'autorouting', 'on');

    fprintf('  patchExportCameraView: added Simulation 3D Camera 2, 3D View, Video To Workspace.\n');
end

function patchDisableSimWindow(modelName)
% Turn off "Display 3D Simulation Window" on the Simulation 3D Scene Configuration block.

    blockPath = [modelName '/Simulation 3D Scene Configuration'];
    if getSimulinkBlockHandle(blockPath, true) == -1
        fprintf('  patchDisableSimWindow: Scene Configuration not found, skipping.\n');
        return
    end

    if strcmp(get_param(blockPath, 'EnableWindow'), 'off')
        fprintf('  patchDisableSimWindow: already off.\n');
        return
    end

    set_param(blockPath, 'EnableWindow', 'off');
    fprintf('  patchDisableSimWindow: disabled Display 3D Simulation Window.\n');
end

function patchActorScript(modelName)
% Replace the Sim3D scene script with a call to initSim3DSceneActors (copied into the
% example folder by patchReplaceFiles), which adds per-part color cycling.

    blockPath = [modelName '/Sim3D Scene Generation/Simulation 3D Actor7'];
    set_param(blockPath, 'InitScriptText', 'initSim3DSceneActors(Actor, World);');
    fprintf('  patchActorScript: InitScriptText calls initSim3DSceneActors.\n');
end

function patchMotionRequestPort(modelName)
% Rename the target model motion input port to Motion Request.

    oldPort = [modelName '/Motion Planner Command'];
    if getSimulinkBlockHandle(oldPort, true) ~= -1
        set_param(oldPort, 'Name', 'Motion Request');
        fprintf('  patchMotionRequestPort: renamed Motion Planner Command.\n');
    else
        fprintf('  patchMotionRequestPort: already named Motion Request.\n');
    end
end

function patchModelCallbacks(modelName)
% Set PreLoadFcn on an already-loaded model that needs workspace vars.

    set_param(modelName, 'PreLoadFcn', 'robotSimParams');
    set_param(modelName, 'InitFcn', '');
    fprintf('  patchModelCallbacks: %s\n', modelName);
end

% Standalone patches (other models / files)

function patchChompCallbacks(ibpDir)
% Set PreLoadFcn on the CHOMP referenced model that needs workspace vars.

    modelName = 'CHOMP_Trajectory_Planner_Module';
    modelPath = fullfile(ibpDir, [modelName '.slx']);
    if ~isfile(modelPath)
        fprintf('  patchChompCallbacks: %s not found, skipping.\n', modelName);
        return
    end

    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    load_system(modelPath);
    patchModelCallbacks(modelName);

    save_system(modelName, modelPath);
    close_system(modelName, 0);
end

function patchReplaceFiles(projectRoot, ibpDir)
% Copy the patched files in dependencies/IntelligentBinPickingPatches into the example folder.
%   - initSim3DRobotModelParam.m : comments out pcread/im2uint8/ptCloud lines (LIDAR/Image
%     Processing), pins generateParam.mat next to the script instead of pwd, and
%     replaces the spawn points with a random drop layout when actorSeed is set (Reshuffle Layout).
%   - initSim3DSceneActors.m : new file; the Sim3D scene script called from the Actor7
%     InitScriptText (patchActorScript), with per-part color cycling.

    patchDir = fullfile(projectRoot, 'dependencies', 'IntelligentBinPickingPatches');
    fileNames = {'initSim3DRobotModelParam.m', 'initSim3DSceneActors.m'};
    for k = 1:numel(fileNames)
        srcPath = fullfile(patchDir, fileNames{k});
        if ~isfile(srcPath)
            fprintf('  patchReplaceFiles: %s not found in patches, skipping.\n', fileNames{k});
            continue
        end
        copyfile(srcPath, fullfile(ibpDir, fileNames{k}), 'f');
        fprintf('  patchReplaceFiles: replaced %s.\n', fileNames{k});
    end
end
