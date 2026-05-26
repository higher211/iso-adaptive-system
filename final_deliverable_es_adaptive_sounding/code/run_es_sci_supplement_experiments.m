function results = run_es_sci_supplement_experiments(opts)
% RUN_ES_SCI_SUPPLEMENT_EXPERIMENTS Supplemental SCI experiments.
%
% Runs:
%   1) fixed/heuristic baseline comparison
%   2) ablation study
%   3) paper-style statistical figures
%
% Example:
%   addpath('code');
%   R = run_es_sci_supplement_experiments(struct('stage','dev'));

    if nargin < 1 || ~isstruct(opts)
        opts = struct();
    end
    stage = lower(char(string(get_sci_opt(opts, 'stage', 'dev'))));
    switch stage
        case 'smoke'
            intensityModes = {'weak','strong'};
            taskModes = {'fast','weakEs'};
            scenarioSeeds = 3101;
            optimizerSeeds = 20260515;
            populationSize = 8;
            maxGenerations = 1;
        case 'dev'
            intensityModes = {'weak','strong'};
            taskModes = {'fast','foEs','hEs','weakEs','full_trace','balanced'};
            scenarioSeeds = 3101;
            optimizerSeeds = 20260515;
            populationSize = 16;
            maxGenerations = 3;
        case 'final'
            intensityModes = {'weak','moderate','strong'};
            taskModes = {'fast','foEs','hEs','weakEs','full_trace','balanced'};
            scenarioSeeds = 3101:3110;
            optimizerSeeds = 20260515:20260524;
            populationSize = 40;
            maxGenerations = 16;
        otherwise
            intensityModes = {'weak','moderate','strong'};
            taskModes = {'fast','foEs','hEs','weakEs','full_trace','balanced'};
            scenarioSeeds = 3101:3105;
            optimizerSeeds = 20260515:20260519;
            populationSize = 32;
            maxGenerations = 10;
    end

    outDir = char(string(get_sci_opt(opts, 'outputDir', fullfile('outputs', 'sci_supplement'))));
    figDir = char(string(get_sci_opt(opts, 'figureDir', fullfile('outputs', 'figures'))));
    ensure_dir(outDir);
    ensure_dir(figDir);

    common = struct();
    common.stage = stage;
    common.intensityModes = intensityModes;
    common.taskModes = taskModes;
    common.scenarioSeeds = scenarioSeeds;
    common.optimizerSeeds = optimizerSeeds;
    common.populationSize = populationSize;
    common.maxGenerations = maxGenerations;
    common.nSubRays = 5;
    common.truthFreqStepMHz = 1.0;

    fullPath = fullfile(outDir, 'full_system_for_supplement.csv');
    if exist(fullPath, 'file')
        fullSystem = readtable(fullPath);
    else
        runOpt = common;
        runOpt.outputPath = fullPath;
        fullSystem = run_es_batch_validation(runOpt);
    end

    baselinePath = fullfile(outDir, 'baseline_comparison_summary.csv');
    if exist(baselinePath, 'file')
        baselineTable = readtable(baselinePath);
    else
        baselineTable = run_baseline_comparison(fullSystem, baselinePath);
    end

    ablationPath = fullfile(outDir, 'ablation_study_summary.csv');
    if exist(ablationPath, 'file')
        ablationTable = readtable(ablationPath);
    else
        ablationTable = run_ablation_study(common, ablationPath, fullSystem);
    end
    figureFiles = generate_sci_figures(fullSystem, baselineTable, ablationTable, figDir);

    results = struct();
    results.fullSystem = fullSystem;
    results.baselineComparison = baselineTable;
    results.ablationStudy = ablationTable;
    results.figureFiles = figureFiles;
    save(fullfile(outDir, 'sci_supplement_results.mat'), '-struct', 'results');
end

