% robotSimParams  Workspace parameters for IntelligentBinPicking_Gemini.
%
% Adds the IBP example to the MATLAB path, runs its standard init
% (loads all buses, robot model, bin params, enums), then overrides
% the two values that differ for the cam2 camera configuration.
%
% Run directly or set as the model PreLoadFcn.

if ~exist('TargetEnvs', 'class')
    error('IBP dependencies not on path. Run projectStartup first (see README).');
end

% initSim3DRobotModelParam must be called explicitly — initRobotModelParam
% skips it when targetEnv already exists in the workspace.
initSim3DRobotModelParam;

% Standard IBP init — loads all buses, robot model, bin params, enums
targetEnv = TargetEnvs.Sim3d;
initRobotModelParam;

% cam2 overrides (camera repositioned higher for better bin + workspace visibility)
camera_loc     = [0.50, 0, 1.50];   % cam1 default: [0.48, 0, 1.15]
maxBinDistance = 0.95;              % cam1 default: 0.60 m

% Alias for geminiTaskPlanner (matches initGeminiTaskPlanner expectation)
MaxDetections = maxObjectDetection;  % = 8, set by initRobotModelParam

% Define geminiTaskPlannerBus in base workspace
initPlannerGeminiER();

% Widen grasp region: IBP default ([0.014 0.014 0.023) for Gemini world-frame positions.
graspRegionTranslation = [0.028 0.028 0.035];

% Part layout seed read by initSim3DRobotModelParam above ([] = shipped layout).
% Kept if already set so a model reload does not reset a layout picked by the
% Reshuffle Layout button.
if ~exist('actorSeed', 'var')
    actorSeed = [];
end

% Verifier -> planner retry loop (Task Scheduler): plan + verify at most
% maxAttempts times; the robot settles at home for homeSettleTime (s) before
% every plan and verify.
maxAttempts    = 2;
homeSettleTime = 0.2;
% Hold (s) between the final verdict and the stop, so the camera still logs
% frames after the verification.
stopDelay      = 1;
