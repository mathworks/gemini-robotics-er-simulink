classdef ReasonerBase < handle
% Passive-strategy base for one reasoner in a reasoning chain: builds the prompt from the shared context and parses the response back into it, never calling a model itself.

    properties (Constant, Access = protected)
        % JsonRule - Output constraint appended to every system prompt.
        JsonRule = "Reply ONLY with valid JSON. Do not include markdown code fences or explanatory text."
    end

    properties (SetAccess = immutable)
        % Instructions - Full system instructions for this reasoner (role, scene, and output schema), set once through the constructor from text (Instructions=) or a text file (InstructionsFile=, default <ClassName>Instructions.txt); JsonRule is appended when the system prompt is assembled.
        Instructions (1,1) string = ""
    end

    properties (Hidden)
        % SaveArtifacts - When true, postprocess writes this reasoner's JSON result + annotated image to WriteArtifactsDir for inspecting each step of the reasoning chain.
        SaveArtifacts (1,1) logical = false

        % WriteArtifactsDir - Target folder for saved artifacts; "" writes to results/ next to the class file (repo root).
        WriteArtifactsDir (1,1) string = ""
    end

    methods (Abstract)
        % Read context and return the image(s) to send plus the user and system prompts for this reasoner.
        [images, userPrompt, instructions] = preprocess(obj, context)

        % Parse the raw answer, write this reasoner's results into context.Data.*, and return the updated context.
        context = postprocess(obj, rawResponse, context)

        % Zero-valued prototype of the struct this reasoner's postprocess produces (plain MATLAB struct, no Simulink.Bus name).
        outStruct = outputStruct(obj)
    end

    methods
        function obj = ReasonerBase(instructions)
            % Set the immutable Instructions (only this constructor may assign them).
            arguments
                instructions (1,1) string = ""
            end
            obj.Instructions = instructions;
        end
    end

    methods (Static, Access = protected)
        function instructions = resolveInstructions(options, className)
            % Pick the constructor's Instructions source: Instructions= text, else InstructionsFile=, else the shipped <className>Instructions.txt.
            hasText = isfield(options, "Instructions");
            hasFile = isfield(options, "InstructionsFile");
            if hasText && hasFile
                error("ReasonerBase:AmbiguousInstructions", ...
                    "Specify Instructions or InstructionsFile, not both.");
            elseif hasText
                instructions = options.Instructions;
            elseif hasFile
                instructions = ReasonerBase.readInstructions(options.InstructionsFile);
            else
                instructions = ReasonerBase.readInstructions(fullfile( ...
                    fileparts(mfilename("fullpath")), className + "Instructions.txt"));
            end
        end

        function instructions = readInstructions(filePath)
            % Read an Instructions text file, normalizing CRLF (git autocrlf checkouts) to LF, unfolding hard-wrapped lines, and dropping trailing newlines.
            instructions = string(fileread(filePath, Encoding="UTF-8"));
            instructions = replace(instructions, sprintf("\r\n"), newline);
            instructions = ReasonerBase.unfoldLines(strip(instructions, "right", newline));
        end

        function stem = artifactStem(stem, context)
            % Suffix an artifact stem with _attempt<N> on a re-fire (context.Attempt > 1) so a retry does not overwrite the first attempt's artifacts.
            if isfield(context, "Attempt") && context.Attempt > 1
                stem = stem + "_attempt" + context.Attempt;
            end
        end

        function text = unfoldLines(text)
            % Join each wrapped continuation line onto the line before it with one space. Blank lines and lines whose first non-space character is -, {, or " keep their line break.
            lines = split(text, newline);
            unfolded = lines(1);
            for k = 2:numel(lines)
                content = strip(lines(k), "left");
                if content ~= "" && strip(unfolded(end)) ~= "" && ~startsWith(content, ["-", "{", """"])
                    unfolded(end) = unfolded(end) + " " + content;
                else
                    unfolded(end+1) = lines(k); %#ok<AGROW>
                end
            end
            text = join(unfolded, newline);
        end
    end

    methods (Access = protected)
        function instructions = composeInstructions(obj)
            % Assemble the full system message: Instructions + the JSON rule.
            promptParts = string.empty;
            if strlength(strtrim(obj.Instructions)) > 0
                promptParts(end + 1) = strtrim(obj.Instructions);
            end
            promptParts(end + 1) = obj.JsonRule;
            instructions = strjoin(promptParts, [newline newline]);
        end

        function writeArtifacts(obj, stem, jsonData, annotatedImage)
            % Write a reasoner's artifact pair: <stem>.json (pretty) + <stem>.png (annotated).
            resultsDir = obj.artifactsDir();
            jsonPath = fullfile(resultsDir, stem + ".json");
            fid = fopen(jsonPath, "w");
            if fid ~= -1
                cleanup = onCleanup(@() fclose(fid));
                fprintf(fid, "%s", jsonencode(jsonData, PrettyPrint=true));
            end
            imwrite(annotatedImage, fullfile(resultsDir, stem + ".png"));
        end

        function writeImageArtifact(obj, stem, image)
            % Write one unannotated image artifact, <stem>.png (e.g. a raw input frame for offline replay).
            imwrite(image, fullfile(obj.artifactsDir(), stem + ".png"));
        end

        function resultsDir = artifactsDir(obj)
            % Resolve (and create) the artifact folder: WriteArtifactsDir, else results/ next to this class file (repo root), not the caller's pwd.
            if strlength(obj.WriteArtifactsDir) > 0
                resultsDir = obj.WriteArtifactsDir;
            else
                resultsDir = fullfile(fileparts(mfilename("fullpath")), "results");
            end
            if ~isfolder(resultsDir)
                mkdir(resultsDir);
            end
        end
    end
end