function baselineTable = run_baseline_comparison(fullSystem, outputPath)
    rows = {};
    for i = 1:height(fullSystem)
        r = fullSystem(i,:);
        rows(end+1,:) = baseline_row(r, 'NSGA-II task-driven', r.dfMHz, r.PRP, r.chipLength, r.Ncoh, char(r.codeType)); %#ok<AGROW>
        rows(end+1,:) = baseline_row(r, 'Fixed medium', 0.10, 8e-3, 20e-6, 16, 'barker'); %#ok<AGROW>
        rows(end+1,:) = baseline_row(r, 'Traditional wide scan', 0.25, 8e-3, 20e-6, 16, 'barker', 1.5, 14.0); %#ok<AGROW>
        [df, ncoh, chip, code] = heuristic_params(char(r.taskMode));
        rows(end+1,:) = baseline_row(r, 'Manual task heuristic', df, 8e-3, chip, ncoh, code); %#ok<AGROW>
    end
    baselineTable = cell2table(rows, 'VariableNames', {'caseId','intensityMode','taskMode','method', ...
        'dfMHz','PRP','chipLength','Ncoh','codeType','codeLength','nFreq','scanTimeSec', ...
        'heightResolutionKm','integrationGainDb','observabilityScore','complexityCost','fixedErr'});
    writetable(baselineTable, outputPath);
end

function row = baseline_row(r, method, dfMHz, PRP, chipLength, Ncoh, codeType, fStart, fEnd)
    if nargin < 8
        fStart = r.targetStartMHz;
        fEnd = r.targetEndMHz;
    end
    codeLength = code_length_local(codeType);
    [nFreq, scanTimeSec, heightResolutionKm, integrationGainDb, observabilityScore, complexityCost] = ...
        strategy_metrics_local(fStart, fEnd, dfMHz, PRP, chipLength, Ncoh, codeType, codeLength);
    fixedErr = max(abs([r.targetStartMHz, r.targetEndMHz] - [fStart, fEnd]));
    row = {r.caseId, string(r.intensityMode), string(r.taskMode), string(method), dfMHz, PRP, chipLength, ...
        Ncoh, string(codeType), codeLength, nFreq, scanTimeSec, heightResolutionKm, integrationGainDb, ...
        observabilityScore, complexityCost, fixedErr};
end

function [df, ncoh, chip, code] = heuristic_params(taskMode)
    switch taskMode
        case 'fast'
            df = 0.25; ncoh = 8; chip = 24e-6; code = 'barker';
        case 'foEs'
            df = 0.05; ncoh = 12; chip = 16e-6; code = 'barker';
        case 'hEs'
            df = 0.12; ncoh = 12; chip = 8e-6; code = 'barker';
        case 'weakEs'
            df = 0.12; ncoh = 28; chip = 16e-6; code = 'complementary';
        case 'full_trace'
            df = 0.05; ncoh = 16; chip = 14e-6; code = 'barker';
        otherwise
            df = 0.12; ncoh = 16; chip = 16e-6; code = 'barker';
    end
end

function ablationTable = run_ablation_study(common, outputPath, fullSystem)
    if nargin < 3
        fullSystem = table();
    end
    variants = {
        'full_system', struct();
        'no_baseline', struct('ablation', struct('disableTaskBaseline', true));
        'no_rule_seed', struct('ablation', struct('disableRuleSeeds', true));
        'no_iri_prior', struct('ablation', struct('disableIriPrior', true));
        'unified_objective', struct('ablation', struct('unifiedObjective', true))
    };
    rows = {};
    for i = 1:size(variants,1)
        name = variants{i,1};
        userPatch = variants{i,2};
        if strcmp(name, 'full_system') && ~isempty(fullSystem)
            T = fullSystem;
        else
            runOpt = common;
            runOpt.outputPath = tempname;
            runOpt.userPrefPatch = userPatch;
            T = run_es_batch_validation(runOpt);
        end
        for k = 1:height(T)
            rows(end+1,:) = {string(name), string(T.intensityMode(k)), string(T.taskMode(k)), T.scenarioSeed(k), ...
                T.optimizerSeed(k), T.fixedErr(k), T.dfMHz(k), T.scanTimeSec(k), T.nFreq(k), ...
                T.heightResolutionKm(k), T.integrationGainDb(k), T.observabilityScore(k), ...
                T.optimizationFeasible(k), T.constraintViolation(k)}; %#ok<AGROW>
        end
        ablationTable = cell2table(rows, 'VariableNames', {'variant','intensityMode','taskMode','scenarioSeed', ...
            'optimizerSeed','fixedErr','dfMHz','scanTimeSec','nFreq','heightResolutionKm', ...
            'integrationGainDb','observabilityScore','optimizationFeasible','constraintViolation'});
        writetable(ablationTable, outputPath);
    end
end

