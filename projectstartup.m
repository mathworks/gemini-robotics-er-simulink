% projectstartup  Configure paths and Python for the Gemini ER project.
%   Run once per MATLAB session. Requires installPythonEnv and
%   installIntelligentBinPicking to have been run at least once.

projectRoot = fileparts(mfilename('fullpath'));
addpath(projectRoot);
addpath(fullfile(projectRoot, 'images'));   % block mask icons (RobotReasoner.svg)

% Add IBP dependency path (must already exist)
ibpPath = fullfile(projectRoot, 'dependencies', 'IntelligentBinPickingExample');
if ~isfolder(ibpPath)
    error('gemini:missingDep', ...
        'IBP example not found at:\n  %s\nRun installIntelligentBinPicking first.', ibpPath);
end
addpath(ibpPath);

% Per-release Simulink build cache under tmp/, so build artifacts (CHOMP cgxe MEX,
% slxc, slprj) stay out of the repo root and one release never loads another's.
buildDir = fullfile(projectRoot, 'tmp', sprintf('r%sCache', version('-release')));
Simulink.fileGenControl('set', 'CacheFolder', buildDir, 'CodeGenFolder', buildDir, ...
    'createDir', true);
if ispc && ~isempty(getenv('NoDefaultCurrentDirectoryInExePath'))
    setenv('NoDefaultCurrentDirectoryInExePath', '');
end

% Configure Python environment
penv = initPythonEnvironment;
disp('Python environment:')
disp(penv)

% Initialize workspace variables (buses, camera params, etc.)
robotSimParams;
