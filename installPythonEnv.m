% installPythonEnv  Install standalone Python 3.13 and Gemini Robotics ER dependencies.
%   Downloads a self-contained Python distribution (no system Python needed),
%   then installs packages required by geminiClient.py.
%
%   Supported architectures: glnxa64 (Linux), win64 (Windows), maca64 (macOS ARM64).
%
%   Run once after cloning:
%     installPythonEnv

arch = computer('arch');
installLocation = fullfile(fileparts(mfilename('fullpath')), 'dependencies', 'python', arch);

pyVersion = "3.13.1";
releaseTag = "20241206";
switch arch
    case 'glnxa64'
        pySource = "https://github.com/indygreg/python-build-standalone/releases/download/" + ...
                   releaseTag + "/cpython-" + pyVersion + "+" + releaseTag + ...
                   "-x86_64-unknown-linux-gnu-install_only.tar.gz";
    case 'win64'
        pySource = "https://github.com/indygreg/python-build-standalone/releases/download/" + ...
                   releaseTag + "/cpython-" + pyVersion + "+" + releaseTag + ...
                   "-x86_64-pc-windows-msvc-shared-install_only.tar.gz";
    case 'maca64'
        pySource = "https://github.com/indygreg/python-build-standalone/releases/download/" + ...
                   releaseTag + "/cpython-" + pyVersion + "+" + releaseTag + ...
                   "-aarch64-apple-darwin-install_only.tar.gz";
    otherwise
        error('Unsupported architecture: %s', arch);
end

tic
if ~exist(fullfile(installLocation, "python"), 'dir')
    mkdir(installLocation)
    disp("Downloading Python " + pyVersion)
    pydlLoc = websave(fullfile(installLocation, "pydl"), pySource);
    disp("Extracting: " + pydlLoc)
    untar(pydlLoc, installLocation);
    delete(pydlLoc)
else
    disp("Python already installed at: " + fullfile(installLocation, "python"))
end

% Resolve interpreter path
if ispc
    pyInterpreter = fullfile(installLocation, "python", "python.exe");
elseif ismac
    pyInterpreter = fullfile(installLocation, "python", "bin", "python3.13");
else
    pyInterpreter = fullfile(installLocation, "python", "bin", "python3.13");
end

% Persist interpreter path in MATLAB settings
s = settings;
if ~hasGroup(s, 'python')
    addGroup(s, 'python');
end
if hasSetting(s.python, "Python")
    s.python.Python.PersonalValue = pyInterpreter;
else
    addSetting(s.python, "Python", "PersonalValue", pyInterpreter);
end

% Quote pyInterpreter for system() - path may contain spaces (e.g., "00 Project - demo")
pyExe = '"' + pyInterpreter + '"';

disp("Upgrading pip")
[status, cmdout] = system(pyExe + " -m pip install --upgrade pip wheel");
if status ~= 0
    error("pip upgrade failed (exit code %d):\n%s", status, cmdout);
end

disp("----------")
disp("Installing Gemini Robotics ER Python dependencies")
[status, cmdout] = system(pyExe + " -m pip install " + ...
    """google-genai==1.73.1"" ""Pillow==12.1.1"" ""numpy==2.4.4""", "-echo");
if status ~= 0
    error("pip install failed (exit code %d):\n%s", status, cmdout);
end
toc

disp("Python installed. Run projectstartup to configure the environment.")