function files = generate_sci_figures(T, baselineTable, ablationTable, figDir)
    files = strings(0,1);
    files(end+1) = grouped_bar(T, 'taskMode', 'scanTimeSec', 'Mean scan time (s)', fullfile(figDir, 'mode_scan_time.png'));
    files(end+1) = grouped_bar(T, 'taskMode', 'dfMHz', 'Mean df (MHz)', fullfile(figDir, 'mode_df.png'));
    files(end+1) = grouped_bar(T, 'taskMode', 'heightResolutionKm', 'Mean height resolution (km)', fullfile(figDir, 'mode_height_resolution.png'));
    files(end+1) = grouped_bar(T, 'taskMode', 'integrationGainDb', 'Mean integration gain (dB)', fullfile(figDir, 'mode_gain.png'));
    files(end+1) = feasible_heatmap(T, fullfile(figDir, 'feasible_rate_heatmap.png'));
    files(end+1) = method_bar(baselineTable, 'scanTimeSec', 'Baseline mean scan time (s)', fullfile(figDir, 'baseline_scan_time.png'));
    files(end+1) = variant_bar(ablationTable, fullfile(figDir, 'ablation_feasible_rate.png'));
end

function path = grouped_bar(T, groupName, valueName, yLabel, outputPath)
    G = groupsummary(T, groupName, 'mean', valueName);
    f = figure('Visible','off');
    bar(categorical(string(G.(groupName))), G.("mean_" + valueName));
    ylabel(yLabel);
    grid on;
    saveas(f, outputPath);
    close(f);
    path = string(outputPath);
end

function path = feasible_heatmap(T, outputPath)
    G = groupsummary(T, {'intensityMode','taskMode'}, 'mean', 'optimizationFeasible');
    intensities = unique(string(G.intensityMode), 'stable');
    tasks = unique(string(G.taskMode), 'stable');
    M = nan(numel(intensities), numel(tasks));
    for i = 1:height(G)
        r = find(intensities == string(G.intensityMode(i)), 1);
        c = find(tasks == string(G.taskMode(i)), 1);
        M(r,c) = G.mean_optimizationFeasible(i);
    end
    f = figure('Visible','off');
    imagesc(M, [0 1]);
    colorbar;
    xticks(1:numel(tasks)); xticklabels(tasks);
    yticks(1:numel(intensities)); yticklabels(intensities);
    title('Optimization feasible rate');
    saveas(f, outputPath);
    close(f);
    path = string(outputPath);
end

function path = method_bar(T, valueName, yLabel, outputPath)
    G = groupsummary(T, 'method', 'mean', valueName);
    f = figure('Visible','off');
    bar(categorical(string(G.method)), G.("mean_" + valueName));
    ylabel(yLabel);
    grid on;
    saveas(f, outputPath);
    close(f);
    path = string(outputPath);
end

function path = variant_bar(T, outputPath)
    G = groupsummary(T, 'variant', 'mean', 'optimizationFeasible');
    f = figure('Visible','off');
    bar(categorical(string(G.variant)), G.mean_optimizationFeasible);
    ylabel('Feasible rate');
    ylim([0 1]);
    grid on;
    saveas(f, outputPath);
    close(f);
    path = string(outputPath);
end

function [nFreq, scanTimeSec, heightResolutionKm, gainDb, obs, complexity] = strategy_metrics_local(fStart, fEnd, df, PRP, chip, Ncoh, codeType, codeLength)
    nFreq = max(1, floor((fEnd - fStart)/df) + 1);
    pulses = Ncoh;
    if strcmpi(codeType, 'complementary')
        pulses = 2*Ncoh;
    end
    scanTimeSec = nFreq*pulses*PRP;
    heightResolutionKm = 299792458*chip/2/1e3;
    gainDb = 10*log10(max(Ncoh,1)) + 10*log10(max(codeLength,1));
    if strcmpi(codeType, 'complementary')
        gainDb = gainDb + 1.5;
    end
    obs = min(max((gainDb - 12) / 14, 0), 1);
    complexity = 0.15*double(strcmpi(codeType, 'complementary')) + 0.03*(Ncoh/48);
end

function L = code_length_local(codeType)
    if strcmpi(codeType, 'complementary')
        L = 16;
    else
        L = 13;
    end
end

function ensure_dir(p)
    if ~exist(p, 'dir')
        mkdir(p);
    end
end

function v = get_sci_opt(s, name, defaultValue)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = defaultValue;
    end
end
