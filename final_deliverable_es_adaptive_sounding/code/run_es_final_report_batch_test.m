function T = run_es_final_report_batch_test(opts)
% RUN_ES_FINAL_REPORT_BATCH_TEST Offline final-scale validation controller.
%
% Default final report scale:
%   3 intensity modes x 6 task modes x 10 scenario seeds x 10 optimizer seeds
%   = 1800 runs.
%
% Offline use:
%   addpath('code');
%   T = run_es_final_report_batch_test();
%
% Small smoke test:
%   T = run_es_final_report_batch_test(struct('smoke',true));

    if nargin < 1 || ~isstruct(opts)
        opts = struct();
    end

    if get_final_opt(opts, 'smoke', false)
        defaultIntensityModes = {'weak','strong'};
        defaultTaskModes = {'fast','weakEs'};
        defaultScenarioSeeds = 3101;
        defaultOptimizerSeeds = 20260515;
        defaultPopulationSize = 8;
        defaultGenerations = 1;
        defaultOutputCsv = fullfile('outputs', 'smoke_final_report_batch_validation_summary.csv');
        defaultOutputMat = fullfile('outputs', 'smoke_final_report_batch_validation_summary.mat');
    else
        defaultIntensityModes = {'weak','moderate','strong'};
        defaultTaskModes = {'fast','foEs','hEs','weakEs','full_trace','balanced'};
        defaultScenarioSeeds = 3101:3110;
        defaultOptimizerSeeds = 20260515:20260524;
        defaultPopulationSize = 40;
        defaultGenerations = 16;
        defaultOutputCsv = fullfile('outputs', 'final_report_batch_validation_summary.csv');
        defaultOutputMat = fullfile('outputs', 'final_report_batch_validation_summary.mat');
    end

    batchOpt = struct();
    batchOpt.stage = 'final_report';
    batchOpt.intensityModes = get_final_opt(opts, 'intensityModes', defaultIntensityModes);
    batchOpt.taskModes = get_final_opt(opts, 'taskModes', defaultTaskModes);
    batchOpt.scenarioSeeds = get_final_opt(opts, 'scenarioSeeds', defaultScenarioSeeds);
    batchOpt.optimizerSeeds = get_final_opt(opts, 'optimizerSeeds', defaultOptimizerSeeds);
    batchOpt.populationSize = get_final_opt(opts, 'populationSize', defaultPopulationSize);
    batchOpt.maxGenerations = get_final_opt(opts, 'maxGenerations', defaultGenerations);
    batchOpt.nSubRays = get_final_opt(opts, 'nSubRays', 5);
    batchOpt.truthFreqStepMHz = get_final_opt(opts, 'truthFreqStepMHz', 1.0);
    batchOpt.outputPath = get_final_opt(opts, 'outputCsv', defaultOutputCsv);

    totalRuns = numel(batchOpt.intensityModes) * numel(batchOpt.taskModes) * ...
        numel(batchOpt.scenarioSeeds) * numel(batchOpt.optimizerSeeds);
    fprintf('Final Es batch validation starts: %d runs.\n', totalRuns);
    fprintf('Intensity modes: %s\n', strjoin(string(batchOpt.intensityModes), ', '));
    fprintf('Task modes: %s\n', strjoin(string(batchOpt.taskModes), ', '));
    fprintf('Scenario seeds: %d..%d (%d)\n', min(batchOpt.scenarioSeeds), max(batchOpt.scenarioSeeds), numel(batchOpt.scenarioSeeds));
    fprintf('Optimizer seeds: %d..%d (%d)\n', min(batchOpt.optimizerSeeds), max(batchOpt.optimizerSeeds), numel(batchOpt.optimizerSeeds));
    fprintf('NSGA-II population=%d generations=%d\n', batchOpt.populationSize, batchOpt.maxGenerations);

    T = run_es_batch_validation(batchOpt);

    outputMat = char(string(get_final_opt(opts, 'outputMat', defaultOutputMat)));
    if isempty(fileparts(outputMat))
        outputMat = fullfile(pwd, outputMat);
    elseif ~is_absolute_final_path(outputMat)
        outputMat = fullfile(pwd, outputMat);
    end
    outputDir = fileparts(outputMat);
    if ~isempty(outputDir) && ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    summaryByMode = groupsummary(T, {'intensityMode','taskMode'}, {'mean','std','max'}, ...
        {'fixedErr','scanTimeSec','dfMHz','nFreq','heightResolutionKm','integrationGainDb','observabilityScore'});
    feasibleByMode = groupsummary(T, {'intensityMode','taskMode'}, 'mean', 'optimizationFeasible');
    save(outputMat, 'T', 'summaryByMode', 'feasibleByMode', 'batchOpt');

    fprintf('CSV written: %s\n', char(string(batchOpt.outputPath)));
    fprintf('MAT written: %s\n', outputMat);
    fprintf('Rows=%d, maxFixedErr=%.3g, feasibleRate=%.3f\n', height(T), max(T.fixedErr), mean(T.optimizationFeasible));
end

function v = get_final_opt(s, name, defaultValue)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = defaultValue;
    end
end

function tf = is_absolute_final_path(p)
    tf = startsWith(p, filesep) || ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once'));
end
