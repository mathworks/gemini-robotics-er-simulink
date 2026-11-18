classdef testBinPickingExample < matlab.unittest.TestCase
    % Smoke tests that installIntelligentBinPicking fetched/patched the dependency and the Simulink 3D Animation setup (block library, Unreal Engine simulation environment support) works.
    % Run: runtests("test/testBinPickingExample.m")

    properties (Constant)

        % Sim3D target model, simulated briefly to smoke-test the 3D Animation setup.
        Sim3DModelName = 'Simulink_3D_IBP_Target';  

        CHOMPModelName = 'CHOMP_Trajectory_Planner_Module';

        ExpectedFile = { ...
            testBinPickingExample.Sim3DModelName + ".slx", ...
            testBinPickingExample.CHOMPModelName + ".slx", ...
            'initRobotModelParam.m', ...
            'initSim3DRobotModelParam.m', ...
            'LoadBuses.m'};
    end

    properties
        IbpDir string
    end

    properties (TestParameter)
        % MathWorks products the example depends on, named as `ver` reports them (see README Requirements).
        RequiredProduct = { ...
            'Simulink', ...
            'Stateflow', ...
            'Robotics System Toolbox', ...
            'Simulink 3D Animation', ...          
            'Computer Vision Toolbox', ...
            'Optimization Toolbox'};
    end

    methods (TestClassSetup)
        function locateIbpDir(testCase)
            import matlab.unittest.fixtures.PathFixture
            projectRoot = fullfile(fileparts(mfilename("fullpath")), "..");
            testCase.IbpDir = fullfile(projectRoot, ...
                "dependencies", "IntelligentBinPickingExample");

            testCase.assertTrue(isfolder(testCase.IbpDir), ...
                sprintf(['IBP example folder not found at:\n  %s\n' ...
                'Run installIntelligentBinPicking first.'], testCase.IbpDir));

            testCase.applyFixture(PathFixture(projectRoot));
            testCase.applyFixture(PathFixture(testCase.IbpDir));
        end

        function useTempWorkingFolder(testCase)
            % Temporary working folder for Simulink
            import matlab.unittest.fixtures.WorkingFolderFixture
            testCase.applyFixture(WorkingFolderFixture);
        end

        function buildCache(~)
            % Per-release Simulink build cache under tmp/, so build artifacts (CHOMP cgxe MEX,
            % slxc, slprj) stay out of the repo root and one release never loads another's.
            projectRoot = fullfile(fileparts(mfilename("fullpath")), "..");
            buildDir = fullfile(projectRoot, 'tmp', sprintf('r%sCache', version('-release')));
            Simulink.fileGenControl('set', 'CacheFolder', buildDir, 'CodeGenFolder', buildDir, ...
                'createDir', true);
            if ispc && ~isempty(getenv('NoDefaultCurrentDirectoryInExePath'))
                setenv('NoDefaultCurrentDirectoryInExePath', '');
            end
        end
    end

    methods (Test)
        function verifyProductInstalled(testCase, RequiredProduct)
            % Each required MathWorks product must be installed for the example to run.
            installedToolboxes = ver;
            installedNames = string({installedToolboxes.Name});
            testCase.verifyTrue(any(installedNames == RequiredProduct), ...
                sprintf('Required product not installed: %s', RequiredProduct));
        end

        function verifyExpectedFilesPresent(testCase)
            % The fetch must land the key models and init scripts.
            for k = 1:numel(testCase.ExpectedFile)
                expected = fullfile(testCase.IbpDir, testCase.ExpectedFile{k});
                testCase.verifyTrue(isfile(expected), ...
                    sprintf('Expected IBP file missing: %s', testCase.ExpectedFile{k}));
            end
        end

        function verifyRobotSimParamsRuns(testCase)
            % robotSimParams loads all buses and planner params without error against the install.
            % Run in base, as PreLoadFcn does: LoadBuses resolves bus names there.
            testCase.verifyWarningFree(@() evalin('base', 'robotSimParams'), ...
                'robotSimParams errored against the IBP install.');
        end

        function verifySim3DModelSimsWithoutError(testCase)
            % Simulink 3D animation model must simulate without errors
            mdl = testCase.Sim3DModelName;
            testCase.addTeardown(@() testBinPickingExample.closeIfNeeded(mdl));

            load_system(mdl);   % fires PreLoadFcn=robotSimParams, staging params
            set_param(mdl, "StopTime", num2str(1));

            testCase.verifyWarningFree(@() sim(mdl), ...
                ['Simulink_3D_IBP_Target failed to simulate. Confirm Simulink 3D ' ...
                'Animation and the Unreal Engine simulation environment support ' ...
                'are installed.']);
        end

        function verifyCHOMPModelSimsWithoutError(testCase)
            % CHOMP Trajectory model must simulate without errors
            mdl = testCase.CHOMPModelName;
            testCase.addTeardown(@() testBinPickingExample.closeIfNeeded(mdl));

            load_system(mdl);   % fires PreLoadFcn=robotSimParams, staging params
            set_param(mdl, "StopTime", num2str(1));

            import matlab.unittest.fixtures.SuppressedWarningsFixture
            testCase.applyFixture( ...
                SuppressedWarningsFixture("Simulink:cgxe:LeakedJITEngine"))            

            testCase.verifyWarningFree(@() sim(mdl), ...
                ['CHOMP_Trajectory_Planner_Module failed to simulate. Confirm the ' ...
                'Robotics System Toolbox, Optimization toolboxes are installed']);
        end
    end

    methods (Static)
        function closeIfNeeded(modelName)
            if bdIsLoaded(modelName)
                close_system(modelName, 0);
            end
        end
    end
end
