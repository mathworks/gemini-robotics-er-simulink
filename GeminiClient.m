classdef GeminiClient < handle
% Pure-transport client for Gemini Robotics ER vision-language reasoning; owns MATLAB<->Python interop.

    properties (Constant, Access = private)
        % PyModule - Python module name (geminiClient.py sits next to this file)
        PyModule = "geminiClient"
        % EnterpriseEnv - environment variable that selects the Agent Platform backend
        EnterpriseEnv = "GOOGLE_GENAI_USE_ENTERPRISE"
        % DefaultLocation - Agent Platform location when GOOGLE_CLOUD_LOCATION is unset
        DefaultLocation = "global"
        % SyncedEnv - environment variables copied into the Python process before each client is created
        SyncedEnv = ["GOOGLE_GENAI_USE_ENTERPRISE", "GOOGLE_GENAI_USE_VERTEXAI", ...
            "GOOGLE_CLOUD_PROJECT", "GOOGLE_CLOUD_LOCATION", "GOOGLE_APPLICATION_CREDENTIALS", ...
            "CLOUDSDK_CONFIG", "GEMINI_API_KEY", "GOOGLE_API_KEY"]
        % AdcFileName - Application Default Credentials file written by "gcloud auth application-default login"
        AdcFileName = "application_default_credentials.json"
        % CloudPlatformScope - OAuth scope requested for Agent Platform credentials
        CloudPlatformScope = "https://www.googleapis.com/auth/cloud-platform"
    end

    properties (SetAccess = immutable)
        % Instructions - default system instructions (role + scene + schema)
        Instructions      (1,1) string
        % Temperature - sampling temperature; 0 = deterministic, [] = server default
        Temperature       double
        % ThinkingBudget - thinking tokens; 0 = no thinking (fastest), -1 = unlimited
        ThinkingBudget    (1,1) double
        % Model - model id requests are sent to (read-only)
        Model             (1,1) string
        % Backend - "enterprise" (Agent Platform, ADC) or "developer" (API key)
        Backend           (1,1) string
    end

    properties (Access = private)
        % PyClient - py.geminiClient.GeminiClient instance
        PyClient
    end

    methods
        function obj = GeminiClient(opts)
        % Construct the client and its underlying Python object.
            arguments
                opts.Instructions (1,1) string = ""
                opts.Temperature double = 0
                opts.ThinkingBudget (1,1) double = 0
            end

            pyMod = obj.importPyModule();

            % [] -> py.None so Python leaves the temperature unset (server default).
            if isempty(opts.Temperature)
                temperatureArg = py.None;
            else
                temperatureArg = opts.Temperature;
            end

            % The backend comes from MATLAB's environment variables; google-genai
            % reads the same variables from the synced Python environment.
            backend = GeminiClient.resolveBackend();
            GeminiClient.syncPythonEnvironment();
            if backend == "enterprise"
                credentials = GeminiClient.loadAdcCredentials();
                apiKey = py.None;
            else
                credentials = py.None;
                apiKey = char(GeminiClient.apiKey());
            end
            obj.PyClient = pyMod.GeminiClient( ...
                backend = char(backend), ...
                credentials = credentials, ...
                api_key = apiKey, ...
                temperature = temperatureArg, ...
                thinking_budget = int32(opts.ThinkingBudget));

            obj.Model          = string(obj.PyClient.model);
            obj.Backend        = string(obj.PyClient.backend);
            obj.Instructions   = opts.Instructions;
            obj.Temperature    = opts.Temperature;
            obj.ThinkingBudget = opts.ThinkingBudget;

            if obj.Backend == "enterprise"
                location = GeminiClient.envValue("GOOGLE_CLOUD_LOCATION");
                if strlength(location) == 0
                    location = GeminiClient.DefaultLocation;
                end
                fprintf("GeminiClient: using Gemini Enterprise Agent Platform (project %s, location %s), model %s\n", ...
                    GeminiClient.envValue("GOOGLE_CLOUD_PROJECT"), location, obj.Model);
            else
                fprintf("GeminiClient: using Gemini Developer API, model %s\n", obj.Model);
            end
        end

        function content = call(obj, userPrompt, images, options)
        % Send one request to Gemini and return the cleaned answer.
            arguments
                obj
                userPrompt (1,1) string
                images = {}
                options.Instructions (1,1) string = obj.Instructions
            end

            pyImages = obj.toPyImageList(images);
            content  = string(obj.PyClient(char(userPrompt), pyImages, ...
                pyargs("instructions", char(options.Instructions))));
        end
    end

    methods (Static)
        function tf = hasCredentials()
        % True when the environment selects a backend: the Agent Platform flag or an API key is set.
            tf = GeminiClient.useEnterprise() || strlength(GeminiClient.apiKey()) > 0;
        end
    end

    methods (Static, Access = private)
        function value = envValue(name)
        % Environment variable as a trimmed string ("" when unset).
            value = strtrim(string(getenv(name)));
        end

        function tf = useEnterprise()
        % True when GOOGLE_GENAI_USE_ENTERPRISE is "true" or "1" (case-insensitive).
            tf = any(strcmpi(GeminiClient.envValue(GeminiClient.EnterpriseEnv), ["true", "1"]));
        end

        function key = apiKey()
        % Developer API key: GOOGLE_API_KEY wins over GEMINI_API_KEY, as in google-genai.
            key = GeminiClient.envValue("GOOGLE_API_KEY");
            if strlength(key) == 0
                key = GeminiClient.envValue("GEMINI_API_KEY");
            end
        end

        function backend = resolveBackend()
        % Pick the backend from environment variables and error if its settings are missing.
            if GeminiClient.useEnterprise()
                backend = "enterprise";
                project = GeminiClient.envValue("GOOGLE_CLOUD_PROJECT");
                if strlength(project) == 0
                    error("GeminiClient:MissingProject", ...
                        "%s is set but GOOGLE_CLOUD_PROJECT is not. Set it to your Google Cloud project ID.", ...
                        GeminiClient.EnterpriseEnv);
                end
            else
                backend = "developer";
                if strlength(GeminiClient.apiKey()) == 0
                    error("GeminiClient:MissingApiKey", ...
                        "No Gemini credentials found. Set GEMINI_API_KEY (or GOOGLE_API_KEY) for the Gemini Developer API, or set %s=True and GOOGLE_CLOUD_PROJECT for the Gemini Enterprise Agent Platform (ADC).", ...
                        GeminiClient.EnterpriseEnv);
                end
            end
        end

        function syncPythonEnvironment()
        % Copy the Gemini environment variables from MATLAB into os.environ.
        % The out-of-process interpreter only has a copy taken at its launch,
        % so later setenv calls in MATLAB would otherwise be missed.
            environ = py.os.environ;
            for name = GeminiClient.SyncedEnv
                value = GeminiClient.envValue(name);
                if name == "GOOGLE_CLOUD_LOCATION" && strlength(value) == 0
                    value = GeminiClient.DefaultLocation;
                end
                if strlength(value) == 0
                    environ.pop(char(name), py.None);
                else
                    environ.update(py.dict(pyargs(char(name), char(value))));
                end
            end
        end

        function credentials = loadAdcCredentials()
        % Load Application Default Credentials as a Python google.auth credentials object.
        % For user ADC files (no project id inside), google.auth.default() runs
        % "gcloud config get project", which opens a console window from the
        % out-of-process Python host. The project comes from GOOGLE_CLOUD_PROJECT
        % instead, so the file is read directly when it exists, using gcloud's
        % path rule: GOOGLE_APPLICATION_CREDENTIALS, else the ADC file in
        % CLOUDSDK_CONFIG, %APPDATA%\gcloud (Windows) or ~/.config/gcloud.
            adcPath = GeminiClient.envValue("GOOGLE_APPLICATION_CREDENTIALS");
            if strlength(adcPath) == 0
                configDir = GeminiClient.envValue("CLOUDSDK_CONFIG");
                if strlength(configDir) == 0
                    if ispc
                        configDir = fullfile(getenv("APPDATA"), "gcloud");
                    else
                        configDir = fullfile(getenv("HOME"), ".config", "gcloud");
                    end
                end
                adcPath = fullfile(configDir, GeminiClient.AdcFileName);
            end

            googleAuth = py.importlib.import_module("google.auth");
            scopes = py.list({char(GeminiClient.CloudPlatformScope)});
            if isfile(adcPath)
                result = googleAuth.load_credentials_from_file(char(adcPath), scopes = scopes);
            else
                % No ADC file: service account / metadata server environments.
                result = googleAuth.default(scopes = scopes);
            end
            credentials = result{1};
        end

        function pyMod = importPyModule()
        % Ensure the repo dir is on the Python path and import the module.
            here = fileparts(mfilename("fullpath"));
            if count(py.sys.path, here) == 0
                insert(py.sys.path, int32(0), here);
            end
            pyMod = py.importlib.import_module(GeminiClient.PyModule);
            py.importlib.reload(pyMod);
        end

        function pyList = toPyImageList(images)
        % Convert a MATLAB image or cell of images into a Python list of numpy uint8 arrays.
            if isempty(images)
                pyList = py.list();
                return
            end
            if ~iscell(images)
                images = {images};
            end
            pyImages = cell(1, numel(images));
            for k = 1:numel(images)
                pyImages{k} = py.numpy.array(uint8(images{k}));
            end
            pyList = py.list(pyImages);
        end
    end
end
