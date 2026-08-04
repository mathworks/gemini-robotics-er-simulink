function installIntelligentBinPicking
% installIntelligentBinPicking  Fetch and patch IntelligentBinPickingExample files.
%   Downloads the IBP example into dependencies/IntelligentBinPickingExample/
%   and applies project-specific patches:
%
%     1. patchActorColors — assigns distinct colors (red, green, blue, cyan,
%        magenta, black) to bin parts so objects are visually distinguishable.
%     2. patchSolverAndVideo — sets fixed-step size to 0.01 s and comments
%        out the Simulation 3D Video Writer block by default.
%
%   Called automatically by projectstartup on first run.
%   Can also be run manually to refresh the local copy.
%
%   Requires: Robotics System Toolbox

projectRoot = fileparts(mfilename('fullpath'));
destDir = fullfile(projectRoot, 'dependencies', 'IntelligentBinPickingExample');

fprintf('Fetching IntelligentBinPickingExample...\n');
fprintf('  Dest   : %s\n', destDir);
if ~isfolder(destDir)
    mkdir(destDir);
end

% Fetch example files without opening editors or changing directory
% (extracted from openExample internals)
exampleId = matlab.internal.examples.identifyExample('robotics/IntelligentBinPickingExample');
metadata = findExample(exampleId);
setupExample(metadata, destDir);

% Add to path so Simulink can resolve model references during patching
addpath(destDir);

% Apply project-specific patches
fprintf('Applying customizations...\n');
patchActorColors(destDir);
patchSolverAndVideo(destDir);
patchModelCallbacks(destDir);
patchRemoveToolboxDeps(destDir);

fprintf('Done.\n');
end

% ── Patches ──────────────────────────────────────────────────────────────────

function patchSolverAndVideo(ibpDir)
% patchSolverAndVideo  Set fixed-step size to 0.01 s.
%
% Also documents how to configure the Simulation 3D Video Writer filename
% (commented out — uncomment to enable AVI recording).

    modelName = 'Simulink_3D_IBP_Target';
    modelPath = fullfile(ibpDir, [modelName '.slx']);

    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    load_system(modelPath);

    % Set fixed-step solver step size
    if ~strcmp(get_param(modelName, 'FixedStep'), '0.01')
        set_param(modelName, 'FixedStep', '0.01');
        fprintf('  patchSolverAndVideo: FixedStep set to 0.01.\n');
    else
        fprintf('  patchSolverAndVideo: FixedStep already 0.01.\n');
    end

    % Add a Simulation 3D Video Writer block (not in original model) and
    % comment it out by default — uncomment to enable AVI recording.
    blkPath = [modelName '/Simulation 3D Video Writer'];
    if getSimulinkBlockHandle(blkPath, true) == -1
        add_block('sim3dlib/Simulation 3D Video Writer', blkPath);
        set_param(blkPath, 'Filename', 'results/output.avi');
        set_param(blkPath, 'Commented', 'on');
        fprintf('  patchSolverAndVideo: added Simulation 3D Video Writer.\n');
    end

    save_system(modelName, modelPath);
    close_system(modelName, 0);
end

function patchActorColors(ibpDir)
% patchActorColors  Replace fixed part color with per-object color cycling.
%
% The original IBP example assigns a uniform gray (param.Color) to all bin
% parts. This patch inserts a colors array and assigns a distinct color to
% each part so objects are visually distinguishable in the Sim3D scene.

    modelName = 'Simulink_3D_IBP_Target';
    modelPath = fullfile(ibpDir, [modelName '.slx']);

    % Close if already loaded from a different path
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    load_system(modelPath);

    blockPath = [modelName '/Sim3D Scene Generation/Simulation 3D Actor7'];
    script = get_param(blockPath, 'InitScriptText');

    % Idempotent — skip if already patched
    if contains(script, 'colors(mod(i-1')
        fprintf('  patchActorColors: already applied.\n');
        close_system(modelName, 0);
        return
    end

    % Insert colors array before the parts for-loop
    colorsBlock = [ ...
        'colors = [' newline ...
        '    0.95, 0.20, 0.20;   % red' newline ...
        '    0.15, 0.80, 0.25;   % green' newline ...
        '    0.20, 0.40, 0.95;   % blue' newline ...
        '    0.10, 0.90, 0.90;   % cyan' newline ...
        '    0.90, 0.15, 0.90;   % magenta' newline ...
        '    0.15, 0.15, 0.15;   % black' newline ...
        '];' newline];

    script = strrep(script, ...
        'for i = 1:param.numInstEachObj', ...
        [colorsBlock 'for i = 1:param.numInstEachObj']);

    % Replace fixed color assignment with cycling color lookup
    script = strrep(script, ...
        'model.Color = param.Color;', ...
        ['%model.Color = param.Color;' newline ...
         '    model.Color = colors(mod(i-1, height(colors)) + 1,:);']);

    set_param(blockPath, 'InitScriptText', script);
    save_system(modelName, modelPath);
    close_system(modelName, 0);
    fprintf('  patchActorColors: applied.\n');
end

function patchModelCallbacks(ibpDir)
% patchModelCallbacks  Set PreLoadFcn on referenced models that need workspace vars.

    modelNames = {'CHOMP_Trajectory_Planner_Module', 'Simulink_3D_IBP_Target'};
    for k = 1:numel(modelNames)
        modelName = modelNames{k};
        modelPath = fullfile(ibpDir, [modelName '.slx']);

        if ~isfile(modelPath)
            fprintf('  patchModelCallbacks: %s not found, skipping.\n', modelName);
            continue
        end

        if bdIsLoaded(modelName)
            close_system(modelName, 0);
        end
        load_system(modelPath);

        set_param(modelName, 'PreLoadFcn', 'robotSimParams');
        set_param(modelName, 'InitFcn', '');

        save_system(modelName, modelPath);
        close_system(modelName, 0);
        fprintf('  patchModelCallbacks: %s\n', modelName);
    end
end

function patchRemoveToolboxDeps(ibpDir)
% patchRemoveToolboxDeps  Comment out pcread/im2uint8/ptCloud lines in initSim3DRobotModelParam.
%
% These lines require LIDAR and Image Processing Toolboxes which are not
% needed for this example.

    filePath = fullfile(ibpDir, 'initSim3DRobotModelParam.m');
    if ~isfile(filePath)
        fprintf('  patchRemoveToolboxDeps: initSim3DRobotModelParam.m not found.\n');
        return
    end

    src = fileread(filePath);

    % Idempotent — skip if already patched
    if contains(src, '%PATCHED:')
        fprintf('  patchRemoveToolboxDeps: already applied.\n');
        return
    end

    keywords = {'pcread', 'im2uint8', 'ptCloud'};
    lines = splitlines(src);
    modified = false;
    for k = 1:numel(lines)
        ln = lines{k};
        if startsWith(strtrim(ln), '%')
            continue
        end
        for j = 1:numel(keywords)
            if contains(ln, keywords{j})
                lines{k} = ['%PATCHED: ' ln];
                modified = true;
                break
            end
        end
    end

    if modified
        writelines(lines, filePath);
        fprintf('  patchRemoveToolboxDeps: commented out pcread/im2uint8/ptCloud lines.\n');
    else
        fprintf('  patchRemoveToolboxDeps: no matching lines found.\n');
    end
end
