function summaryTable = run_es_batch_validation(opts)
% RUN_ES_BATCH_VALIDATION Batch validation for task-driven Es optimization.
%
% Example:
%   T = run_es_batch_validation(struct('stage','dev'));
%   T = run_es_batch_validation(struct('taskModes',{{'fast','foEs'}}, ...
%       'scenarioSeeds',1:3,'optimizerSeeds',101:103, ...
%       'intensityModes',{{'weak','moderate','strong'}}));

    if nargin < 1 || ~isstruct(opts)
        opts = struct();
    end

    stage = get_batch_opt(opts, 'stage', 'dev');
    switch lower(char(string(stage)))
        case 'dev'
            defaultScenarioSeeds = 3101;
            defaultOptimizerSeeds = 20260515;
            defaultPopulationSize = 16;
            defaultGenerations = 3;
        case 'functional'
            defaultScenarioSeeds = 3101:3106;
            defaultOptimizerSeeds = 20260515:20260519;
            defaultPopulationSize = 24;
            defaultGenerations = 8;
        otherwise
            defaultScenarioSeeds = 3101:3110;
            defaultOptimizerSeeds = 20260515:20260524;
            defaultPopulationSize = 40;
            defaultGenerations = 16;
    end

    taskModes = get_batch_opt(opts, 'taskModes', {'fast','foEs','hEs','weakEs','full_trace','balanced'});
    intensityModes = get_batch_opt(opts, 'intensityModes', {'moderate'});
    scenarioSeeds = get_batch_opt(opts, 'scenarioSeeds', defaultScenarioSeeds);
    optimizerSeeds = get_batch_opt(opts, 'optimizerSeeds', defaultOptimizerSeeds);
    populationSize = get_batch_opt(opts, 'populationSize', defaultPopulationSize);
    maxGenerations = get_batch_opt(opts, 'maxGenerations', defaultGenerations);
    nSubRays = get_batch_opt(opts, 'nSubRays', 5);
    truthFreqStepMHz = get_batch_opt(opts, 'truthFreqStepMHz', 1.0);
    outputPath = char(string(get_batch_opt(opts, 'outputPath', fullfile('outputs', 'batch_validation_summary.csv'))));
    if isempty(fileparts(outputPath))
        outputPath = fullfile(pwd, outputPath);
    elseif ~is_absolute_path(outputPath)
        outputPath = fullfile(pwd, outputPath);
    end

    rows = {};
    caseId = 0;
    for iIntensity = 1:numel(intensityModes)
        intensityMode = char(string(intensityModes{iIntensity}));
        intensityCfg = es_intensity_config(intensityMode);
        for iScene = 1:numel(scenarioSeeds)
            for iOpt = 1:numel(optimizerSeeds)
                for iMode = 1:numel(taskModes)
                caseId = caseId + 1;
                mode = char(string(taskModes{iMode}));
                runOpt = struct();
                runOpt.quiet = true;
                runOpt.userPref.taskMode = mode;
                runOpt.sceneSpec.Es.foEsExcessOverIriEMHz = intensityCfg.foEsExcessOverIriEMHz;
                runOpt.sceneSpec.Es.foEsSigmaMHz = intensityCfg.foEsSigmaMHz;
                runOpt.sceneSpec.Es.reflectivity = intensityCfg.reflectivity;
                runOpt.initialCfg.noiseStd = intensityCfg.noiseStd;
                runOpt.fwdOpt.scenarioSeed = scenarioSeeds(iScene);
                runOpt.fwdOpt.subraySeed = scenarioSeeds(iScene) + 17;
                runOpt.fwdOpt.noiseSeedBase = scenarioSeeds(iScene) + 9000;
                runOpt.fwdOpt.nSubRays = nSubRays;
                runOpt.fwdOpt.truthFreqListMHz = 1.5:truthFreqStepMHz:14.0;
                runOpt.fwdOpt.verbose = false;
                runOpt.optimizer.populationSize = populationSize;
                runOpt.optimizer.maxGenerations = maxGenerations;
                runOpt.optimizer.seed = optimizerSeeds(iOpt);

                out = es_only_adaptive_sounding_system(runOpt);
                targetRange = out.optimizerInfo.targetRegion.requiredRangeMHz;
                cfg = out.optimized.cfg;
                metric = out.optimizerInfo.bestMetrics;
                cons = out.optimizerInfo.bestConstraint;
                selectedRow = selected_candidate_row(out.optimizerInfo.candidateTable, cfg);
                fixedErr = max(abs(targetRange - [cfg.fStartMHz, cfg.fEndMHz]));
                initialFeature = out.initial.feature;
                foEObs = NaN;
                if isfield(initialFeature, 'E') && isfield(initialFeature.E, 'foEObservedRawMHz')
                    foEObs = initialFeature.E.foEObservedRawMHz;
                end

                rows(end+1,:) = {caseId, string(intensityMode), intensityCfg.foEsExcessOverIriEMHz, ...
                    intensityCfg.foEsSigmaMHz, intensityCfg.reflectivity, intensityCfg.noiseStd, ...
                    string(mode), optimizerSeeds(iOpt), scenarioSeeds(iScene), ...
                    initialFeature.Es.foEBackgroundMHz, foEObs, initialFeature.Es.foEsMHz, out.initial.cfg.dfMHz, ...
                    targetRange(1), targetRange(2), cfg.fStartMHz, cfg.fEndMHz, fixedErr, ...
                    cfg.dfMHz, cfg.PRP, cfg.chipLength, cfg.Ncoh, string(cfg.codeType), cfg.codeLength, ...
                    metric.nFreq, metric.scanTimeSec, metric.heightResolutionKm, metric.hAmbKm, metric.dutyRatio, ...
                    metric.integrationGainDb, metric.observabilityScore, metric.resolutionCost, metric.complexityCost, ...
                    cons.feasible, cons.optimizationFeasible, selectedRow.constraintViolation, ...
                    out.optimizerInfo.selectionInfo.nPareto, out.optimizerInfo.selectionInfo.nOptimizationFeasible, ...
                    out.optimizerInfo.selectionInfo.selectedLexicographicRank}; %#ok<AGROW>
                end
            end
        end
    end

    summaryTable = cell2table(rows, 'VariableNames', {'caseId','intensityMode','foEsExcessOverIriEMHz', ...
        'foEsSigmaMHz','reflectivity','noiseStd','taskMode','optimizerSeed','scenarioSeed', ...
        'foE_IRI','foE_obs','foEs_obs','df_coarse','targetStartMHz','targetEndMHz','cfgStartMHz','cfgEndMHz','fixedErr', ...
        'dfMHz','PRP','chipLength','Ncoh','codeType','codeLength','nFreq','scanTimeSec','heightResolutionKm', ...
        'hAmbKm','dutyRatio','integrationGainDb','observabilityScore','resolutionCost','complexityCost', ...
        'feasible','optimizationFeasible','constraintViolation','nPareto','nOptimizationFeasible','selectedLexicographicRank'});

    outputDir = fileparts(outputPath);
    if ~isempty(outputDir) && ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end
    writetable(summaryTable, outputPath);
