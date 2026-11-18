function penv = initPythonEnvironment
% initPythonEnvironment Point MATLAB at the project's bundled Python 3.13 (OutOfProcess) and put the repo root on py.sys.path.

% The function lives in the repo root, so its own location resolves projectRoot.
projectRoot = fileparts(mfilename('fullpath'));
installLocation = fullfile(projectRoot, 'dependencies', 'python', computer('arch'));
if ispc
    pyInterpreter = fullfile(installLocation, "python", "python.exe");
else
    pyInterpreter = fullfile(installLocation, "python", "bin", "python3.13");
end
if ~isfile(pyInterpreter)
    error('gemini:missingPython', ...
        'Python interpreter not found at:\n  %s\nRun installPythonEnv first.', pyInterpreter);
end

% Start a fresh Python environment after terminating any existing one
penv = pyenv;
if penv.Status == "Loaded"
    terminate(penv);
end
penv = pyenv(Version=pyInterpreter, ExecutionMode="OutOfProcess");

if count(py.sys.path, projectRoot) == 0
    insert(py.sys.path, int64(0), projectRoot);
end
end
