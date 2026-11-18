% projectshutdown  Runs automatically when the MATLAB project is closed.
%                  Also call manually to remove project paths from the session.

projectRoot = fileparts(mfilename('fullpath'));
rmpath(fullfile(projectRoot, 'dependencies', 'IntelligentBinPickingExample'));
rmpath(fullfile(projectRoot, 'images'));
rmpath(projectRoot);
Simulink.fileGenControl('reset');
terminate(pyenv)