end

function cfg = es_intensity_config(mode)
    switch lower(char(string(mode)))
        case {'weak','low','weak_es'}
            cfg = struct('foEsExcessOverIriEMHz', 0.35, 'foEsSigmaMHz', 0.55, ...
                'reflectivity', 0.65, 'noiseStd', 0.024);
        case {'strong','high','strong_es'}
            cfg = struct('foEsExcessOverIriEMHz', 1.50, 'foEsSigmaMHz', 1.10, ...
                'reflectivity', 1.30, 'noiseStd', 0.014);
        case {'moderate','medium','normal','default'}
            cfg = struct('foEsExcessOverIriEMHz', 0.80, 'foEsSigmaMHz', 0.90, ...
                'reflectivity', 1.00, 'noiseStd', 0.018);
        otherwise
            error('Unknown Es intensity mode: %s', mode);
    end
end

function v = get_batch_opt(s, name, defaultValue)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = defaultValue;
    end
end

function tf = is_absolute_path(p)
    tf = startsWith(p, filesep) || ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once'));
end

function row = selected_candidate_row(candidateTable, cfg)
    tol = 1e-10;
    code = string(cfg.codeType);
    idx = find(abs(candidateTable.fStartMHz - cfg.fStartMHz) <= tol & ...
        abs(candidateTable.fEndMHz - cfg.fEndMHz) <= tol & ...
        abs(candidateTable.dfMHz - cfg.dfMHz) <= tol & ...
        abs(candidateTable.PRP - cfg.PRP) <= tol & ...
        abs(candidateTable.chipLength - cfg.chipLength) <= tol & ...
        candidateTable.Ncoh == cfg.Ncoh & ...
        string(candidateTable.codeType) == code & ...
        candidateTable.codeLength == cfg.codeLength, 1, 'first');
    if isempty(idx)
        [~, idx] = min(candidateTable.cost);
    end
    row = candidateTable(idx,:);
end
