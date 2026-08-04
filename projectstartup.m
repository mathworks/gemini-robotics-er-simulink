% projectstartup  Configure paths and Python for the Gemini ER project.
%   Run once per MATLAB session. Requires installPythonEnv and
%   installIntelligentBinPicking to have been run at least once.

projectRoot = fileparts(mfilename('fullpath'));
addpath(projectRoot);

% Add IBP dependency path (must already exist)
ibpPath = fullfile(projectRoot, 'dependencies', 'IntelligentBinPickingExample');
if ~isfolder(ibpPath)
    error('gemini:missingDep', ...
        'IBP example not found at:\n  %s\nRun installIntelligentBinPicking first.', ibpPath);
end
addpath(ibpPath);

% Configure Python environment
arch = computer('arch');
installLocation = fullfile(projectRoot, 'dependencies', 'python', arch);
if ispc
    pyInterpreter = fullfile(installLocation, "python", "python.exe");
else
    pyInterpreter = fullfile(installLocation, "python", "bin", "python3.13");
end
if ~isfile(pyInterpreter)
    error('gemini:missingPython', ...
        'Python interpreter not found at:\n  %s\nRun installPythonEnv first.', pyInterpreter);
end
terminate(pyenv);
penv = pyenv(Version=pyInterpreter, ExecutionMode="OutOfProcess");
if count(py.sys.path, projectRoot) == 0
    insert(py.sys.path, int64(0), projectRoot);
end
disp('Python environment:')
disp(penv)

% Initialize workspace variables (buses, camera params, etc.)
robotSimParams;
