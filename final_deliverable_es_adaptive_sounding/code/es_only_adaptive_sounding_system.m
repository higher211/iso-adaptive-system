function out = es_only_adaptive_sounding_system(modeOrOptions, options)
% ES_ONLY_ADAPTIVE_SOUNDING_SYSTEM
% -------------------------------------------------------------------------
% Es-only 自适应垂直探测完整系统。
%
% 系统流程：
%   真实 Es 场景输入
%       -> 正常背景电离层 + 偶发 E 层建模
%       -> 垂直探测等效信道
%       -> Barker-13 / 互补码-16 编码脉冲链路
%       -> 初策略电离图
%       -> 非破坏性预处理
%       -> 已知 Es 类型特征提取
%       -> 按用户任务偏好进行理论策略寻优
%       -> 优化策略电离图
%       -> 初策略、优化策略与真实 Es 可观测特征比较
%
% 限定：
%   1) 只保留 Es 偶发 E 层；
%   2) 其他异常类型全部删除：blanketing Es、depletion/bubble-like、irregularity、TID、吸收等；
%   3) E/F1/F2 背景层保持正常；
%   4) Barker 码固定 13 位，互补码固定 16 位；
%   5) Ncoh 为整数；
%   6) fStart、fEnd、df、PRP、chipLength 为理论连续取值。
%
% 运行：
%   out = es_only_adaptive_sounding_system;
%   runOpt.userPref.taskMode = 'fast';       % 快速Es告警
%   runOpt.userPref.taskMode = 'foEs';       % foEs边界精读窄扫
%   runOpt.userPref.taskMode = 'hEs';        % h'Es稳定读取
%   runOpt.userPref.taskMode = 'weakEs';     % 弱Es可观测增强
%   runOpt.userPref.taskMode = 'full_trace'; % 完整Es形态
%   runOpt.userPref.taskMode = 'balanced';   % 综合Pareto折中，默认
%   out = es_only_adaptive_sounding_system(runOpt);
% -------------------------------------------------------------------------

    if nargin >= 1 && (ischar(modeOrOptions) || isstring(modeOrOptions))
        runOpt = struct();
        runOpt.userPref.taskMode = char(modeOrOptions);
    elseif nargin >= 1
        runOpt = modeOrOptions;
    else
        runOpt = struct();
    end

    quietMode = get_opt(runOpt, 'quiet', false);
    if ~quietMode
        clc;
    end
    rng(2026);

    % 1. Es-only 真实场景输入。
    sceneSpec = make_es_only_sceneSpec();
    sceneSpec = apply_struct_override(sceneSpec, get_opt(runOpt, 'sceneSpec', struct()));

    % 2. 初始均衡探测策略。
    initialCfg = make_initial_strategy();
    initialCfg = apply_struct_override(initialCfg, get_opt(runOpt, 'initialCfg', struct()));
    initialCfg = refresh_strategy(initialCfg);

    % 3. 理论寻优偏好与约束。
    userPref = make_es_optimizer_preference();
    userPref = apply_struct_override(userPref, get_opt(runOpt, 'userPref', struct()));
    userPref = apply_optimizer_override(userPref, get_opt(runOpt, 'optimizer', struct()));

    % 4. 前向链路选项。
    fwdOpt = make_forward_options();
    fwdOpt = apply_struct_override(fwdOpt, get_opt(runOpt, 'fwdOpt', struct()));
    if quietMode
        fwdOpt.verbose = false;
    end

    % 5. 构造真实场景、空间相关 Es 斑块、固定子路径集合。
    scene = build_scene_from_sceneSpec(sceneSpec);
    scene.seedBase = fwdOpt.scenarioSeed;
    scene = initialize_scene_maps(scene);
    subraySet = build_common_subray_set(fwdOpt.apertureKm, fwdOpt.nSubRays, fwdOpt.subraySeed);

    % 6. 真值层。仅用于最终验证，不进入策略寻优。
    sceneTruth = compute_es_scene_truth(sceneSpec, scene, subraySet, fwdOpt);
    echoTruth = generate_truth_echo_table(scene, subraySet, fwdOpt.truthFreqListMHz, fwdOpt.frozenSceneTimeSec);
    truthFeature = build_es_truth_feature(sceneTruth, echoTruth);

    % 7. 初策略探测。
    initialCfg = attach_subray_set(refresh_strategy(initialCfg), subraySet);
    initialCfg.sceneTimeMode = fwdOpt.sceneTimeMode;
    initialCfg.frozenSceneTimeSec = fwdOpt.frozenSceneTimeSec;
    initialSim = run_forward_one_strategy(initialCfg, scene, fwdOpt, 'initial');

    % 8. 初策略电离图预处理与 Es 特征提取。
    pp = default_preprocess_param_native();
    initialPre = preprocess_ionogram_native(initialSim.fMHz, initialSim.hKm, initialSim.ionogram, pp);
    initialFeature = extract_es_features(initialPre);
    initialFeature = attach_iri_background_context(initialFeature, scene);

    % 9. Es-only 理论策略寻优。只使用 initialFeature，不使用 truthFeature。
    [optimizedCfg, optimizerInfo] = optimize_strategy_es_only(initialCfg, sceneSpec, initialFeature, userPref);

    % 10. 优化策略再探测。
    optimizedCfg = attach_subray_set(refresh_strategy(optimizedCfg), subraySet);
    optimizedCfg.sceneTimeMode = fwdOpt.sceneTimeMode;
    optimizedCfg.frozenSceneTimeSec = fwdOpt.frozenSceneTimeSec;
    optimizedSim = run_forward_one_strategy(optimizedCfg, scene, fwdOpt, 'optimized');

    % 11. 优化策略电离图预处理与 Es 特征提取。
    ppOpt = default_preprocess_param_native();
    optimizedPre = preprocess_ionogram_native(optimizedSim.fMHz, optimizedSim.hKm, optimizedSim.ionogram, ppOpt);
    optimizedFeature = stabilize_es_height_with_prior(extract_es_features(optimizedPre), initialFeature);
    optimizedFeature = attach_iri_background_context(optimizedFeature, scene);

    % 12. 初策略、优化策略与真实 Es 特征比较。
    initialScore = compare_es_feature_with_truth(initialFeature, truthFeature, initialCfg, initialSim);
    optimizedScore = compare_es_feature_with_truth(optimizedFeature, truthFeature, optimizedCfg, optimizedSim);
    improvement = compare_initial_optimized_es(truthFeature, initialFeature, optimizedFeature, initialScore, optimizedScore);

    % 13. 汇总输出。
    out = struct();
    out.sceneSpec = sceneSpec;
    out.scene = scene;
    out.subraySet = subraySet;
    out.sceneTruth = sceneTruth;
    out.echoTruth = echoTruth;
    out.truthFeature = truthFeature;
    out.initial.cfg = initialCfg;
    out.initial.sim = initialSim;
    out.initial.pre = initialPre;
    out.initial.feature = initialFeature;
    out.initial.score = initialScore;
    out.optimized.cfg = optimizedCfg;
    out.optimized.sim = optimizedSim;
    out.optimized.pre = optimizedPre;
    out.optimized.feature = optimizedFeature;
    out.optimized.score = optimizedScore;
    out.optimizerInfo = optimizerInfo;
    out.improvement = improvement;
    out.summaryTable = improvement.summaryTable;
    out.modelFlow = build_iri_es_model_flow(scene);
    out.rawComparison = build_raw_comparison(initialSim, optimizedSim);
    out.featureComparison.initialFeature = initialFeature;
    out.featureComparison.optimizedFeature = optimizedFeature;
    out.featureComparison.truthFeature = truthFeature;
    out.resolutionAwareComparison.initialScore = initialScore;
    out.resolutionAwareComparison.optimizedScore = optimizedScore;
    out.resolutionAwareComparison.summaryTable = improvement.summaryTable;

    assignin('base', 'esOnlyAdaptiveOut', out);

    if ~quietMode
        fprintf('\nES-ONLY ADAPTIVE SOUNDING SYSTEM FINISHED.\n');
        fprintf('Workspace variable: esOnlyAdaptiveOut\n\n');
        disp(out.summaryTable);
    end

end

function [P, T] = build_pareto_table(candidateTable)
    T = candidateTable;
    n = height(T);
    if ismember('optimizationFeasible', T.Properties.VariableNames)
        T.paretoEligible = T.optimizationFeasible;
    elseif ismember('feasible', T.Properties.VariableNames)
        T.paretoEligible = T.feasible;
    else
        T.paretoEligible = true(n,1);
    end

    isPareto = false(n,1);
    eligibleIdx = find(T.paretoEligible);
    if isempty(eligibleIdx)
        T.isPareto = isPareto;
        P = T(isPareto,:);
        return;
    end
    vals = [T.scanTimeSec(eligibleIdx), T.resolutionCost(eligibleIdx), -T.observabilityScore(eligibleIdx), T.complexityCost(eligibleIdx)];
    localPareto = true(numel(eligibleIdx), 1);
    for i = 1:numel(eligibleIdx)
        for j = 1:numel(eligibleIdx)
            if i == j, continue; end
            if all(vals(j,:) <= vals(i,:)) && any(vals(j,:) < vals(i,:))
                localPareto(i) = false;
                break;
            end
        end
    end
    isPareto(eligibleIdx) = localPareto;
    T.isPareto = isPareto;
    P = T(isPareto,:);
end

function [cfg, cost, metric, breakdown, cons, selectionInfo] = select_strategy_from_pareto_candidates(candidateTable, baseCfg, target, pref)
    [paretoTable, allTable] = build_pareto_table(candidateTable);
    reliabilityTable = table();
    nonDegenerateTable = table();
    selectedLexicographicRank = NaN;
    if isempty(paretoTable)
        [~, idx] = min(candidateTable.cost);
        row = candidateTable(idx,:);
        selectionMode = 'minimum-cost fallback';
    else
        eligible = paretoTable;
        if isfield(target, 'hasIriPrior') && target.hasIriPrior
            reliabilityTable = filter_es_reliable_pareto_candidates(eligible, pref);
            if isempty(reliabilityTable)
                reliabilityTable = eligible;
                selectionMode = 'IRI-informed Pareto theoretical fallback; no candidate passed Es observability filter';
            else
                selectionMode = 'IRI-informed Es-observable Pareto point';
            end

            nonDegenerateTable = filter_non_degenerate_theoretical_candidates(reliabilityTable, baseCfg, pref);
            if ~isempty(nonDegenerateTable)
                eligible = nonDegenerateTable;
                selectionMode = 'IRI-informed non-degenerate Pareto low-time-band resolution-prioritized point';
            else
                eligible = reliabilityTable;
                selectionMode = [selectionMode, '; non-degenerate fallback'];
            end

            [row, selectedLexicographicRank] = select_task_pareto_row(eligible, pref);
        else
            score = pareto_knee_score(eligible);
            [~, idx] = min(score);
            row = eligible(idx,:);
            selectionMode = 'feasible Pareto knee point';
        end
    end

    cfg = row_to_strategy_cfg(row, baseCfg);
    [cost, metric, cons, breakdown] = es_strategy_cost(cfg, target, pref);
    selectionInfo = struct();
    selectionInfo.mode = selectionMode;
    selectionInfo.nCandidates = height(candidateTable);
    selectionInfo.nPareto = height(paretoTable);
    selectionInfo.nOptimizationFeasible = count_table_true(allTable, 'optimizationFeasible');
    selectionInfo.nParetoEligible = count_table_true(allTable, 'paretoEligible');
    selectionInfo.nEsReliablePareto = height(reliabilityTable);
    selectionInfo.nNonDegeneratePareto = height(nonDegenerateTable);
    selectionInfo.selectedLexicographicRank = selectedLexicographicRank;
end

function [row, rankIdx] = select_task_pareto_row(T, pref)
    switch get_opt(pref, 'selectionMode', 'balanced')
        case 'fast'
            [row, rankIdx] = select_sorted_pareto_row(T, {'scanTimeSec','negObservabilityScore','complexityCost','dfMHz','originalOrder'});
        case 'foes'
            [row, rankIdx] = select_sorted_pareto_row(T, {'dfMHz','scanTimeSec','negIntegrationGainDb','heightResolutionKm','originalOrder'});
        case 'height'
            [row, rankIdx] = select_sorted_pareto_row(T, {'heightResolutionKm','negIntegrationGainDb','scanTimeSec','dfMHz','originalOrder'});
        case 'weak'
            [row, rankIdx] = select_sorted_pareto_row(T, {'negObservabilityScore','negIntegrationGainDb','scanTimeSec','complexityCost','originalOrder'});
        case 'full_trace'
            [row, rankIdx] = select_sorted_pareto_row(T, {'nFreqDescending','dfMHz','resolutionCost','negObservabilityScore','scanTimeSec','originalOrder'});
        otherwise
            [row, rankIdx] = select_lexicographic_pareto_row(T);
    end
end

function [row, rankIdx] = select_sorted_pareto_row(T, sortNames)
    if isempty(T)
        row = T;
        rankIdx = NaN;
        return;
    end
    S = add_task_sort_columns(T);
    S.originalOrder = (1:height(S))';
    S = sortrows(S, sortNames);
    row = S(1, T.Properties.VariableNames);
    rankIdx = S.originalOrder(1);
end

function S = add_task_sort_columns(S)
    S.negObservabilityScore = -S.observabilityScore;
    S.negIntegrationGainDb = -S.integrationGainDb;
    S.nFreqDescending = -S.nFreq;
end

function T2 = filter_es_reliable_pareto_candidates(T, pref)
    if isempty(T)
        T2 = T;
        return;
    end
    minFreq = max(pref.minFrequencySamples, 12);
    if strcmpi(pref.taskMode, 'fast_detection')
        minFreq = pref.minFrequencySamples;
    end
    ok = T.optimizationFeasible & ...
        T.integrationGainDb >= pref.minIntegrationGainDb & ...
        T.nFreq >= minFreq;
    T2 = T(ok,:);
end

function T2 = filter_non_degenerate_theoretical_candidates(T, baseCfg, pref)
    if isempty(T)
        T2 = T([]);
        return;
    end
    %#ok<INUSD>  % baseCfg is retained for the existing call interface.
    ok = T.optimizationFeasible & T.nFreq >= min_required_task_frequency_samples(pref);
    T2 = T(ok,:);
end

function n = min_required_task_frequency_samples(pref)
    if strcmpi(pref.taskMode, 'fast_detection')
        n = pref.minFrequencySamples;
    else
        n = max(pref.minFrequencySamples, 12);
    end
end

function scanTime = estimate_strategy_scan_time(cfg)
    nFreq = max(1, floor((cfg.fEndMHz - cfg.fStartMHz)/max(cfg.dfMHz, eps)) + 1);
    if is_complementary_mode(cfg)
        pulsesPerFreq = 2*cfg.Ncoh;
    else
        pulsesPerFreq = cfg.Ncoh;
    end
    scanTime = nFreq*pulsesPerFreq*cfg.PRP;
end

function [row, rankIdx] = select_lexicographic_pareto_row(T)
    if isempty(T)
        row = T;
        rankIdx = NaN;
        return;
    end
    S = T;
    minScan = min(S.scanTimeSec);
    % Work inside a low-time band, then prefer the point that better serves
    % Es scaling quality. This keeps the strategy fast without selecting the
    % fastest candidate at the expense of h'Es/foEs resolution.
    lowCostLimit = max(1.60*minScan, minScan + 0.25);
    lowCost = S(S.scanTimeSec <= lowCostLimit, :);
    if ~isempty(lowCost)
        S = lowCost;
    end
    S.negObservabilityScore = -S.observabilityScore;
    S.absCost = abs(S.cost);
    S.originalOrder = (1:height(S))';
    S = sortrows(S, {'scanTimeSec', 'resolutionCost', ...
        'negObservabilityScore', 'absCost', 'originalOrder'});
    row = S(1, T.Properties.VariableNames);
    rankIdx = S.originalOrder(1);
end

function score = pareto_knee_score(T)
    objectives = [T.scanTimeSec, T.resolutionCost, -T.observabilityScore, T.complexityCost];
    mins = min(objectives, [], 1);
    maxs = max(objectives, [], 1);
    span = max(maxs - mins, eps);
    Z = (objectives - mins) ./ span;

    idealDistance = sqrt(sum(Z.^2, 2));
    balancePenalty = std(Z, 0, 2);
    scanPenalty = normalize_vector(T.scanTimeSec);
    score = idealDistance + 0.25*balancePenalty + 0.18*scanPenalty + 0.08*normalize_vector(T.cost);
end

function cfg = row_to_strategy_cfg(row, baseCfg)
    cfg = baseCfg;
    cfg.codeType = char(row.codeType{1});
    cfg.codeLength = row.codeLength;
    cfg.Ncoh = row.Ncoh;
    cfg.fStartMHz = row.fStartMHz;
    cfg.fEndMHz = row.fEndMHz;
    cfg.dfMHz = row.dfMHz;
    cfg.PRP = row.PRP;
    cfg.chipLength = row.chipLength;
    cfg = refresh_strategy(cfg);
end

function n = count_table_true(T, name)
    if isempty(T) || ~ismember(name, T.Properties.VariableNames)
        n = 0;
    else
        n = sum(logical(T.(name)));
    end
end

function y = normalize_vector(x)
    if isempty(x)
        y = x;
        return;
    end
    lo = min(x);
    hi = max(x);
    y = (x - lo) ./ max(hi - lo, eps);
end

function v = get_opt(s, name, defaultValue)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = defaultValue;
    end
end

function s = apply_struct_override(s, override)
    if ~isstruct(override), return; end
    names = fieldnames(override);
    for i = 1:numel(names)
        name = names{i};
        if isstruct(override.(name)) && isfield(s, name) && isstruct(s.(name))
            s.(name) = apply_struct_override(s.(name), override.(name));
        else
            s.(name) = override.(name);
        end
    end
end

function pref = apply_optimizer_override(pref, override)
    if ~isstruct(override) || isempty(fieldnames(override))
        return;
    end
    if isfield(override, 'populationSize')
        pref.nsga2.populationSize = override.populationSize;
    end
    if isfield(override, 'maxGenerations')
        pref.nsga2.nGenerations = override.maxGenerations;
    end
    if isfield(override, 'nGenerations')
        pref.nsga2.nGenerations = override.nGenerations;
    end
    if isfield(override, 'seed')
        pref.nsga2.seed = override.seed;
    end
    if isfield(override, 'crossoverProbability')
        pref.nsga2.crossoverProbability = override.crossoverProbability;
    end
    if isfield(override, 'mutationProbability')
        pref.nsga2.mutationProbability = override.mutationProbability;
    end
    if isfield(override, 'nsga2')
        pref.nsga2 = apply_struct_override(pref.nsga2, override.nsga2);
    end
end

%% ========================================================================
%%                         SceneSpec and strategy inputs
%% ========================================================================

function sceneSpec = make_es_only_sceneSpec()
    sceneSpec = struct();
    sceneSpec.name = 'es_only_normal_background';
    sceneSpec.allowedAnomalyTypes = {'Es'};

    % 正常背景层。背景层不是异常，只作为 E/F1/F2 正常反射基础。
    sceneSpec.background.mode = 'chapman';
    sceneSpec.background.foE = 2.6;
    sceneSpec.background.hmE = 110;
    sceneSpec.background.HE = 9;
    sceneSpec.background.foF1 = 4.0;
    sceneSpec.background.hmF1 = 185;
    sceneSpec.background.HF1 = 22;
    sceneSpec.background.foF2 = 8.3;
    sceneSpec.background.hmF2 = 300;
    sceneSpec.background.HF2bot = 44;
    sceneSpec.background.HF2top = 82;
    sceneSpec.background.NeFloor = 1e8;

    sceneSpec.geo.latDeg = 30.0;
    sceneSpec.geo.lonDeg = 114.0;
    sceneSpec.time.utcDatetime = datetime(2026,5,14,6,0,0,'TimeZone','UTC');
    sceneSpec.iri.mode = 'iri2020_python';
    sceneSpec.iri.pythonExe = 'C:\Users\20171\iri2020_env\python.exe';
    sceneSpec.iri.helperScript = fullfile(fileparts(mfilename('fullpath')), 'iri2020_profile.py');
    sceneSpec.iri.note = 'IRI2020 Python adapter; falls back only if mode is changed to fallback_chapman.';

    % 唯一异常：Es 偶发 E 层。
    sceneSpec.Es.enabled = true;
    sceneSpec.Es.foEsMHz = 6.4;
    sceneSpec.Es.foEsSigmaMHz = 0.9;
    sceneSpec.Es.foEsMinMHz = 1.2;
    sceneSpec.Es.foEsMaxMHz = 11.0;
    sceneSpec.Es.targetMode = 'iri_background_excess';
    sceneSpec.Es.foEsExcessOverIriEMHz = 0.8;
    sceneSpec.Es.hEsKm = 108;
    sceneSpec.Es.hEsSigmaKm = 2.5;
    sceneSpec.Es.thicknessKm = 1.1;
    sceneSpec.Es.patchScaleKm = 45;
    sceneSpec.Es.patchThreshold = -0.18;
    sceneSpec.Es.driftKmMin = [0.50, 0.12];
    sceneSpec.Es.reflectivity = 1.0;
    sceneSpec.Es.radialVelocityMean = 0;
    sceneSpec.Es.radialVelocityStd = 12;

    % 明确删除其他异常类型。
    sceneSpec.Es.blanketing.enabled = false;
    sceneSpec.FRegion.depletion.enabled = false;
    sceneSpec.FRegion.irregularity.enabled = false;
    sceneSpec.FRegion.range.enabled = false;
    sceneSpec.FRegion.frequency.enabled = false;
    sceneSpec.FRegion.dynamic.enabled = false;
    sceneSpec.TID.enabled = false;
    sceneSpec.absorptionAnomaly.enabled = false;
end

function cfg = make_initial_strategy()
    cfg = struct();
    cfg.codeType = 'barker';
    cfg.codeLength = 13;
    cfg.fStartMHz = 1.5;
    cfg.fEndMHz = 14.0;
    cfg.dfMHz = 0.25;
    cfg.PRP = 8e-3;
    cfg.chipLength = 20e-6;
    cfg.Ncoh = 16;
    cfg.samplePerChip = 8;
    cfg.guardTime = 80e-6;
    cfg.maxHeightKm = 900;
    cfg.noiseStd = 0.018;
    cfg.useDopplerFFT = true;  % 固定链路处理，不作为 Es-only 策略优化变量。
    cfg.rangeAmbiguityMode = 'wrap';
    cfg.includePropagationPhase = true;
    cfg.useFractionalDelay = true;
    cfg.normalizePulseCompression = true;
    cfg.debugFreqMHz = 6.0;
    cfg = refresh_strategy(cfg);
end

function pref = make_es_optimizer_preference()
    pref = struct();

    % Task-driven optimization mode. Users may override this with
    % runOpt.userPref.taskMode = 'fast'/'foEs'/'hEs'/'weakEs'/'balanced'.
    pref.taskMode = 'balanced';

    % 理论连续参数范围。不是固件档位约束，而是避免无界最优的任务/物理边界。
    pref.bounds.fStartMHz = [1.0, 8.0];
    pref.bounds.fEndMHz = [3.0, 16.0];
    pref.bounds.dfMHz = [0.02, 0.50];
    pref.bounds.PRP = [5e-3, 15e-3];
    pref.bounds.chipLength = [8e-6, 40e-6];

    % Es-only 策略偏好：频率分辨率 + 快速扫频。
    pref.referenceDfMHz = 0.10;
    pref.referenceHeightResolutionKm = 2.0;

    % 允许的离散码型和整数 Ncoh 搜索范围。
    pref.codeTypeSet = {'barker','complementary'};
    pref.codeLengthSet = [13, 16];
    pref.NcohIntegerRange = [6, 48];
    pref.NcohSearchStep = 2;

    % Toolbox-free constrained NSGA-II settings used by the final optimizer.
    % The weighted score is retained only as an auxiliary reporting field and
    % tie-breaker after the multi-objective candidate set has been generated.
    pref.optimizerMethod = 'nsga2';
    pref.nsga2.populationSize = 80;
    pref.nsga2.nGenerations = 40;
    pref.nsga2.crossoverProbability = 0.85;
    pref.nsga2.mutationProbability = 0.18;
    pref.nsga2.seed = 20260515;

    % 任务/物理约束。
    pref.maxScanTimeSec = 20;
    pref.maxHeightKm = 900;
    pref.heightMarginKm = 100;
    pref.guardTime = 80e-6;
    pref.maxDutyRatio = 0.20;
    pref.maxPreferredHeightResolutionKm = 3.1;
    pref.minPreferredNcoh = 4;
    pref.maxPreferredScanTimeSec = 1.2;
    pref.maxAdaptiveScanTimeSec = 3.0;
    pref.maxPreferredDfMHz = 0.28;
    pref.minIntegrationGainDb = 18.0;
    pref.minFrequencySamples = 10;

    % Es 目标区域构造。
    pref.target.iriPriorStartFlexMHz = 0.45;
    pref.target.iriPriorEndFlexMHz = 0.55;
    pref.target.userMarginMHz = 0.50;

    % Es 强度软阈值，用初探 foEs 连续调节偏好强度。
    pref.softThreshold.foEsMHz.x0 = 4.5;
    pref.softThreshold.foEsMHz.tau = 0.8;
end

function opt = make_forward_options()
    opt = struct();
    opt.scenarioSeed = 3101;
    opt.subraySeed = 2026;
    opt.noiseSeedBase = 9000;
    opt.nSubRays = 45;
    opt.apertureKm = 95;
    opt.sceneTimeMode = 'frozen';
    opt.frozenSceneTimeSec = 0;
    opt.truthFreqListMHz = 1.5:0.05:14.0;
    opt.verbose = true;
end

function cfg = refresh_strategy(cfg)
    if ~isfield(cfg, 'codeLength') || isempty(cfg.codeLength)
        cfg.codeLength = code_length_from_type(cfg.codeType);
    end
    validate_code_choice(cfg.codeType, cfg.codeLength);
    cfg.Fs = cfg.samplePerChip / cfg.chipLength;
    cfg.fListMHz = cfg.fStartMHz:cfg.dfMHz:cfg.fEndMHz;
    cfg.fIF1 = 0.31 * cfg.Fs;
    cfg.fIF2 = 0.09 * cfg.Fs;
    cfg.ddcCutoff1Hz = 0.45 * cfg.Fs;
    cfg.ddcCutoff2Hz = min(0.32 * cfg.Fs, 1.5 / cfg.chipLength);
end

function L = code_length_from_type(codeType)
    switch lower(codeType)
        case {'barker','baker','barker13'}
            L = 13;
        case {'complementary','golay','互补码','complementary16','golay16'}
            L = 16;
        otherwise
            error('Unsupported codeType: %s', codeType);
    end
end

%% ========================================================================
%%                         Scene construction and truth
%% ========================================================================

function scene = build_scene_from_sceneSpec(sceneSpec)
    scene = struct();
    scene.name = sceneSpec.name;
    scene.zGridKm = 70:1:700;
    scene.mapXKm = -300:5:300;
    scene.mapYKm = -300:5:300;
    scene.bg = sceneSpec.background;
    scene.geo = sceneSpec.geo;
    scene.time = sceneSpec.time;
    scene.iri = sceneSpec.iri;
    scene.iri.fallback = sceneSpec.background;
    [NeBg0, iriInfo0] = get_iri_background_profile(scene.geo.latDeg, scene.geo.lonDeg, scene.time.utcDatetime, scene.zGridKm(:), scene.iri);
    scene.iriBackground.hKm = scene.zGridKm(:);
    scene.iriBackground.Ne = NeBg0;
    scene.iriBackground.info = iriInfo0;

    es = sceneSpec.Es;
    scene.switch.EsOn = logical(es.enabled);
    iriFoE = scene.iriBackground.info.foEBackgroundMHz;
    if isfield(es, 'targetMode') && strcmpi(es.targetMode, 'iri_background_excess')
        scene.Es.foEsMean = max(es.foEsMHz, iriFoE + es.foEsExcessOverIriEMHz);
        scene.Es.targetMode = es.targetMode;
        scene.Es.foEsExcessOverIriEMHz = es.foEsExcessOverIriEMHz;
    else
        scene.Es.foEsMean = es.foEsMHz;
        scene.Es.targetMode = 'absolute';
        scene.Es.foEsExcessOverIriEMHz = NaN;
    end
    scene.Es.foEsSigma = es.foEsSigmaMHz;
    scene.Es.foEsMin = es.foEsMinMHz;
    scene.Es.foEsMax = max(es.foEsMaxMHz, scene.Es.foEsMean + 2*scene.Es.foEsSigma);
    scene.Es.hMeanKm = es.hEsKm;
    scene.Es.hSigmaKm = es.hEsSigmaKm;
    scene.Es.thickKm = es.thicknessKm;
    scene.Es.corrKm = es.patchScaleKm;
    scene.Es.patchThr = es.patchThreshold;
    scene.Es.vxKmMin = es.driftKmMin(1);
    scene.Es.vyKmMin = es.driftKmMin(2);
    scene.Es.reflectivity = es.reflectivity * double(scene.switch.EsOn);
    scene.Es.vrMean = es.radialVelocityMean;
    scene.Es.vrStd = es.radialVelocityStd;
    scene.Es.classifyMinFraction = 0.25;

    % 删除其他异常。F 区正常。
    scene.switch.BlanketingOn = false;
    scene.switch.FDepletionOn = false;
    scene.switch.FIrregularityOn = false;
    scene.F.reflectivity = 0.22;
    scene.F.normalReflectivity = 0.22;
    scene.F.vrMean = 0;
    scene.F.vrStd = 3;

    scene.echo.rangeLossExponent = 0.75;
    scene.echo.criticalBoostGain = 0.18;
    scene.echo.criticalBoostWidthMHz = 0.60;

end

function scene = initialize_scene_maps(scene)
    x = scene.mapXKm;
    y = scene.mapYKm;
    dx = abs(x(2)-x(1));
    dy = abs(y(2)-y(1));
    nx = numel(x);
    ny = numel(y);
    scene.maps.rEsFo = corr2d_field(nx, ny, scene.Es.corrKm, dx, dy, scene.seedBase + 1);
    scene.maps.rEsH = corr2d_field(nx, ny, scene.Es.corrKm, dx, dy, scene.seedBase + 2);
    [~, centerComponents, centerTruth] = build_es_ionosphere_profile(0, 0, scene.zGridKm(:), 0, scene);
    scene.constructedProfile.center = centerComponents;
    scene.constructedProfile.center.truth = centerTruth;
end

function subraySet = build_common_subray_set(apertureKm, nSubRays, seed)
    rng(seed);
    rr = apertureKm * sqrt(rand(nSubRays, 1));
    aa = 2*pi*rand(nSubRays, 1);
    subraySet.apertureKm = apertureKm;
    subraySet.xKm = rr .* cos(aa);
    subraySet.yKm = rr .* sin(aa);
    subraySet.phase = 2*pi*rand(nSubRays, 1);
    subraySet.amp = max(0.1, abs(1 + 0.25*randn(nSubRays, 1)));
    subraySet.vrEsN = randn(nSubRays, 1);
    subraySet.vrFN = randn(nSubRays, 1);
end

function cfg = attach_subray_set(cfg, subraySet)
    cfg.apertureKm = subraySet.apertureKm;
    cfg.nSubRays = numel(subraySet.xKm);
    cfg.subrayXKm = subraySet.xKm(:);
    cfg.subrayYKm = subraySet.yKm(:);
    cfg.subrayPhase = subraySet.phase(:);
    cfg.subrayAmp = subraySet.amp(:);
    cfg.subrayVrEsN = subraySet.vrEsN(:);
    cfg.subrayVrFN = subraySet.vrFN(:);
end

function sceneTruth = compute_es_scene_truth(sceneSpec, scene, subraySet, opt)
    z = scene.zGridKm(:);
    x = [0; subraySet.xKm(:)];
    y = [0; subraySet.yKm(:)];
    foEs = nan(numel(x),1);
    foEsEff = nan(numel(x),1);
    foEbg = nan(numel(x),1);
    esFrac = nan(numel(x),1);
    hEs = nan(numel(x),1);
    for k = 1:numel(x)
        [~, d] = ionosphere_profile_at_xy(x(k), y(k), z, opt.frozenSceneTimeSec, scene);
        foEs(k) = d.foEsLayerOnlyMHz;
        foEsEff(k) = d.foEsEffMHz;
        foEbg(k) = d.foEBackgroundMHz;
        esFrac(k) = d.EsMaxFraction;
        hEs(k) = d.hEsKm;
    end
    sceneTruth = struct();
    sceneTruth.sceneName = scene.name;
    sceneTruth.foEsLayerOnlyMHz = max_finite(foEs);
    sceneTruth.foEsEffectiveMHz = max_finite(foEsEff);
    sceneTruth.foEBackgroundMHz = max_finite(foEbg);
    sceneTruth.EsMaxFraction = max_finite(esFrac);
    sceneTruth.foEsMHz = sceneTruth.foEsEffectiveMHz;
    sceneTruth.hEsKm = median_finite(hEs);
    sceneTruth.EsEnabled = sceneSpec.Es.enabled;
    sceneTruth.background = scene.iriBackground.info;
    sceneTruth.summaryTable = table(string(scene.name), sceneTruth.foEBackgroundMHz, sceneTruth.foEsLayerOnlyMHz, sceneTruth.foEsEffectiveMHz, sceneTruth.EsMaxFraction, sceneTruth.hEsKm, sceneTruth.EsEnabled, ...
        'VariableNames', {'sceneName','foEBackgroundMHz','foEsLayerOnlyMHz','foEsEffectiveMHz','EsMaxFraction','hEsKm','EsEnabled'});
end

function echoTruth = generate_truth_echo_table(scene, subraySet, fListMHz, tSec)
    cfg = make_initial_strategy();
    cfg = attach_subray_set(cfg, subraySet);
    echoTruth = empty_echo_truth_table();
    for i = 1:numel(fListMHz)
        echo = scene_to_echo_channel(fListMHz(i), tSec, 0, cfg, scene);
        echoTruth = [echoTruth; echo_to_truth_table(echo, fListMHz(i), tSec, 0)]; %#ok<AGROW>
    end
end

function truthFeature = build_es_truth_feature(sceneTruth, echoTruth)
    truthFeature = struct();
    truthFeature.Es.requested = true;
    truthFeature.Es.foEsMHz = sceneTruth.foEsMHz;
    truthFeature.Es.foEsLayerOnlyMHz = sceneTruth.foEsLayerOnlyMHz;
    truthFeature.Es.foEsEffectiveMHz = sceneTruth.foEsEffectiveMHz;
    truthFeature.Es.foEBackgroundMHz = sceneTruth.foEBackgroundMHz;
    truthFeature.Es.EsMaxFraction = sceneTruth.EsMaxFraction;
    truthFeature.Es.hEsPrimeKm = NaN;
    truthFeature.Es.hEsTrueKm = sceneTruth.hEsKm;
    truthFeature.background = sceneTruth.background;

    if ~isempty(echoTruth) && istable(echoTruth) && height(echoTruth) > 0
        idx = strcmp(echoTruth.layerName, 'Es');
        if any(idx)
            truthFeature.Es.foEsMHz = max(echoTruth.fMHz(idx));
            truthFeature.Es.hEsPrimeKm = median_finite(echoTruth.hVirtKm(idx));
        end
    end
end

%% ========================================================================
%%                         Forward chain
%% ========================================================================

function sim = run_forward_one_strategy(cfg, scene, opt, label)
    rng(opt.noiseSeedBase + sum(double(label)));
    if opt.verbose
        fprintf('\nForward run: %s | %s-%d, %.4f MHz step, chip %.2fus, PRP %.2fms, Ncoh %d\n', ...
            label, cfg.codeType, cfg.codeLength, cfg.dfMHz, cfg.chipLength*1e6, cfg.PRP*1e3, cfg.Ncoh);
    end
    scan = simulate_frequency_scan(cfg, scene, opt.verbose);
    sim = struct();
    sim.name = label;
    sim.fMHz = scan.fListMHz;
    sim.hKm = scan.heightAxisKm;
    sim.ionogram = scan.ionogram;
    sim.ionogramDb = 20*log10(abs(scan.ionogram)./max(abs(scan.ionogram(:))+eps) + 1e-6);
    sim.scanTimeSec = scan.scanTimeSec;
end

function scan = simulate_frequency_scan(cfg, scene, verbose)
    fList = cfg.fListMHz;
    ionogram = [];
    heightAxisKm = [];
    scanClockSec = 0;
    for iF = 1:numel(fList)
        out = simulate_one_frequency(fList(iF), scanClockSec, cfg, scene);
        if isempty(ionogram)
            heightAxisKm = out.heightAxisKm;
            ionogram = zeros(numel(heightAxisKm), numel(fList));
        end
        ionogram(:, iF) = out.heightProfile(:);
        scanClockSec = scanClockSec + out.timeUsedSec;
        if verbose && (mod(iF, max(1,round(numel(fList)/5))) == 0 || iF == numel(fList))
            fprintf('  %3d/%3d f=%.2f MHz\n', iF, numel(fList), fList(iF));
        end
    end
    scan = struct('fListMHz', fList, 'heightAxisKm', heightAxisKm, 'ionogram', ionogram, 'scanTimeSec', scanClockSec);
end

function out = simulate_one_frequency(fMHz, tFreqStartSec, cfg, scene)
    [codeA, codeB] = make_phase_code(cfg);
    info = derive_strategy_info(cfg);
    nDelay = info.nDelaySamp;

    if is_complementary_mode(cfg)
        profiles = complex(zeros(nDelay, cfg.Ncoh));
        for m = 1:cfg.Ncoh
            tA = tFreqStartSec + (2*m-2)*cfg.PRP;
            tB = tFreqStartSec + (2*m-1)*cfg.PRP;
            echoA = scene_to_echo_channel(fMHz, scene_time(tA,cfg), 2*m-1, cfg, scene);
            echoB = scene_to_echo_channel(fMHz, scene_time(tB,cfg), 2*m, cfg, scene);
            rxA = synthesize_rx_if1(echoA, codeA, tA, cfg);
            rxB = synthesize_rx_if1(echoB, codeB, tB, cfg);
            bbA = receiver_two_stage_ddc(rxA, cfg);
            bbB = receiver_two_stage_ddc(rxB, cfg);
            pcA = pulse_compress_bb(bbA, codeA, nDelay, cfg);
            pcB = pulse_compress_bb(bbB, codeB, nDelay, cfg);
            profiles(:,m) = 0.5*(pcA + pcB);
        end
        slowDt = 2*cfg.PRP;
        timeUsedSec = 2*cfg.Ncoh*cfg.PRP;
    else
        profiles = complex(zeros(nDelay, cfg.Ncoh));
        for m = 1:cfg.Ncoh
            tPulse = tFreqStartSec + (m-1)*cfg.PRP;
            echo = scene_to_echo_channel(fMHz, scene_time(tPulse,cfg), m, cfg, scene);
            rx = synthesize_rx_if1(echo, codeA, tPulse, cfg);
            bb = receiver_two_stage_ddc(rx, cfg);
            profiles(:,m) = pulse_compress_bb(bb, codeA, nDelay, cfg);
        end
        slowDt = cfg.PRP;
        timeUsedSec = cfg.Ncoh*cfg.PRP;
    end

    if cfg.useDopplerFFT
        RD = fftshift(fft(profiles, [], 2), 2); %#ok<NASGU>
        heightProfile = max(abs(RD), [], 2);
    else
        heightProfile = abs(sum(profiles,2));
    end
    c0 = 299792458;
    heightAxisKm = c0*((0:nDelay-1).'/cfg.Fs)/2/1e3;
    out = struct('heightAxisKm', heightAxisKm, 'heightProfile', heightProfile, 'timeUsedSec', timeUsedSec, 'slowDt', slowDt);
end

function tScene = scene_time(tActual, cfg)
    if isfield(cfg,'sceneTimeMode') && strcmpi(cfg.sceneTimeMode,'frozen')
        tScene = cfg.frozenSceneTimeSec;
    else
        tScene = tActual;
    end
end

function echo = scene_to_echo_channel(fMHz, tSec, pulseIndex, cfg, scene)
    z = scene.zGridKm(:);
    echo = empty_echo_struct();
    for n = 1:cfg.nSubRays
        xq = cfg.subrayXKm(n);
        yq = cfg.subrayYKm(n);
        [Ne, d] = ionosphere_profile_at_xy(xq, yq, z, tSec, scene);
        fp = fpMHz_from_Ne(Ne);
        idxFirst = find(fp >= fMHz, 1, 'first');
        if isempty(idxFirst) || idxFirst < 2
            continue;
        end
        hFirst = interp_reflection_height(z, fp, fMHz, idxFirst);
        esFracAtReflection = d.EsFraction(idxFirst);
        if hFirst < 150 && scene.switch.EsOn && esFracAtReflection >= scene.Es.classifyMinFraction
            layerName = 'Es';
        elseif hFirst < 150
            layerName = 'IRI_E_normal';
        else
            layerName = 'IRI_F_normal';
        end
        echo = append_echo(echo, fMHz, z, fp, idxFirst, layerName, xq, yq, n, pulseIndex, cfg, scene, d);
    end
end

function echo = append_echo(echo, fMHz, z, fp, idx, layerName, xq, yq, subIdx, pulseIndex, cfg, scene, d)
    c0 = 299792458;
    fRF = fMHz*1e6;
    hTrue = interp_reflection_height(z, fp, fMHz, idx);
    hVirt = virtual_height_km(z, fp, fMHz, idx, hTrue);
    tau = 2*hVirt*1e3/c0;

    switch layerName
        case 'Es'
            baseAmp = scene.Es.reflectivity;
            vr = scene.Es.vrMean + scene.Es.vrStd*cfg.subrayVrEsN(subIdx);
            fCrit = d.foEsEffMHz;
        case 'IRI_E_normal'
            baseAmp = 0.25;
            vr = 0.5*scene.Es.vrStd*cfg.subrayVrEsN(subIdx);
            fCrit = d.foEBackgroundMHz;
        otherwise
            baseAmp = scene.F.normalReflectivity;
            vr = scene.F.vrMean + scene.F.vrStd*cfg.subrayVrFN(subIdx);
            fCrit = d.foF2EffMHz;
    end

    fd = 2*fRF*vr/c0;
    rangeLoss = (120/max(hVirt,100))^scene.echo.rangeLossExponent;
    apertureLoss = exp(-0.5*(hypot(xq,yq)/cfg.apertureKm)^2);
    criticalBoost = 1 + scene.echo.criticalBoostGain*exp(-0.5*((fCrit-fMHz)/scene.echo.criticalBoostWidthMHz)^2);
    ampAbs = baseAmp * cfg.subrayAmp(subIdx) * rangeLoss * apertureLoss * criticalBoost;
    phase = cfg.subrayPhase(subIdx) - 2*pi*fRF*tau;

    k = numel(echo.tau) + 1;
    echo.tau(k,1) = tau;
    echo.amp(k,1) = ampAbs * exp(1j*phase);
    echo.fd(k,1) = fd;
    echo.hTrueKm(k,1) = hTrue;
    echo.hVirtKm(k,1) = hVirt;
    echo.layerName{k,1} = layerName;
    echo.subrayIndex(k,1) = subIdx;
    echo.pulseIndex(k,1) = pulseIndex;
end

function echo = empty_echo_struct()
    echo = struct();
    echo.tau = zeros(0,1);
    echo.amp = complex(zeros(0,1));
    echo.fd = zeros(0,1);
    echo.hTrueKm = zeros(0,1);
    echo.hVirtKm = zeros(0,1);
    echo.layerName = cell(0,1);
    echo.subrayIndex = zeros(0,1);
    echo.pulseIndex = zeros(0,1);
end

function T = echo_to_truth_table(echo, fMHz, tSec, pulseIndex)
    n = numel(echo.tau);
    if n == 0
        T = empty_echo_truth_table();
        return;
    end
    T = table(fMHz*ones(n,1), tSec*ones(n,1), pulseIndex*ones(n,1), echo.subrayIndex(:), echo.layerName(:), echo.tau(:)*1e3, echo.hTrueKm(:), echo.hVirtKm(:), abs(echo.amp(:)), angle(echo.amp(:)), echo.fd(:), ...
        'VariableNames', {'fMHz','tSec','pulseIndex','subrayIndex','layerName','tauMs','hTrueKm','hVirtKm','ampAbs','ampPhaseRad','fdHz'});
end

function T = empty_echo_truth_table()
    T = table(zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), cell(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', {'fMHz','tSec','pulseIndex','subrayIndex','layerName','tauMs','hTrueKm','hVirtKm','ampAbs','ampPhaseRad','fdHz'});
end

function rxIF1 = synthesize_rx_if1(echo, code, pulseAbsTimeSec, cfg)
    Fs = cfg.Fs;
    Nrec = max(1, floor(cfg.PRP*Fs));
    NsChip = max(1, round(cfg.chipLength*Fs));
    txBB = repelem(code(:), NsChip);
    Ntx = numel(txBB);
    tTx = (0:Ntx-1)'/Fs;
    txIF1 = txBB .* exp(1j*2*pi*cfg.fIF1*tTx);
    rxIF1 = complex(zeros(Nrec,1));
    for k = 1:numel(echo.tau)
        tauK = echo.tau(k);
        if strcmpi(cfg.rangeAmbiguityMode, 'wrap')
            tauEff = mod(tauK, cfg.PRP);
        else
            if tauK >= cfg.PRP, continue; end
            tauEff = tauK;
        end
        if tauEff < (Ntx/Fs + cfg.guardTime)
            continue;
        end
        pulse = echo.amp(k).*txIF1.*exp(1j*2*pi*echo.fd(k)*(pulseAbsTimeSec + tTx));
        rxIF1 = add_fractional_pulse(rxIF1, pulse, tauEff*Fs, cfg.useFractionalDelay);
    end
    noise = cfg.noiseStd/sqrt(2)*(randn(Nrec,1)+1j*randn(Nrec,1));
    rxIF1 = rxIF1 + noise;
end

function y = add_fractional_pulse(y, pulse, delaySamp, useFrac)
    N = numel(y);
    L = numel(pulse);
    if ~useFrac
        d = round(delaySamp);
        idx = d + (1:L)';
        valid = idx>=1 & idx<=N;
        y(idx(valid)) = y(idx(valid)) + pulse(valid);
        return;
    end
    d0 = floor(delaySamp);
    frac = delaySamp - d0;
    idx1 = d0 + (1:L)';
    idx2 = idx1 + 1;
    valid1 = idx1>=1 & idx1<=N;
    valid2 = idx2>=1 & idx2<=N;
    y(idx1(valid1)) = y(idx1(valid1)) + (1-frac)*pulse(valid1);
    y(idx2(valid2)) = y(idx2(valid2)) + frac*pulse(valid2);
end

function bb = receiver_two_stage_ddc(rxIF1, cfg)
    Fs = cfg.Fs;
    N = numel(rxIF1);
    t = (0:N-1)'/Fs;
    x1 = rxIF1 .* exp(-1j*2*pi*(cfg.fIF1-cfg.fIF2)*t);
    x1 = fft_lowpass(x1, Fs, cfg.ddcCutoff1Hz);
    x2 = x1 .* exp(-1j*2*pi*cfg.fIF2*t);
    bb = fft_lowpass(x2, Fs, cfg.ddcCutoff2Hz);
end

function profile = pulse_compress_bb(bb, code, nDelay, cfg)
    NsChip = max(1, round(cfg.chipLength*cfg.Fs));
    txBB = repelem(code(:), NsChip);
    mf = conj(flipud(txBB));
    y = conv(bb, mf, 'full');
    if cfg.normalizePulseCompression
        y = y / max(sum(abs(txBB).^2), eps);
    end
    startIdx = numel(txBB);
    profile = complex(zeros(nDelay,1));
    if startIdx <= numel(y)
        nAvail = min(nDelay, numel(y)-startIdx+1);
        profile(1:nAvail) = y(startIdx:startIdx+nAvail-1);
    end
end

%% ========================================================================
%%                         Ionospheric profile
%% ========================================================================

function [NeTotal, truth] = ionosphere_profile_at_xy(xKm, yKm, zKm, tSec, scene)
    [NeTotal, ~, truth] = build_es_ionosphere_profile(xKm, yKm, zKm, tSec, scene);
end

function [NeTotal, components, truth] = build_es_ionosphere_profile(xKm, yKm, zKm, tSec, scene)
    zKm = zKm(:);
    tMin = tSec/60;

    [NeIRI, iriInfo] = get_iri_background_profile( ...
        scene.geo.latDeg, scene.geo.lonDeg, scene.time.utcDatetime, zKm, scene.iri);

    if scene.switch.EsOn
        xEs = xKm - scene.Es.vxKmMin*tMin;
        yEs = yKm - scene.Es.vyKmMin*tMin;
        rEsFo = map_value(scene, 'rEsFo', xEs, yEs, 0);
        rEsH = map_value(scene, 'rEsH', xEs, yEs, 0);
        foEs = scene.Es.foEsMean + scene.Es.foEsSigma*rEsFo;
        foEs = min(max(foEs, scene.Es.foEsMin), scene.Es.foEsMax);
        hEs = scene.Es.hMeanKm + scene.Es.hSigmaKm*rEsH;
        patchWeight = 0.15 + 0.85/(1 + exp(-(rEsFo-scene.Es.patchThr)/0.35));
        NeTarget = Ne_from_foMHz(foEs);
        NeBgAtEs = interp1(zKm, NeIRI, hEs, 'linear', 'extrap');
        NeEsPeak = max(NeTarget - NeBgAtEs, 0);
        NeEs = patchWeight*NeEsPeak.*exp(-0.5*((zKm-hEs)/scene.Es.thickKm).^2);
    else
        foEs = NaN;
        hEs = NaN;
        patchWeight = 0;
        NeTarget = NaN;
        NeBgAtEs = NaN;
        NeEsPeak = 0;
        NeEs = zeros(size(zKm));
    end

    NeTotal = max(NeIRI + NeEs, scene.bg.NeFloor);

    fpTotal = fpMHz_from_Ne(NeTotal);
    fpEsOnly = fpMHz_from_Ne(NeEs);
    fpIRI = fpMHz_from_Ne(NeIRI);
    esFraction = NeEs ./ max(NeTotal, eps);
    esMask = zKm >= 85 & zKm <= 150;
    fMask = zKm >= 180 & zKm <= 550;

    components = struct();
    components.hKm = zKm;
    components.NeIRI = NeIRI;
    components.NeEs = NeEs;
    components.NeTotal = NeTotal;
    components.fpIRI = fpIRI;
    components.fpEs = fpEsOnly;
    components.fpTotal = fpTotal;
    components.EsFraction = esFraction;

    truth = struct();
    truth.backgroundModel = iriInfo.mode;
    truth.iriInfo = iriInfo;
    truth.foEBackgroundMHz = max_finite(fpIRI(esMask));
    truth.foEsLayerOnlyMHz = max_finite(fpEsOnly(esMask));
    truth.foEsEffMHz = max_finite(fpTotal(esMask));
    truth.foF2EffMHz = max_finite(fpTotal(fMask));
    truth.foEsTargetMHz = foEs;
    truth.NeEsTargetPeak = NeTarget;
    truth.NeBgAtEsPeak = NeBgAtEs;
    truth.NeEsIncrementPeak = NeEsPeak;
    truth.hEsKm = hEs;
    truth.EsPatchWeight = patchWeight;
    truth.NeBackground = NeIRI;
    truth.NeEsIncrement = NeEs;
    truth.EsFraction = esFraction;
    truth.EsMaxFraction = max_finite(esFraction(esMask));
end

function [NeBg, iriInfo] = get_iri_background_profile(latDeg, lonDeg, timeUTC, hKm, iriOpt)
    persistent cacheKey cacheNe cacheInfo
    hKm = hKm(:);
    mode = 'fallback_chapman';
    if isfield(iriOpt, 'mode') && ~isempty(iriOpt.mode)
        mode = iriOpt.mode;
    end
    timeIso = datetime_to_utc_iso(timeUTC);
    dh = median(diff(hKm));
    key = sprintf('%s|%.8f|%.8f|%s|%d|%.3f|%.3f|%.6g', lower(mode), latDeg, lonDeg, timeIso, numel(hKm), hKm(1), hKm(end), dh);
    if ~isempty(cacheKey) && strcmp(cacheKey, key)
        NeBg = cacheNe;
        iriInfo = cacheInfo;
        return;
    end

    iriInfo = struct();
    iriInfo.mode = mode;
    iriInfo.latDeg = latDeg;
    iriInfo.lonDeg = lonDeg;
    iriInfo.timeUTC = timeUTC;

    switch lower(mode)
        case 'precomputed'
            if ~isfield(iriOpt, 'hKm') || ~isfield(iriOpt, 'Ne')
                error('IRI precomputed mode requires iriOpt.hKm and iriOpt.Ne.');
            end
            hSrc = iriOpt.hKm(:);
            NeSrc = iriOpt.Ne(:);
            NeBg = interp1(hSrc, NeSrc, hKm, 'linear', 'extrap');
            iriInfo.source = 'precomputed IRI electron density profile';

        case {'iri2020_python','python'}
            [NeBg, pyInfo] = iri2020_python_background(latDeg, lonDeg, timeIso, hKm, iriOpt);
            iriInfo.source = pyInfo.source;
            iriInfo.pythonExe = pyInfo.pythonExe;
            iriInfo.foF2 = pyInfo.foF2;
            iriInfo.hmF2 = pyInfo.hmF2;
            iriInfo.NmF2 = pyInfo.NmF2;
            iriInfo.hmE = pyInfo.hmE;
            iriInfo.NmE = pyInfo.NmE;
            iriInfo.TEC = pyInfo.TEC;
            iriInfo.f107 = pyInfo.f107;
            iriInfo.ap = pyInfo.ap;

        case {'iri2020_matlab','iri_matlab'}
            error(['IRI mode "%s" is configured, but no local IRI2020 MATLAB adapter is wired in this single-file package. ', ...
                'Provide iriOpt.hKm/iriOpt.Ne with mode="precomputed", or replace this branch with the installed IRI interface call.'], mode);

        case {'fallback_chapman','chapman'}
            if ~isfield(iriOpt, 'fallback')
                error('fallback_chapman mode requires iriOpt.fallback background parameters.');
            end
            [NeBg, fallbackInfo] = fallback_chapman_background(hKm, iriOpt.fallback);
            iriInfo.source = 'fallback Chapman background used through IRI adapter';
            iriInfo.fallback = fallbackInfo;

        otherwise
            error('Unknown IRI background mode: %s', mode);
    end

    NeFloor = 0;
    if isfield(iriOpt, 'fallback') && isfield(iriOpt.fallback, 'NeFloor')
        NeFloor = iriOpt.fallback.NeFloor;
    end
    NeBg = max(NeBg(:), NeFloor);
    iriInfo.foEBackgroundMHz = max_finite(fpMHz_from_Ne(NeBg(hKm >= 85 & hKm <= 150)));
    iriInfo.foF2BackgroundMHz = max_finite(fpMHz_from_Ne(NeBg(hKm >= 180 & hKm <= 550)));
    cacheKey = key;
    cacheNe = NeBg;
    cacheInfo = iriInfo;
end

function [NeBg, pyInfo] = iri2020_python_background(latDeg, lonDeg, timeIso, hKm, iriOpt)
    if ~isfield(iriOpt, 'pythonExe') || isempty(iriOpt.pythonExe)
        error('iri2020_python mode requires iriOpt.pythonExe.');
    end
    if ~isfield(iriOpt, 'helperScript') || isempty(iriOpt.helperScript)
        error('iri2020_python mode requires iriOpt.helperScript.');
    end

    req = struct('latDeg', latDeg, 'lonDeg', lonDeg, 'timeUTC', timeIso, 'hKm', hKm(:).');
    tag = char(java.util.UUID.randomUUID());
    reqFile = fullfile(tempdir, ['iri_req_' tag '.json']);
    outFile = fullfile(tempdir, ['iri_out_' tag '.csv']);
    metaFile = fullfile(tempdir, ['iri_meta_' tag '.json']);
    cleanupObj = onCleanup(@() cleanup_temp_files({reqFile, outFile, metaFile})); %#ok<NASGU>

    fid = fopen(reqFile, 'w');
    if fid < 0
        error('Cannot write IRI request file: %s', reqFile);
    end
    fprintf(fid, '%s', jsonencode(req));
    fclose(fid);

    envRoot = fileparts(iriOpt.pythonExe);
    pathParts = {fullfile(envRoot, 'Library', 'mingw-w64', 'bin'), fullfile(envRoot, 'Library', 'bin'), fullfile(envRoot, 'Scripts'), envRoot};
    pathPrefix = strjoin(pathParts, ';');
    cmd = sprintf('set "PATH=%s;%%PATH%%" && "%s" "%s" "%s" "%s" "%s"', ...
        pathPrefix, iriOpt.pythonExe, iriOpt.helperScript, reqFile, outFile, metaFile);
    [status, cmdOut] = system(cmd);
    if status ~= 0
        error('IRI2020 Python call failed:\n%s', cmdOut);
    end

    M = readmatrix(outFile, 'NumHeaderLines', 1);
    if size(M,2) < 2
        error('IRI2020 Python output is malformed: %s', outFile);
    end
    NeBg = M(:,2);
    pyInfo = jsondecode(fileread(metaFile));
    pyInfo.pythonExe = iriOpt.pythonExe;
end

function cleanup_temp_files(files)
    for k = 1:numel(files)
        if exist(files{k}, 'file')
            delete(files{k});
        end
    end
end

function s = datetime_to_utc_iso(t)
    if isdatetime(t)
        if isempty(t.TimeZone)
            t.TimeZone = 'UTC';
        else
            t.TimeZone = 'UTC';
        end
        s = sprintf('%04d-%02d-%02dT%02d:%02d:%02.0f+00:00', year(t), month(t), day(t), hour(t), minute(t), second(t));
    else
        s = char(t);
    end
end

function [NeBg, info] = fallback_chapman_background(hKm, bg)
    NeE = chapman_1d(hKm, bg.hmE, bg.HE, Ne_from_foMHz(bg.foE));
    NeF1 = chapman_1d(hKm, bg.hmF1, bg.HF1, Ne_from_foMHz(bg.foF1));
    NeF2 = chapman_asym_1d(hKm, bg.hmF2, bg.HF2bot, bg.HF2top, Ne_from_foMHz(bg.foF2));
    NeBg = NeE + NeF1 + NeF2;

    info = struct();
    info.foE = bg.foE;
    info.hmE = bg.hmE;
    info.foF1 = bg.foF1;
    info.hmF1 = bg.hmF1;
    info.foF2 = bg.foF2;
    info.hmF2 = bg.hmF2;
end

%% ========================================================================
%%                         Preprocess and Es feature extraction
%% ========================================================================

function pp = default_preprocess_param_native()
    pp = struct();
    pp.useNativeGrid = true;
    pp.noiseBandFraction = 0.80;
    pp.madFloorDb = 1.2;
    pp.smoothSigmaHBin = 1.0;
    pp.smoothSigmaFBin = 0.7;
    pp.weakThreshold = 2.5;
    pp.midThreshold = 4.0;
    pp.strongThreshold = 6.0;
    pp.EsBandKm = [85, 150];
    pp.EBandKm = [85, 125];
end

function pre = preprocess_ionogram_native(fMHz, hKm, ionogram, pp)
    fMHz = fMHz(:).';
    hKm = hKm(:);
    I = abs(ionogram);

    scale = percentile_local(I(:), 99.5);
    if ~isfinite(scale) || scale <= eps
        scale = max(I(:)+eps);
    end
    In = I./max(scale, eps);
    IdB = 20*log10(In + 1e-6);

    noiseBand = hKm >= pp.noiseBandFraction*max(hKm);
    noiseMed = zeros(1,numel(fMHz));
    noiseMAD = zeros(1,numel(fMHz));
    for k = 1:numel(fMHz)
        x = IdB(noiseBand,k);
        noiseMed(k) = median(x);
        noiseMAD(k) = median(abs(x-noiseMed(k)));
    end
    sigma = max(noiseMAD, pp.madFloorDb);
    SNR = (IdB - repmat(noiseMed, numel(hKm), 1))./repmat(sigma, numel(hKm), 1);
    SNRs = conv2(SNR, gaussian_kernel2d(pp.smoothSigmaHBin, pp.smoothSigmaFBin), 'same');

    maskWeak = SNRs > pp.weakThreshold;
    maskMid = continuity_filter(SNRs > pp.midThreshold, 2, 2);
    maskStrong = continuity_filter(SNRs > pp.strongThreshold, 2, 2);

    eBand = hKm >= pp.EBandKm(1) & hKm <= pp.EBandKm(2);
    esBand = hKm >= pp.EsBandKm(1) & hKm <= pp.EsBandKm(2);
    pre = struct();
    pre.param = pp;
    pre.fGridMHz = fMHz;
    pre.hGridKm = hKm;
    pre.rawAmplitude = I;
    pre.normalizedAmplitude = In;
    pre.IdB = IdB;
    pre.SNR = SNR;
    pre.SNRs = SNRs;
    pre.maskWeak = maskWeak;
    pre.maskMid = maskMid;
    pre.maskStrong = maskStrong;
    pre.E = band_descriptors(fMHz, hKm, SNRs, maskWeak, maskMid, maskStrong, eBand);
    pre.Es = band_descriptors(fMHz, hKm, SNRs, maskWeak, maskMid, maskStrong, esBand);
    pre.note = 'Native-grid preprocessing. No cross-strategy interpolation.';
end

function D = band_descriptors(fGrid, hGrid, SNRs, maskWeak, maskMid, maskStrong, band)
    nF = numel(fGrid);
    hBand = hGrid(band);
    D.activeWeak = false(1,nF);
    D.activeMid = false(1,nF);
    D.activeStrong = false(1,nF);
    D.ridgeHeightKm = nan(1,nF);
    D.ridgeSNR = nan(1,nF);
    D.heightWidthWeakKm = nan(1,nF);
    for k = 1:nF
        sw = maskWeak(band,k);
        sm = maskMid(band,k);
        ss = maskStrong(band,k);
        D.activeWeak(k) = any(sw);
        D.activeMid(k) = any(sm);
        D.activeStrong(k) = any(ss);
        if any(ss), cand = ss; elseif any(sm), cand = sm; else, cand = sw; end
        if any(cand)
            snrCol = SNRs(band,k);
            snrCol(~cand) = -Inf;
            [D.ridgeSNR(k), idx] = max(snrCol);
            D.ridgeHeightKm(k) = hBand(idx);
        end
        D.heightWidthWeakKm(k) = height_width(hBand, sw);
    end
end

function feature = extract_es_features(pre)
    f = pre.fGridMHz;
    active = pre.Es.activeMid;
    weakActive = pre.Es.activeWeak;
    heightEstimate = robust_es_height_estimate(pre, active);
    feature = struct();
    feature.E.observable = any(pre.E.activeMid);
    feature.E.foEObservedRawMHz = max_freq(f, pre.E.activeMid);
    feature.E.activeMidFreqMHz = f(pre.E.activeMid);
    feature.E.meanSNR = mean_finite(pre.E.ridgeSNR(pre.E.activeMid));
    feature.E.traceContinuity = trace_continuity(f, pre.E.activeMid);
    feature.Es.observable = any(active);
    feature.Es.foEsMHz = max_freq(f, active);
    feature.Es.hEsPrimeKm = heightEstimate.hKm;
    feature.Es.hEsPrimeStdKm = heightEstimate.stdKm;
    feature.Es.hEsPrimeN = heightEstimate.nUsed;
    feature.Es.traceLengthMHz = freq_span(f, active);
    feature.Es.traceContinuity = trace_continuity(f, active);
    feature.Es.meanSNR = mean_finite(pre.Es.ridgeSNR(active));
    feature.Es.weakEdgeWidthMHz = max(0, freq_span(f, weakActive) - freq_span(f, active));
    feature.Es.heightWidthKm = median_finite(pre.Es.heightWidthWeakKm(active));
    feature.Quality.contrastDb = max(pre.IdB(:)) - median(pre.IdB(:));
    feature.summaryTable = table(feature.E.observable, feature.E.foEObservedRawMHz, feature.Es.observable, feature.Es.foEsMHz, feature.Es.hEsPrimeKm, feature.Es.traceContinuity, feature.Es.meanSNR, feature.Quality.contrastDb, ...
        'VariableNames', {'EObservable','foEObservedRawMHz','EsObservable','foEsMHz','hEsPrimeKm','EsContinuity','EsMeanSNR','ContrastDb'});
end

function est = robust_es_height_estimate(pre, active)
    est = struct('hKm', NaN, 'stdKm', NaN, 'nUsed', 0);
    if ~any(active)
        return;
    end

    h = pre.Es.ridgeHeightKm(active);
    snr = pre.Es.ridgeSNR(active);
    ok = isfinite(h) & isfinite(snr);
    h = h(ok);
    snr = snr(ok);
    if isempty(h)
        return;
    end

    h0 = median(h);
    madH = median(abs(h - h0));
    keep = abs(h - h0) <= max(6, 2.5*max(madH, eps));
    h = h(keep);
    snr = snr(keep);
    if isempty(h)
        est.hKm = h0;
        return;
    end

    w = max(snr - min(snr) + 1, 1);
    est.hKm = weighted_percentile_local(h, w, 30);
    est.stdKm = sqrt(sum(w.*(h-est.hKm).^2)/max(sum(w), eps));
    est.nUsed = numel(h);
end

function m = weighted_percentile_local(x, w, pct)
    x = x(:);
    w = w(:);
    ok = isfinite(x) & isfinite(w) & w > 0;
    x = x(ok);
    w = w(ok);
    if isempty(x)
        m = NaN;
        return;
    end
    [x, order] = sort(x);
    w = w(order);
    cw = cumsum(w)/sum(w);
    idx = find(cw >= pct/100, 1, 'first');
    m = x(idx);
end

function feature = attach_iri_background_context(feature, scene)
    info = scene.iriBackground.info;
    feature.Background = info;
    if isfield(info, 'foEBackgroundMHz')
        feature.Es.foEBackgroundMHz = info.foEBackgroundMHz;
    else
        feature.Es.foEBackgroundMHz = NaN;
    end
    if isfield(info, 'foF2BackgroundMHz')
        feature.Es.foF2BackgroundMHz = info.foF2BackgroundMHz;
    else
        feature.Es.foF2BackgroundMHz = NaN;
    end
    feature.Es.foEsExcessOverBgMHz = feature.Es.foEsMHz - feature.Es.foEBackgroundMHz;
    feature.Es.backgroundModel = scene.iri.mode;
end

function feature = stabilize_es_height_with_prior(feature, priorFeature)
    if ~isfield(priorFeature, 'Es') || ~isfield(feature, 'Es')
        return;
    end
    priorH = priorFeature.Es.hEsPrimeKm;
    currentH = feature.Es.hEsPrimeKm;
    if ~isfinite(priorH) || ~isfinite(currentH)
        return;
    end

    jumpKm = abs(currentH - priorH);
    if jumpKm > 2.0
        feature.Es.hEsPrimeKmRaw = currentH;
        feature.Es.hEsPrimeKm = priorH;
        feature.Es.hEsPrimePriorApplied = true;
    else
        feature.Es.hEsPrimeKmRaw = currentH;
        feature.Es.hEsPrimeKm = 0.6*currentH + 0.4*priorH;
        feature.Es.hEsPrimePriorApplied = true;
    end
end

%% ========================================================================
%%                         Es-only theoretical optimization
%% ========================================================================

function [optimizedCfg, optInfo] = optimize_strategy_es_only(initialCfg, sceneSpec, initialFeature, pref)
    pref = resolve_es_task_preference(pref, initialCfg, initialFeature);
    severity = compute_es_severity(sceneSpec, initialFeature, pref);

    targetRegion = build_es_target_region(initialCfg, initialFeature, pref);
    [candidateTable, nsgaInfo] = run_constrained_nsga2_es(initialCfg, targetRegion, pref);
    globalEvalCount = nsgaInfo.evaluationCount;

    candidateTable = sortrows(candidateTable, 'cost', 'ascend');
    topN = min(10, height(candidateTable));

    [bestCfg, bestCost, bestMetric, bestBreakdown, bestCons, selectionInfo] = select_strategy_from_pareto_candidates(candidateTable, initialCfg, targetRegion, pref);
    optimizedCfg = refresh_strategy(bestCfg);
    optInfo = struct();
    optInfo.method = 'Constrained NSGA-II multi-objective Es-only adaptive optimization';
    optInfo.taskProfile = pref.taskProfile;
    optInfo.nsga2 = nsgaInfo;
    optInfo.globalEvalCount = globalEvalCount;
    optInfo.localRefineCount = 0;
    optInfo.activeSeverity = severity;
    optInfo.targetRegion = targetRegion;
    optInfo.bestCost = bestCost;
    optInfo.bestMetrics = bestMetric;
    optInfo.bestCostBreakdown = bestBreakdown;
    optInfo.bestConstraint = bestCons;
    optInfo.candidateTable = candidateTable;
    optInfo.topCandidateTable = candidateTable(1:topN,:);
    optInfo.selectionInfo = selectionInfo;
    optInfo.reasonTable = build_es_optimizer_reason_table(optimizedCfg, severity, targetRegion, bestMetric, bestBreakdown, bestCons);
end

function validate_code_choice(codeType, codeLength)
    defaultLength = code_length_from_type(codeType);
    if codeLength ~= defaultLength
        error('Unsupported codeType/codeLength pair: %s-%d.', codeType, codeLength);
    end
end

function pref = resolve_es_task_preference(pref, initialCfg, initialFeature)
    mode = canonical_es_task_mode(get_opt(pref, 'taskMode', 'balanced'));
    pref.taskMode = mode;
    profile = make_es_task_profile(mode);

    pref.maxPreferredScanTimeSec = profile.maxPreferredScanTimeSec;
    pref.maxAdaptiveScanTimeSec = profile.maxAdaptiveScanTimeSec;
    pref.maxPreferredDfMHz = profile.maxPreferredDfMHz;
    pref.maxPreferredHeightResolutionKm = profile.maxPreferredHeightResolutionKm;
    pref.minPreferredNcoh = profile.minPreferredNcoh;
    pref.minIntegrationGainDb = profile.minIntegrationGainDb;
    pref.minFrequencySamples = profile.minFrequencySamples;
    pref.referenceDfMHz = profile.referenceDfMHz;
    pref.referenceHeightResolutionKm = profile.referenceHeightResolutionKm;
    pref.objectiveMode = profile.objectiveMode;
    pref.selectionMode = profile.selectionMode;
    pref.targetMode = profile.targetMode;
    pref.freezeFrequencyWindow = profile.freezeFrequencyWindow;
    pref.preferredCodeType = profile.preferredCodeType;

    pref.target = apply_struct_override(pref.target, profile.target);

    if ~isfield(pref.target, 'userMarginMHz') || ~isfinite(pref.target.userMarginMHz)
        pref.target.userMarginMHz = 0.50;
    end
    profile.effectiveTaskMode = mode;
    profile.initialFoEsMHz = initialFeature.Es.foEsMHz;
    profile.initialDfMHz = initialCfg.dfMHz;
    profile.initialScanTimeSec = estimate_strategy_scan_time(initialCfg);
    pref.taskProfile = profile;
end

function mode = canonical_es_task_mode(mode)
    mode = lower(char(string(mode)));
    mode = strrep(mode, '-', '_');
    mode = strrep(mode, ' ', '_');
    switch mode
        case {'fast','fast_detection','fast_es_detection','alarm','quick'}
            mode = 'fast_detection';
        case {'foes','foes_read','foes_narrow','foes_precision','foes_oriented','foes_boundary'}
            mode = 'foes_read';
        case {'hes','hes_stable','height','height_stable','height_stable_es'}
            mode = 'height_stable';
        case {'weak','weakes','weak_es','weak_visibility','weak_es_visibility'}
            mode = 'weak_es_visibility';
        case {'morphology','full_trace','trace','shape','complete_es'}
            mode = 'full_trace';
        case {'balanced','balance','pareto','default'}
            mode = 'balanced';
        otherwise
            error('Unknown Es taskMode: %s', mode);
    end
end

function profile = make_es_task_profile(mode)
    profile = struct();
    profile.name = mode;
    profile.freezeFrequencyWindow = true;
    profile.preferredCodeType = 'none';
    profile.target = struct();
    profile.baseline = struct();

    switch mode
        case 'fast_detection'
            profile.displayName = 'Fast Es Detection';
            profile.description = '快速监测 Es 是否出现，优先压缩扫描时间，并保留最低可用覆盖和增益。';
            profile.objectiveMode = 'fast';
            profile.selectionMode = 'fast';
            profile.targetMode = 'foEs_compact';
            profile.maxPreferredScanTimeSec = 0.55;
            profile.maxAdaptiveScanTimeSec = 1.20;
            profile.maxPreferredDfMHz = 0.40;
            profile.maxPreferredHeightResolutionKm = 4.5;
            profile.minPreferredNcoh = 4;
            profile.minIntegrationGainDb = 13.5;
            profile.minFrequencySamples = 5;
            profile.referenceDfMHz = 0.22;
            profile.referenceHeightResolutionKm = 3.5;
            profile.preferredCodeType = 'barker';
            profile.baseline = struct('maxScanTimeSec', 1.20, 'scanTimeRatioToInitial', 0.35, ...
                'minFrequencySamples', 5, 'minIntegrationGainDb', 13.5, ...
                'minObservabilityScore', 0.55, 'maxDfMHz', 0.40);
            profile.target.iriPriorStartFlexMHz = 0.20;
            profile.target.iriPriorEndFlexMHz = 0.20;

        case 'foes_read'
            profile.displayName = 'foEs-oriented Narrow Scan';
            profile.description = '围绕初探 foEs 边界窄扫，优先提高频率分辨率和 foEs 读取精度。';
            profile.objectiveMode = 'foes';
            profile.selectionMode = 'foes';
            profile.targetMode = 'foEs_boundary';
            profile.freezeFrequencyWindow = true;
            profile.maxPreferredScanTimeSec = 1.50;
            profile.maxAdaptiveScanTimeSec = 2.60;
            profile.maxPreferredDfMHz = 0.12;
            profile.maxPreferredHeightResolutionKm = 4.0;
            profile.minPreferredNcoh = 6;
            profile.minIntegrationGainDb = 15.0;
            profile.minFrequencySamples = 8;
            profile.referenceDfMHz = 0.05;
            profile.referenceHeightResolutionKm = 3.5;
            profile.baseline = struct('maxScanTimeSec', 2.60, 'scanTimeRatioToInitial', 0.60, ...
                'minFrequencySamples', 8, 'minIntegrationGainDb', 15.0, ...
                'minObservabilityScore', 0.58, 'maxDfMHz', 0.12);
            profile.target.iriPriorStartFlexMHz = 0.00;
            profile.target.iriPriorEndFlexMHz = 0.00;

        case 'height_stable'
            profile.displayName = 'Height-stable Es Mode';
            profile.description = '关注 h''Es 虚高稳定读取，优先高度分辨率、适度积累和稳定回波。';
            profile.objectiveMode = 'height';
            profile.selectionMode = 'height';
            profile.targetMode = 'iri_to_foEs';
            profile.maxPreferredScanTimeSec = 2.40;
            profile.maxAdaptiveScanTimeSec = 4.00;
            profile.maxPreferredDfMHz = 0.25;
            profile.maxPreferredHeightResolutionKm = 2.3;
            profile.minPreferredNcoh = 8;
            profile.minIntegrationGainDb = 17.0;
            profile.minFrequencySamples = 9;
            profile.referenceDfMHz = 0.16;
            profile.referenceHeightResolutionKm = 1.6;
            profile.baseline = struct('maxScanTimeSec', 4.00, 'scanTimeRatioToInitial', 0.80, ...
                'minFrequencySamples', 9, 'minIntegrationGainDb', 17.0, ...
                'minObservabilityScore', 0.62, 'maxDfMHz', 0.25, ...
                'maxHeightResolutionKm', 2.3);

        case 'weak_es_visibility'
            profile.displayName = 'Weak Es Visibility Mode';
            profile.description = '弱 Es 可观测增强，优先积累增益、编码增益和可观测性，允许较长扫描时间。';
            profile.objectiveMode = 'weak';
            profile.selectionMode = 'weak';
            profile.targetMode = 'iri_to_foEs';
            profile.maxPreferredScanTimeSec = 3.60;
            profile.maxAdaptiveScanTimeSec = 5.50;
            profile.maxPreferredDfMHz = 0.22;
            profile.maxPreferredHeightResolutionKm = 3.2;
            profile.minPreferredNcoh = 14;
            profile.minIntegrationGainDb = 21.0;
            profile.minFrequencySamples = 10;
            profile.referenceDfMHz = 0.14;
            profile.referenceHeightResolutionKm = 2.4;
            profile.preferredCodeType = 'complementary';
            profile.baseline = struct('maxScanTimeSec', 5.50, 'scanTimeRatioToInitial', 0.90, ...
                'minFrequencySamples', 10, 'minIntegrationGainDb', 21.0, ...
                'minObservabilityScore', 0.72, 'maxDfMHz', 0.22);

        case 'full_trace'
            profile.displayName = 'Complete Es Trace Mode';
            profile.description = '研究 Es 完整形态，优先扫频上下文、轨迹连续性和可观测性。';
            profile.objectiveMode = 'full_trace';
            profile.selectionMode = 'full_trace';
            profile.targetMode = 'iri_to_foEs';
            profile.maxPreferredScanTimeSec = 4.20;
            profile.maxAdaptiveScanTimeSec = 6.00;
            profile.maxPreferredDfMHz = 0.20;
            profile.maxPreferredHeightResolutionKm = 3.0;
            profile.minPreferredNcoh = 10;
            profile.minIntegrationGainDb = 18.5;
            profile.minFrequencySamples = 14;
            profile.referenceDfMHz = 0.12;
            profile.referenceHeightResolutionKm = 2.0;
            profile.baseline = struct('maxScanTimeSec', 6.00, 'scanTimeRatioToInitial', 0.90, ...
                'minFrequencySamples', 14, 'minIntegrationGainDb', 18.5, ...
                'minObservabilityScore', 0.65, 'maxDfMHz', 0.20, ...
                'maxHeightResolutionKm', 3.0);
            profile.target.iriPriorStartFlexMHz = 0.50;
            profile.target.iriPriorEndFlexMHz = 0.70;

        otherwise
            profile.displayName = 'Balanced Pareto Mode';
            profile.description = '综合平衡扫描时间、分辨率和 Es 可观测性，输出任务约束下的 Pareto 折中点。';
            profile.objectiveMode = 'balanced';
            profile.selectionMode = 'balanced';
            profile.targetMode = 'iri_to_foEs';
            profile.maxPreferredScanTimeSec = 1.2;
            profile.maxAdaptiveScanTimeSec = 3.0;
            profile.maxPreferredDfMHz = 0.28;
            profile.maxPreferredHeightResolutionKm = 3.1;
            profile.minPreferredNcoh = 4;
            profile.minIntegrationGainDb = 18.0;
            profile.minFrequencySamples = 10;
            profile.referenceDfMHz = 0.10;
            profile.referenceHeightResolutionKm = 2.0;
            profile.baseline = struct('maxScanTimeSec', 3.00, 'scanTimeRatioToInitial', 0.70, ...
                'minFrequencySamples', 10, 'minIntegrationGainDb', 18.0, ...
                'minObservabilityScore', 0.60, 'maxDfMHz', 0.28, ...
                'maxHeightResolutionKm', 3.1);
            profile.target.iriPriorStartFlexMHz = 0.45;
            profile.target.iriPriorEndFlexMHz = 0.55;
    end
end

function [candidateTable, info] = run_constrained_nsga2_es(initialCfg, targetRegion, pref)
    opt = pref.nsga2;
    oldState = rng;
    cleanup = onCleanup(@() rng(oldState)); %#ok<NASGU>
    rng(opt.seed, 'twister');

    nVar = 7;
    popSize = opt.populationSize;
    if mod(popSize, 2) ~= 0
        popSize = popSize + 1;
    end

    pop = initialize_nsga2_population(popSize, initialCfg, targetRegion, pref);
    allRows = {};
    evaluationCount = 0;

    for gen = 1:opt.nGenerations
        eval = evaluate_nsga2_population(pop, initialCfg, targetRegion, pref, gen);
        evaluationCount = evaluationCount + size(pop,1);
        allRows = append_nsga2_rows(allRows, eval);

        [rank, crowd] = constrained_nsga2_rank(eval.objectives, eval.constraintViolation);
        offspring = zeros(popSize, nVar);
        for i = 1:2:popSize
            p1 = tournament_select_nsga2(rank, crowd, eval.constraintViolation);
            p2 = tournament_select_nsga2(rank, crowd, eval.constraintViolation);
            [c1, c2] = crossover_mutate_nsga2(pop(p1,:), pop(p2,:), pref, targetRegion, opt);
            offspring(i,:) = c1;
            offspring(i+1,:) = c2;
        end

        combined = [pop; offspring];
        combinedEval = evaluate_nsga2_population(combined, initialCfg, targetRegion, pref, gen);
        [combinedRank, combinedCrowd] = constrained_nsga2_rank(combinedEval.objectives, combinedEval.constraintViolation);
        pop = select_next_nsga2_population(combined, combinedRank, combinedCrowd, combinedEval.constraintViolation, popSize);
    end

    finalEval = evaluate_nsga2_population(pop, initialCfg, targetRegion, pref, opt.nGenerations + 1);
    evaluationCount = evaluationCount + size(pop,1);
    allRows = append_nsga2_rows(allRows, finalEval);

    candidateTable = es_candidate_table_from_rows(allRows);
    candidateTable = unique(candidateTable, 'rows', 'stable');
    info = struct();
    info.method = 'constrained NSGA-II';
    info.populationSize = popSize;
    info.nGenerations = opt.nGenerations;
    info.crossoverProbability = opt.crossoverProbability;
    info.mutationProbability = opt.mutationProbability;
    info.seed = opt.seed;
    info.initialization = 'IRI-informed seeds + boundary strategies + Latin hypercube space-filling samples';
    info.evaluationCount = evaluationCount;
end

function rows = append_nsga2_rows(rows, eval)
    for i = 1:numel(eval.cfg)
        rows(end+1,:) = es_candidate_row(eval.cfg(i), eval.metric(i), eval.cost(i), eval.breakdown(i), eval.cons(i), eval.rank(i), eval.crowding(i), eval.constraintViolation(i), eval.generation(i)); %#ok<AGROW>
    end
end

function row = es_candidate_row(cfg, metric, cost, breakdown, cons, nsgaRank, crowdingDistance, constraintViolation, generation)
    row = {cfg.codeType, cfg.codeLength, cfg.Ncoh, cfg.fStartMHz, cfg.fEndMHz, cfg.dfMHz, cfg.PRP, cfg.chipLength, ...
        metric.scanTimeSec, metric.heightResolutionKm, metric.resolutionCost, metric.EsCoverage, ...
        metric.integrationGainDb, metric.observabilityScore, metric.complexityCost, metric.nFreq, cost, breakdown.utility, breakdown.penalty, ...
        cons.feasible, cons.optimizationFeasible, nsgaRank, crowdingDistance, constraintViolation, generation};
end

function T = es_candidate_table_from_rows(rows)
    T = cell2table(rows, 'VariableNames', {'codeType','codeLength','Ncoh','fStartMHz','fEndMHz','dfMHz','PRP','chipLength','scanTimeSec','heightResolutionKm','resolutionCost','EsCoverage','integrationGainDb','observabilityScore','complexityCost','nFreq','cost','utility','penalty','feasible','optimizationFeasible','nsgaRank','crowdingDistance','constraintViolation','generation'});
end

function pop = initialize_nsga2_population(popSize, initialCfg, target, pref)
    nVar = 7;
    b = nsga2_bounds(target, pref);
    pop = zeros(popSize, nVar);

    seedX = cfg_to_nsga2_x(initialCfg, target, pref);
    reqLow = target.iriPriorRangeMHz(1);
    reqHigh = target.iriPriorRangeMHz(2);
    lowNcoh = pref.NcohIntegerRange(1);
    midNcoh = min(max(16, pref.NcohIntegerRange(1)), pref.NcohIntegerRange(2));
    weakNcoh = min(max(28, pref.NcohIntegerRange(1)), pref.NcohIntegerRange(2));
    highNcoh = min(max(32, pref.NcohIntegerRange(1)), pref.NcohIntegerRange(2));
    nCode = numel(pref.codeLengthSet);

    seedRows = [
        seedX;
        reqLow, reqHigh, min(0.25, b.hi(3)), 8e-3, min(20e-6, b.hi(5)), lowNcoh, 1;
        reqLow, reqHigh, min(0.16, b.hi(3)), 8e-3, min(14e-6, b.hi(5)), max(lowNcoh, 6), 1;
        reqLow, reqHigh, min(0.10, b.hi(3)), max(10e-3, b.lo(4)), b.lo(5), max(lowNcoh, 10), 1;
        reqLow, reqHigh, min(0.05, b.hi(3)), 8e-3, min(10e-6, b.hi(5)), max(lowNcoh, 10), 1;
        reqLow, reqHigh, min(0.05, b.hi(3)), 8e-3, min(12e-6, b.hi(5)), weakNcoh, 1;
        b.hi(1), b.lo(2), b.hi(3), b.lo(4), b.hi(5), lowNcoh, 1;                 % fastest practical edge
        b.lo(1), b.hi(2), b.lo(3), b.hi(4), b.lo(5), highNcoh, 1;                % precision edge
        b.lo(1), b.hi(2), min(0.08, b.hi(3)), b.hi(4), b.lo(5), highNcoh, nCode; % height-stable edge
        b.lo(1), b.hi(2), min(0.20, b.hi(3)), b.hi(4), min(28e-6, b.hi(5)), highNcoh, nCode;
        b.hi(1), b.hi(2), min(0.28, b.hi(3)), 8e-3, min(16e-6, b.hi(5)), midNcoh, 1;
        b.lo(1), b.lo(2), min(0.28, b.hi(3)), 8e-3, min(16e-6, b.hi(5)), midNcoh, 1
    ];

    nSeed = min(size(seedRows,1), popSize);
    pop(1:nSeed,:) = seedRows(1:nSeed,:);

    nFill = popSize - nSeed;
    if nFill > 0
        U = latin_hypercube_unit(nFill, nVar);
        pop(nSeed+1:end,:) = b.lo + U.*(b.hi - b.lo);
    end

    for i = 1:popSize
        pop(i,:) = repair_nsga2_x(pop(i,:), target, pref);
    end
end

function U = latin_hypercube_unit(n, d)
    U = zeros(n,d);
    if n <= 0
        return;
    end
    for j = 1:d
        U(:,j) = ((0:n-1)' + rand(n,1)) / n;
        U(:,j) = U(randperm(n), j);
    end
end

function b = nsga2_bounds(target, pref)
    reqLow = target.requiredRangeMHz(1);
    reqHigh = target.requiredRangeMHz(2);
    pb = pref.bounds;
    b.lo = [reqLow, reqHigh, pb.dfMHz(1), pb.PRP(1), pb.chipLength(1), pref.NcohIntegerRange(1), 1];
    b.hi = [reqLow, reqHigh, pb.dfMHz(2), pb.PRP(2), pb.chipLength(2), pref.NcohIntegerRange(2), numel(pref.codeLengthSet)];
end

function x = cfg_to_nsga2_x(cfg, target, pref)
    codeIdx = find(strcmpi(cfg.codeType, pref.codeTypeSet) & cfg.codeLength == pref.codeLengthSet, 1);
    if isempty(codeIdx), codeIdx = 1; end
    x = [target.requiredRangeMHz(1), target.requiredRangeMHz(2), cfg.dfMHz, cfg.PRP, cfg.chipLength, cfg.Ncoh, codeIdx];
    x = repair_nsga2_x(x, target, pref);
end

function x = repair_nsga2_x(x, target, pref)
    b = nsga2_bounds(target, pref);
    x = min(max(x, b.lo), b.hi);
    x(1) = target.requiredRangeMHz(1);
    x(2) = target.requiredRangeMHz(2);
    x(6) = round((round(x(6)) - pref.NcohIntegerRange(1)) / pref.NcohSearchStep) * pref.NcohSearchStep + pref.NcohIntegerRange(1);
    x(6) = min(max(x(6), pref.NcohIntegerRange(1)), pref.NcohIntegerRange(2));
    x(7) = min(max(round(x(7)), 1), numel(pref.codeLengthSet));
    x(1) = target.requiredRangeMHz(1);
    x(2) = target.requiredRangeMHz(2);
end

function eval = evaluate_nsga2_population(pop, baseCfg, target, pref, generation)
    n = size(pop,1);
    cfg(1,n) = baseCfg;
    metric = struct();
    cons = struct();
    breakdown = struct();
    objectives = [];
    cost = zeros(n,1);
    violation = zeros(n,1);
    for i = 1:n
        cfg(i) = nsga2_x_to_cfg(pop(i,:), baseCfg, target, pref);
        [cost(i), metricI, consI, breakdownI] = es_strategy_cost(cfg(i), target, pref);
        if i == 1
            metric = metricI;
            cons = consI;
            breakdown = breakdownI;
        else
            metric(i) = metricI; %#ok<AGROW>
            cons(i) = consI; %#ok<AGROW>
            breakdown(i) = breakdownI; %#ok<AGROW>
        end
        objectives(i,:) = task_objective_vector(metric(i), cfg(i), pref); %#ok<AGROW>
        violation(i) = es_constraint_violation(cfg(i), metric(i), cons(i), target, pref);
    end
    [rank, crowd] = constrained_nsga2_rank(objectives, violation);
    eval = struct();
    eval.cfg = cfg;
    eval.metric = metric;
    eval.cons = cons;
    eval.breakdown = breakdown;
    eval.objectives = objectives;
    eval.cost = cost;
    eval.constraintViolation = violation;
    eval.rank = rank;
    eval.crowding = crowd;
    eval.generation = repmat(generation, n, 1);
end

function obj = task_objective_vector(metric, cfg, pref)
    switch get_opt(pref, 'objectiveMode', 'balanced')
        case 'fast'
            obj = [metric.scanTimeSec, -metric.observabilityScore, metric.complexityCost];
        case 'foes'
            obj = [cfg.dfMHz, metric.scanTimeSec, -metric.integrationGainDb];
        case 'height'
            obj = [metric.heightResolutionKm, -metric.integrationGainDb, metric.scanTimeSec];
        case 'weak'
            obj = [-metric.observabilityScore, -metric.integrationGainDb, metric.scanTimeSec];
        case 'full_trace'
            obj = [cfg.dfMHz, metric.resolutionCost, -metric.observabilityScore, metric.scanTimeSec];
        otherwise
            obj = [metric.scanTimeSec, metric.resolutionCost, -metric.observabilityScore];
    end
end

function cfg = nsga2_x_to_cfg(x, baseCfg, target, pref)
    x = repair_nsga2_x(x, target, pref);
    cfg = baseCfg;
    codeIdx = min(max(round(x(7)), 1), numel(pref.codeLengthSet));
    cfg.codeType = pref.codeTypeSet{codeIdx};
    cfg.codeLength = pref.codeLengthSet(codeIdx);
    cfg.fStartMHz = x(1);
    cfg.fEndMHz = x(2);
    cfg.dfMHz = x(3);
    cfg.PRP = x(4);
    cfg.chipLength = x(5);
    cfg.Ncoh = round(x(6));
    cfg = refresh_strategy(cfg);
end

function v = es_constraint_violation(cfg, metric, cons, target, pref)
    v = 0;
    v = v + max(0, cfg.fStartMHz - target.requiredRangeMHz(1)) + max(0, target.requiredRangeMHz(2) - cfg.fEndMHz);
    v = v + max(0, (pref.maxHeightKm + pref.heightMarginKm - metric.hAmbKm) / 100);
    v = v + max(0, metric.scanTimeSec - pref.maxScanTimeSec) / pref.maxScanTimeSec;
    v = v + max(0, metric.scanTimeSec - pref.maxPreferredScanTimeSec) / pref.maxPreferredScanTimeSec;
    v = v + max(0, metric.scanTimeSec - pref.maxAdaptiveScanTimeSec) / pref.maxAdaptiveScanTimeSec;
    v = v + max(0, cfg.dfMHz - pref.maxPreferredDfMHz) / pref.maxPreferredDfMHz;
    v = v + max(0, metric.dutyRatio - pref.maxDutyRatio) / pref.maxDutyRatio;
    v = v + max(0, metric.heightResolutionKm - pref.maxPreferredHeightResolutionKm) / pref.maxPreferredHeightResolutionKm;
    v = v + max(0, pref.minPreferredNcoh - cfg.Ncoh) / max(pref.minPreferredNcoh, 1);
    v = v + max(0, pref.minIntegrationGainDb - metric.integrationGainDb) / max(pref.minIntegrationGainDb, eps);
    v = v + max(0, pref.minFrequencySamples - metric.nFreq) / pref.minFrequencySamples;
    v = v + task_baseline_violation(metric, cfg, pref);
    if ~cons.pulseFits, v = v + 1; end
    if ~cons.codeLengthOK, v = v + 1; end
end

function [v, status] = task_baseline_violation(metric, cfg, pref)
    v = 0;
    status = struct();
    if ~isfield(pref, 'taskProfile') || ~isfield(pref.taskProfile, 'baseline')
        status.ok = true;
        return;
    end
    b = pref.taskProfile.baseline;
    if isfield(b, 'maxScanTimeSec')
        d = max(0, metric.scanTimeSec - b.maxScanTimeSec) / max(b.maxScanTimeSec, eps);
        v = v + d;
        status.maxScanTimeOK = d <= 1e-12;
    end
    if isfield(b, 'scanTimeRatioToInitial') && isfield(pref.taskProfile, 'initialScanTimeSec') && isfinite(pref.taskProfile.initialScanTimeSec)
        limit = b.scanTimeRatioToInitial * pref.taskProfile.initialScanTimeSec;
        d = max(0, metric.scanTimeSec - limit) / max(limit, eps);
        v = v + d;
        status.scanTimeRatioOK = d <= 1e-12;
        status.scanTimeRatioLimitSec = limit;
    end
    if isfield(b, 'minFrequencySamples')
        d = max(0, b.minFrequencySamples - metric.nFreq) / max(b.minFrequencySamples, eps);
        v = v + d;
        status.minFrequencySamplesOK = d <= 1e-12;
    end
    if isfield(b, 'minIntegrationGainDb')
        d = max(0, b.minIntegrationGainDb - metric.integrationGainDb) / max(abs(b.minIntegrationGainDb), eps);
        v = v + d;
        status.minIntegrationGainOK = d <= 1e-12;
    end
    if isfield(b, 'minObservabilityScore')
        d = max(0, b.minObservabilityScore - metric.observabilityScore);
        v = v + d;
        status.minObservabilityOK = d <= 1e-12;
    end
    if isfield(b, 'maxDfMHz')
        d = max(0, cfg.dfMHz - b.maxDfMHz) / max(b.maxDfMHz, eps);
        v = v + d;
        status.maxDfOK = d <= 1e-12;
    end
    if isfield(b, 'maxHeightResolutionKm')
        d = max(0, metric.heightResolutionKm - b.maxHeightResolutionKm) / max(b.maxHeightResolutionKm, eps);
        v = v + d;
        status.maxHeightResolutionOK = d <= 1e-12;
    end
    status.violation = v;
    status.ok = v <= 1e-12;
end

function [rank, crowd] = constrained_nsga2_rank(objectives, violation)
    n = size(objectives,1);
    dominates = false(n,n);
    dominatedCount = zeros(n,1);
    fronts = cell(n,1);
    rank = inf(n,1);
    for p = 1:n
        for q = 1:n
            if p == q, continue; end
            if constrained_dominates(objectives(p,:), violation(p), objectives(q,:), violation(q))
                dominates(p,q) = true;
            elseif constrained_dominates(objectives(q,:), violation(q), objectives(p,:), violation(p))
                dominatedCount(p) = dominatedCount(p) + 1;
            end
        end
        if dominatedCount(p) == 0
            rank(p) = 1;
            fronts{1}(end+1) = p; %#ok<AGROW>
        end
    end

    f = 1;
    while f <= n && ~isempty(fronts{f})
        nextFront = [];
        for p = fronts{f}
            qList = find(dominates(p,:));
            for q = qList
                dominatedCount(q) = dominatedCount(q) - 1;
                if dominatedCount(q) == 0
                    rank(q) = f + 1;
                    nextFront(end+1) = q; %#ok<AGROW>
                end
            end
        end
        f = f + 1;
        if f <= n
            fronts{f} = nextFront;
        end
    end

    crowd = zeros(n,1);
    validFronts = unique(rank(isfinite(rank)))';
    for f = validFronts
        idx = find(rank == f);
        crowd(idx) = crowding_distance(objectives(idx,:));
    end
end

function tf = constrained_dominates(aObj, aViol, bObj, bViol)
    tol = 1e-12;
    if aViol <= tol && bViol > tol
        tf = true;
    elseif aViol > tol && bViol <= tol
        tf = false;
    elseif aViol > tol && bViol > tol
        tf = aViol < bViol;
    else
        tf = all(aObj <= bObj + tol) && any(aObj < bObj - tol);
    end
end

function d = crowding_distance(vals)
    n = size(vals,1);
    m = size(vals,2);
    d = zeros(n,1);
    if n <= 2
        d(:) = Inf;
        return;
    end
    for j = 1:m
        [sorted, order] = sort(vals(:,j), 'ascend');
        d(order(1)) = Inf;
        d(order(end)) = Inf;
        span = max(sorted(end) - sorted(1), eps);
        for k = 2:n-1
            d(order(k)) = d(order(k)) + (sorted(k+1) - sorted(k-1)) / span;
        end
    end
end

function idx = tournament_select_nsga2(rank, crowd, violation)
    n = numel(rank);
    a = randi(n);
    b = randi(n);
    if violation(a) < violation(b) - 1e-12
        idx = a;
    elseif violation(b) < violation(a) - 1e-12
        idx = b;
    elseif rank(a) < rank(b)
        idx = a;
    elseif rank(b) < rank(a)
        idx = b;
    elseif crowd(a) >= crowd(b)
        idx = a;
    else
        idx = b;
    end
end

function [c1, c2] = crossover_mutate_nsga2(p1, p2, pref, target, opt)
    b = nsga2_bounds(target, pref);
    if rand < opt.crossoverProbability
        alpha = rand(size(p1));
        c1 = alpha.*p1 + (1-alpha).*p2;
        c2 = alpha.*p2 + (1-alpha).*p1;
    else
        c1 = p1;
        c2 = p2;
    end
    c1 = mutate_nsga2_x(c1, b, opt.mutationProbability);
    c2 = mutate_nsga2_x(c2, b, opt.mutationProbability);
    c1 = repair_nsga2_x(c1, target, pref);
    c2 = repair_nsga2_x(c2, target, pref);
end

function x = mutate_nsga2_x(x, b, pMut)
    scale = [0.25, 0.25, 0.18, 0.12, 0.12, 0.22, 0.50];
    for j = 1:numel(x)
        if rand < pMut
            sigma = scale(j) * (b.hi(j) - b.lo(j));
            x(j) = x(j) + sigma*randn();
        end
    end
    x = min(max(x, b.lo), b.hi);
end

function nextPop = select_next_nsga2_population(pop, rank, crowd, violation, popSize)
    n = size(pop,1);
    order = (1:n)';
    [~, sortIdx] = sortrows([rank(:), violation(:), -crowd(:), order], [1 2 3 4]);
    nextPop = pop(sortIdx(1:popSize), :);
end

function severity = compute_es_severity(sceneSpec, feature, pref)
    severity = struct();
    if sceneSpec.Es.enabled && isfinite(feature.Es.foEsMHz)
        x0 = pref.softThreshold.foEsMHz.x0;
        tau = pref.softThreshold.foEsMHz.tau;
        severity.Es = sigmoid_soft(feature.Es.foEsMHz, x0, tau);
    else
        severity.Es = 0.5;
    end
end

function target = build_es_target_region(initialCfg, feature, pref)
    target = struct();
    bgFoE = NaN;
    if isfield(feature.Es, 'foEBackgroundMHz')
        bgFoE = feature.Es.foEBackgroundMHz;
    end
    foEObs = observed_foe_from_feature(feature, bgFoE, initialCfg.dfMHz, pref.target.userMarginMHz);
    hasFoEs = isfield(feature.Es, 'observable') && feature.Es.observable && isfinite(feature.Es.foEsMHz);
    hasBg = isfinite(bgFoE);
    hasFoEObs = isfinite(foEObs);
    targetMode = get_opt(pref, 'targetMode', 'iri_to_foEs');
    if hasFoEs && strcmpi(targetMode, 'foEs_boundary')
        [fStart, fEnd, pointTable] = build_ranked_boundary_window(initialCfg, ...
            {'foEs_obs'}, [feature.Es.foEsMHz], {'observed'}, pref.target.userMarginMHz);
        target.priorType = 'task-driven foEs boundary narrow window';
    elseif hasFoEs && strcmpi(targetMode, 'foEs_compact')
        [fStart, fEnd, pointTable] = build_ranked_boundary_window(initialCfg, ...
            {'foE_IRI','foEs_obs'}, [bgFoE, feature.Es.foEsMHz], {'iri','observed'}, pref.target.userMarginMHz);
        target.priorType = 'task-driven compact foEs detection window';
    elseif hasFoEs || hasBg || hasFoEObs
        [fStart, fEnd, pointTable] = build_e_es_ranked_boundary_window(initialCfg, feature, bgFoE, foEObs, pref.target.userMarginMHz);
        target.priorType = 'ranked-boundary E-to-Es window without ordering assumption';
    elseif hasFoEs
        [fStart, fEnd, pointTable] = build_ranked_boundary_window(initialCfg, ...
            {'foEs_obs'}, [feature.Es.foEsMHz], {'observed'}, pref.target.userMarginMHz);
        target.priorType = 'foEs-only fallback window';
    else
        fStart = initialCfg.fStartMHz;
        fEnd = initialCfg.fEndMHz;
        pointTable = table();
        target.priorType = 'wide fallback window';
    end
    target.requiredRangeMHz = [fStart, fEnd];
    target.iriPriorRangeMHz = [fStart, fEnd];
    target.taskMode = pref.taskMode;
    target.taskDisplayName = pref.taskProfile.displayName;
    target.freezeFrequencyWindow = pref.freezeFrequencyWindow;
    target.hasIriPrior = hasFoEs && hasBg;
    target.foEsObservedMHz = feature.Es.foEsMHz;
    target.foEBackgroundMHz = bgFoE;
    target.foEObservedMHz = foEObs;
    target.esExcessOverBgMHz = feature.Es.foEsMHz - bgFoE;
    target.userMarginMHz = pref.target.userMarginMHz;
    target.dfCoarseMHz = initialCfg.dfMHz;
    target.frequencyBoundaryPointTable = pointTable;
    target.reason = pref.taskProfile.description;
end

function foEObs = observed_foe_from_feature(feature, foEIri, dfCoarseMHz, userMarginMHz)
    foEObs = NaN;
    if ~isfield(feature, 'E') || ~isfield(feature.E, 'activeMidFreqMHz')
        return;
    end
    f = feature.E.activeMidFreqMHz(:);
    if isempty(f)
        return;
    end
    if isfinite(foEIri)
        searchHalfWidth = max(dfCoarseMHz, userMarginMHz);
        f = f(f >= foEIri - searchHalfWidth & f <= foEIri + searchHalfWidth);
    end
    if isempty(f)
        return;
    end
    foEObs = max(f);
end

function [fStart, fEnd, pointTable] = build_e_es_ranked_boundary_window(initialCfg, feature, foEIri, foEObs, userMarginMHz)
    names = {'foE_IRI','foE_obs','foEs_obs'};
    values = [foEIri, foEObs, feature.Es.foEsMHz];
    sources = {'iri','observed','observed'};
    [fStart, fEnd, pointTable] = build_ranked_boundary_window(initialCfg, names, values, sources, userMarginMHz);
end

function [fStart, fEnd, pointTable] = build_ranked_boundary_window(initialCfg, namesIn, values, sourcesIn, userMarginMHz)
    names = {};
    centers = [];
    sources = {};
    expansion = [];
    for i = 1:numel(values)
        if isfinite(values(i))
            names{end+1,1} = namesIn{i}; %#ok<AGROW>
            centers(end+1,1) = values(i); %#ok<AGROW>
            sources{end+1,1} = sourcesIn{i}; %#ok<AGROW>
            expansion(end+1,1) = frequency_source_expansion(sourcesIn{i}, initialCfg.dfMHz, userMarginMHz); %#ok<AGROW>
        end
    end
    if isempty(centers)
        fStart = initialCfg.fStartMHz;
        fEnd = initialCfg.fEndMHz;
        pointTable = table();
        return;
    end
    [minFreq, minIdx] = min(centers);
    [maxFreq, maxIdx] = max(centers);
    fStart = max(initialCfg.fStartMHz, minFreq - expansion(minIdx));
    fEnd = min(initialCfg.fEndMHz, maxFreq + expansion(maxIdx));
    isLowerBoundary = false(numel(centers),1);
    isUpperBoundary = false(numel(centers),1);
    isLowerBoundary(minIdx) = true;
    isUpperBoundary(maxIdx) = true;
    pointTable = table(string(names), centers, string(sources), expansion, isLowerBoundary, isUpperBoundary, ...
        'VariableNames', {'name','frequencyMHz','sourceType','boundaryExpansionMHz','isLowerBoundary','isUpperBoundary'});
end

function expansionMHz = frequency_source_expansion(sourceType, dfCoarseMHz, userMarginMHz)
    switch lower(char(string(sourceType)))
        case 'iri'
            expansionMHz = userMarginMHz;
        case 'observed'
            expansionMHz = dfCoarseMHz;
        otherwise
            error('Unknown frequency source type: %s', sourceType);
    end
end

function [cost, metric, cons, breakdown] = es_strategy_cost(cfg, target, pref)
    c0 = 299792458;
    nFreq = max(1, floor((cfg.fEndMHz - cfg.fStartMHz)/cfg.dfMHz) + 1);
    if is_complementary_mode(cfg)
        pulsesPerFreq = 2*cfg.Ncoh;
    else
        pulsesPerFreq = cfg.Ncoh;
    end
    scanTime = nFreq*pulsesPerFreq*cfg.PRP;
    heightResKm = c0*cfg.chipLength/2/1e3;
    hAmbKm = c0*cfg.PRP/2/1e3;
    pulseWidth = cfg.codeLength*cfg.chipLength;
    duty = pulseWidth/cfg.PRP;

    targetLow = target.requiredRangeMHz(1);
    targetHigh = target.requiredRangeMHz(2);
    targetWidth = max(targetHigh - targetLow, cfg.dfMHz);
    overlapWidth = max(0, min(cfg.fEndMHz, targetHigh) - max(cfg.fStartMHz, targetLow));
    EsCoverage = min(1, overlapWidth / targetWidth);
    integrationGainDb = 10*log10(max(cfg.Ncoh,1)) + 10*log10(max(cfg.codeLength,1));
    if is_complementary_mode(cfg)
        integrationGainDb = integrationGainDb + 1.5;
    end
    integrationScore = normalize_score(integrationGainDb, pref.minIntegrationGainDb - 6, pref.minIntegrationGainDb + 8);
    observabilityScore = integrationScore;
    resolutionCost = 0.5*(cfg.dfMHz / pref.referenceDfMHz) + ...
        0.5*(heightResKm / pref.referenceHeightResolutionKm);
    complexityCost = 0.15*double(is_complementary_mode(cfg)) + 0.03*(cfg.Ncoh / pref.NcohIntegerRange(2));

    metric = struct();
    metric.EsCoverage = EsCoverage;
    metric.integrationGainDb = integrationGainDb;
    metric.observabilityScore = observabilityScore;
    metric.complexityCost = complexityCost;
    metric.resolutionCost = resolutionCost;
    metric.scanTimeSec = scanTime;
    metric.heightResolutionKm = heightResKm;
    metric.hAmbKm = hAmbKm;
    metric.dutyRatio = duty;
    metric.nFreq = nFreq;

    utility = task_utility_score(metric, cfg, pref);

    penalty = 0;
    cons = struct();
    cons.targetCovered = cfg.fStartMHz <= target.requiredRangeMHz(1) && cfg.fEndMHz >= target.requiredRangeMHz(2);
    if ~cons.targetCovered
        gap = max(0, cfg.fStartMHz - target.requiredRangeMHz(1)) + max(0, target.requiredRangeMHz(2) - cfg.fEndMHz);
        penalty = penalty + 80*gap;
    end
    cons.heightUnambiguous = hAmbKm >= pref.maxHeightKm + pref.heightMarginKm;
    if ~cons.heightUnambiguous
        penalty = penalty + 500*(pref.maxHeightKm + pref.heightMarginKm - hAmbKm)/100;
    end
    cons.pulseFits = pulseWidth + pref.guardTime < cfg.PRP;
    if ~cons.pulseFits
        penalty = penalty + 500*(pulseWidth + pref.guardTime - cfg.PRP)/cfg.PRP;
    end
    cons.scanTimeOK = scanTime <= pref.maxScanTimeSec;
    if ~cons.scanTimeOK
        penalty = penalty + 4*(scanTime - pref.maxScanTimeSec);
    end
    cons.resoundingTimeStable = scanTime <= pref.maxPreferredScanTimeSec;
    if ~cons.resoundingTimeStable
        penalty = penalty + 3.0*(scanTime - pref.maxPreferredScanTimeSec);
    end
    cons.adaptiveScanPractical = scanTime <= pref.maxAdaptiveScanTimeSec;
    if ~cons.adaptiveScanPractical
        penalty = penalty + 5.0*(scanTime - pref.maxAdaptiveScanTimeSec);
    end
    cons.dfStable = cfg.dfMHz <= pref.maxPreferredDfMHz;
    if ~cons.dfStable
        penalty = penalty + 4.0*(cfg.dfMHz - pref.maxPreferredDfMHz)/pref.maxPreferredDfMHz;
    end
    cons.dutyOK = duty <= pref.maxDutyRatio;
    if ~cons.dutyOK
        penalty = penalty + 300*(duty - pref.maxDutyRatio);
    end
    cons.heightResolutionStable = heightResKm <= pref.maxPreferredHeightResolutionKm;
    if ~cons.heightResolutionStable
        penalty = penalty + 1.8*(heightResKm - pref.maxPreferredHeightResolutionKm);
    end
    cons.NcohStable = cfg.Ncoh >= pref.minPreferredNcoh;
    if ~cons.NcohStable
        penalty = penalty + 0.8*(pref.minPreferredNcoh - cfg.Ncoh);
    end
    cons.EsCoverageOK = EsCoverage >= 1 - 1e-9;
    cons.integrationGainOK = integrationGainDb >= pref.minIntegrationGainDb;
    if ~cons.integrationGainOK
        penalty = penalty + 0.2*(pref.minIntegrationGainDb - integrationGainDb);
    end
    cons.frequencySamplesOK = nFreq >= pref.minFrequencySamples;
    if ~cons.frequencySamplesOK
        penalty = penalty + 1.5*(pref.minFrequencySamples - nFreq);
    end
    [baselineViolation, baselineStatus] = task_baseline_violation(metric, cfg, pref);
    cons.baseline = baselineStatus;
    cons.baselineOK = baselineViolation <= 1e-12;
    penalty = penalty + 6.0*baselineViolation;
    cons.codeLengthOK = (strcmpi(cfg.codeType,'barker') && cfg.codeLength==13) || (strcmpi(cfg.codeType,'complementary') && cfg.codeLength==16);
    cons.NcohInteger = abs(cfg.Ncoh-round(cfg.Ncoh)) < 1e-12;
    cons.feasible = cons.targetCovered && cons.heightUnambiguous && cons.pulseFits && cons.scanTimeOK && cons.dutyOK && cons.codeLengthOK && cons.NcohInteger;
    cons.optimizationFeasible = cons.feasible && cons.adaptiveScanPractical && cons.dfStable && cons.EsCoverageOK && cons.integrationGainOK && cons.frequencySamplesOK && cons.heightResolutionStable && cons.NcohStable && cons.baselineOK;

    % Es-only 中互补码低旁瓣不是主导偏好，加入复杂度/时长修正，避免无意义偏向互补码。
    complexityPenalty = complexityCost;
    preferredCode = get_opt(pref, 'preferredCodeType', 'none');
    if strcmpi(preferredCode, 'complementary') && is_complementary_mode(cfg)
        complexityPenalty = max(0, complexityPenalty - 0.12);
    elseif strcmpi(preferredCode, 'barker') && is_complementary_mode(cfg)
        complexityPenalty = complexityPenalty + 0.25;
    end
    penalty = penalty + complexityPenalty;

    cost = -utility + penalty;
    breakdown = struct('utility',utility,'penalty',penalty,'complexityPenalty',complexityPenalty);
end

function utility = task_utility_score(metric, cfg, pref)
    scanNorm = metric.scanTimeSec / max(pref.maxAdaptiveScanTimeSec, eps);
    dfNorm = cfg.dfMHz / max(pref.referenceDfMHz, eps);
    hNorm = metric.heightResolutionKm / max(pref.referenceHeightResolutionKm, eps);
    gainNorm = normalize_score(metric.integrationGainDb, pref.minIntegrationGainDb - 6, pref.minIntegrationGainDb + 8);
    switch get_opt(pref, 'objectiveMode', 'balanced')
        case 'fast'
            utility = 0.45*metric.observabilityScore - 0.55*scanNorm - 0.08*metric.complexityCost - 0.05*dfNorm;
        case 'foes'
            utility = 0.30*gainNorm - 0.60*dfNorm - 0.18*scanNorm;
        case 'height'
            utility = 0.45*metric.observabilityScore + 0.30*gainNorm - 0.55*hNorm - 0.12*scanNorm;
        case 'weak'
            utility = 0.55*metric.observabilityScore + 0.45*gainNorm - 0.16*scanNorm - 0.10*dfNorm;
        case 'full_trace'
            utility = 0.35*metric.observabilityScore - 0.26*dfNorm - 0.12*hNorm - 0.12*scanNorm;
        otherwise
            utility = metric.observabilityScore - 0.08*metric.resolutionCost - 0.02*metric.scanTimeSec;
    end
end

function T = build_es_optimizer_reason_table(cfg, severity, target, metric, breakdown, cons)
    item = {'任务模式'; '异常类型'; 'Es严重度'; '优化目标'; 'IRI背景foE'; '目标扫频区域'; '选择码型'; '选择Ncoh'; '编码积累增益'; 'dfMHz'; 'chipLength'; 'PRP'; '扫描时间'; 'Es覆盖率'; '高度不模糊'; '分辨率代价'; '惩罚'};
    explanation = { ...
        sprintf('%s：%s', target.taskDisplayName, target.reason); ...
        'IRI正常背景 + Es异常增量，其他异常类型关闭'; ...
        sprintf('%.3f，由初探foEs通过连续软阈值得到', severity.Es); ...
        task_objective_description(target.taskMode); ...
        sprintf('%.3f MHz', target.foEBackgroundMHz); ...
        sprintf('[%.3f, %.3f] MHz，寻优前由任务模式固定生成；NSGA-II不优化扫频起止频率', target.requiredRangeMHz(1), target.requiredRangeMHz(2)); ...
        sprintf('%s-%d', cfg.codeType, cfg.codeLength); ...
        sprintf('%d，整数取值', cfg.Ncoh); ...
        sprintf('%.2f dB', metric.integrationGainDb); ...
        sprintf('%.4f MHz', cfg.dfMHz); ...
        sprintf('%.2f us，对应高度分辨率 %.2f km', cfg.chipLength*1e6, metric.heightResolutionKm); ...
        sprintf('%.2f ms，对应不模糊高度 %.1f km', cfg.PRP*1e3, metric.hAmbKm); ...
        sprintf('%.3f s', metric.scanTimeSec); ...
        sprintf('%.2f，约束%s', metric.EsCoverage, logical_to_text(cons.EsCoverageOK)); ...
        logical_to_text(cons.heightUnambiguous); ...
        sprintf('%.3f', metric.resolutionCost); ...
        sprintf('%.3f', breakdown.penalty)};
    T = table(item, explanation, 'VariableNames', {'item','explanation'});
end

function text = task_objective_description(taskMode)
    switch taskMode
        case 'fast_detection'
            text = '快速告警：优先最小扫描时间、可观测性和低复杂度，覆盖率仅作固定窗口校验';
        case 'foes_read'
            text = 'foEs精读：围绕foEs边界窄扫，优先最小df、兼顾扫描时间和积累增益';
        case 'height_stable'
            text = 'h''Es稳定：优先高度分辨率、积累增益和适度扫描时间';
        case 'weak_es_visibility'
            text = '弱Es增强：优先可观测性和积累/编码增益，扫描时间上限放宽';
        case 'full_trace'
            text = '完整形态：优先频点充分、分辨率和可观测性，覆盖率仅作固定窗口校验';
        otherwise
            text = '综合平衡：扫描时间、分辨率代价和Es可观测性三个紧凑目标';
    end
end

%% ========================================================================
%%                         Compare and plot
%% ========================================================================

function score = compare_es_feature_with_truth(obs, truth, cfg, sim)
    score = struct();
    score.observable = obs.Es.observable;
    score.foEsErrorMHz = absdiff(obs.Es.foEsMHz, truth.Es.foEsMHz);
    score.hEsPrimeErrorKm = absdiff(obs.Es.hEsPrimeKm, truth.Es.hEsPrimeKm);
    score.frequencyResolutionMHz = cfg.dfMHz;
    score.heightResolutionKm = 299792458 * cfg.chipLength / 2 / 1e3;
    score.foEsUncertaintyMHz = cfg.dfMHz / sqrt(12);
    score.hPrimeUncertaintyKm = score.heightResolutionKm / sqrt(12);
    score.foEsNormalizedError = score.foEsErrorMHz / max(score.foEsUncertaintyMHz, eps);
    score.hEsPrimeNormalizedError = score.hEsPrimeErrorKm / max(score.hPrimeUncertaintyKm, eps);
    score.traceContinuity = obs.Es.traceContinuity;
    score.meanSNR = obs.Es.meanSNR;
    score.traceLengthMHz = obs.Es.traceLengthMHz;
    score.weakEdgeWidthMHz = obs.Es.weakEdgeWidthMHz;
    if isfield(obs.Es, 'hEsPrimeStdKm')
        score.hEsPrimeStdKm = obs.Es.hEsPrimeStdKm;
    else
        score.hEsPrimeStdKm = NaN;
    end
    score.scanTimeSec = sim.scanTimeSec;
    cost = 0;
    if ~obs.Es.observable, cost = cost + 25; end
    cost = cost + 5*nan_penalty(score.foEsNormalizedError, 5);
    cost = cost + 5*nan_penalty(score.hEsPrimeNormalizedError, 5);
    cost = cost + 0.7*nan_penalty(score.hEsPrimeStdKm/max(score.heightResolutionKm, eps), 4);
    cost = cost + 8*max(0, 1 - nan_to_value(score.traceContinuity,0));
    score.totalCost = cost;
    score.preferenceScore = max(0, 100 - cost);
    score.qualityScore = score.preferenceScore;
end

function improvement = compare_initial_optimized_es(truth, initF, optF, scoreI, scoreO)
    rows = {};
    rows = add_row(rows, 'foEsMHz', truth.Es.foEsMHz, initF.Es.foEsMHz, optF.Es.foEsMHz);
    rows = add_row(rows, 'foEBackgroundMHz', truth.Es.foEBackgroundMHz, initF.Es.foEBackgroundMHz, optF.Es.foEBackgroundMHz);
    rows = add_row(rows, 'foEsExcessOverBgMHz', truth.Es.foEsMHz-truth.Es.foEBackgroundMHz, initF.Es.foEsExcessOverBgMHz, optF.Es.foEsExcessOverBgMHz);
    rows = add_row(rows, 'hEsPrimeKm', truth.Es.hEsPrimeKm, initF.Es.hEsPrimeKm, optF.Es.hEsPrimeKm);
    rows = add_row(rows, 'EsTraceContinuity', NaN, initF.Es.traceContinuity, optF.Es.traceContinuity);
    rows = add_row(rows, 'EsMeanSNR', NaN, initF.Es.meanSNR, optF.Es.meanSNR);
    rows = add_row(rows, 'EsTraceLengthMHz', NaN, initF.Es.traceLengthMHz, optF.Es.traceLengthMHz);
    rows = add_row(rows, 'scanTimeSec', NaN, scoreI.scanTimeSec, scoreO.scanTimeSec);
    rows = add_row(rows, 'frequencyResolutionMHz', NaN, scoreI.frequencyResolutionMHz, scoreO.frequencyResolutionMHz);
    rows = add_row(rows, 'heightResolutionKm', NaN, scoreI.heightResolutionKm, scoreO.heightResolutionKm);
    rows = add_row(rows, 'foEsNormalizedError', 0, scoreI.foEsNormalizedError, scoreO.foEsNormalizedError);
    rows = add_row(rows, 'hEsPrimeNormalizedError', 0, scoreI.hEsPrimeNormalizedError, scoreO.hEsPrimeNormalizedError);
    rows = add_row(rows, 'qualityScore', 100, scoreI.qualityScore, scoreO.qualityScore);
    improvement.summaryTable = cell2table(rows, 'VariableNames', {'featureName','truthValue','initialValue','optimizedValue','initialError','optimizedError','improvement'});
    improvement.initialScore = scoreI;
    improvement.optimizedScore = scoreO;
end

function rawComparison = build_raw_comparison(initialSim, optimizedSim)
    rawComparison = struct();
    rawComparison.note = 'Native ionograms are preserved for visual comparison only. No unified-grid interpolation or pixel-level difference is performed.';
    rawComparison.initial.fMHz = initialSim.fMHz;
    rawComparison.initial.hKm = initialSim.hKm;
    rawComparison.initial.ionogram = initialSim.ionogram;
    rawComparison.initial.ionogramDb = initialSim.ionogramDb;
    rawComparison.initial.scanTimeSec = initialSim.scanTimeSec;
    rawComparison.optimized.fMHz = optimizedSim.fMHz;
    rawComparison.optimized.hKm = optimizedSim.hKm;
    rawComparison.optimized.ionogram = optimizedSim.ionogram;
    rawComparison.optimized.ionogramDb = optimizedSim.ionogramDb;
    rawComparison.optimized.scanTimeSec = optimizedSim.scanTimeSec;
end

function modelFlow = build_iri_es_model_flow(scene)
    modelFlow = struct();
    modelFlow.steps = { ...
        'Input geographic location, UTC time, and IRI mode'; ...
        'Generate quiet background NeIRI(h) using IRI2020'; ...
        'Generate localized Es electron-density increment NeEs(x,y,h,t) relative to the IRI background'; ...
        'Compute total density NeTotal = NeIRI + NeEs'; ...
        'Use NeTotal for plasma frequency, reflection height, virtual height, and echoes'; ...
        'Generate initial native-grid ionogram'; ...
        'Preprocess each strategy on its own native grid'; ...
        'Extract Es features and attach IRI background parameters'; ...
        'Optimize strategy for Es observability relative to IRI background'; ...
        'Run optimized resounding'; ...
        'Compare native ionograms visually and scalar features with resolution-aware errors'};
    modelFlow.backgroundModel = scene.iri.mode;
    modelFlow.backgroundInfo = scene.iriBackground.info;
    modelFlow.EsTargetMode = scene.Es.targetMode;
    modelFlow.totalDensityEquation = 'NeTotal(x,y,h,t) = NeIRI(h; lat,lon,time) + NeEsIncrement(x,y,h,t)';
end

function rows = add_row(rows, name, truthVal, initVal, optVal)
    if isfinite(truthVal)
        eI = absdiff(initVal, truthVal);
        eO = absdiff(optVal, truthVal);
        imp = eI - eO;
    else
        eI = NaN;
        eO = NaN;
        imp = optVal - initVal;
    end
    rows(end+1,:) = {name, truthVal, initVal, optVal, eI, eO, imp}; %#ok<AGROW>
end

function [codeA, codeB] = make_phase_code(cfg)
    switch lower(cfg.codeType)
        case {'barker','baker','barker13'}
            codeA = barker_code(cfg.codeLength);
            codeB = [];
        case {'complementary','golay','互补码','complementary16','golay16'}
            [codeA, codeB] = golay_pair(cfg.codeLength);
        otherwise
            error('Unsupported codeType: %s', cfg.codeType);
    end
    codeA = codeA(:);
    codeB = codeB(:);
end

function tf = is_complementary_mode(cfg)
    tf = any(strcmpi(cfg.codeType, {'complementary','golay','互补码'}));
end

function c = barker_code(L)
    if L ~= 13
        error('This Es-only system fixes Barker code length to 13.');
    end
    c = [1 1 1 1 1 -1 -1 1 1 -1 1 -1 1];
end

function [a,b] = golay_pair(N)
    if N ~= 16
        error('This Es-only system fixes complementary code length to 16.');
    end
    a = 1; b = 1;
    while numel(a) < N
        a0 = a; b0 = b;
        a = [a0, b0]; %#ok<AGROW>
        b = [a0,-b0]; %#ok<AGROW>
    end
end

function info = derive_strategy_info(cfg)
    c0 = 299792458;
    [codeA, ~] = make_phase_code(cfg);
    info.codeLength = numel(codeA);
    info.pulseWidthSec = numel(codeA)*cfg.chipLength;
    info.heightResolutionKm = c0*cfg.chipLength/2/1e3;
    info.hAmbKm = c0*cfg.PRP/2/1e3;
    Nrec = max(1, floor(cfg.PRP*cfg.Fs));
    maxDelayByHeight = floor(2*cfg.maxHeightKm*1e3/c0*cfg.Fs)+1;
    info.nDelaySamp = min(maxDelayByHeight, Nrec);
end

function Ne = Ne_from_foMHz(foMHz)
    Ne = (foMHz/8.98e-6).^2;
end

function fp = fpMHz_from_Ne(Ne)
    fp = 8.98e-6*sqrt(max(Ne,0));
end

function Ne = chapman_1d(h, hm, H, Nm)
    zeta = (h-hm)./H;
    Ne = Nm.*exp(0.5*(1-zeta-exp(-zeta)));
end

function Ne = chapman_asym_1d(h, hm, Hbot, Htop, Nm)
    H = Hbot + (Htop-Hbot).*(h>=hm);
    zeta = (h-hm)./H;
    Ne = Nm.*exp(0.5*(1-zeta-exp(-zeta)));
end

function hRef = interp_reflection_height(z, fp, f, idx)
    z1 = z(idx-1); z2 = z(idx);
    f1 = fp(idx-1); f2 = fp(idx);
    if abs(f2-f1) < 1e-12
        hRef = z2;
    else
        hRef = z1 + (f-f1)*(z2-z1)/(f2-f1);
    end
end

function hVirt = virtual_height_km(z, fp, f, idx, hRef)
    zz = [0; z(1:idx-1); hRef];
    ff = [0; fp(1:idx-1); 0.995*f];
    mu_g = 1 ./ sqrt(max(1-(ff./f).^2, 0.018));
    hVirt = trapz(zz, mu_g);
end

function R = corr2d_field(nx, ny, corrKm, dx, dy, seed)
    rng(seed);
    W = randn(nx, ny);
    sigX = max(corrKm/dx/2.355, 1);
    sigY = max(corrKm/dy/2.355, 1);
    kx = ceil(4*sigX); ky = ceil(4*sigY);
    gx = exp(-((-kx:kx).^2)/(2*sigX^2)); gx = gx/sum(gx);
    gy = exp(-((-ky:ky).^2)/(2*sigY^2)); gy = gy/sum(gy);
    R = conv2(conv2(W,gx(:),'same'), gy(:).', 'same');
    R = R - mean(R(:));
    R = R/max(std(R(:)), eps);
end

function val = map_value(scene, mapName, xq, yq, fillVal)
    M = scene.maps.(mapName);
    val = interp2(scene.mapXKm, scene.mapYKm, M.', xq, yq, 'linear', fillVal);
end

function y = fft_lowpass(x, Fs, cutoffHz)
    N = numel(x);
    if cutoffHz >= Fs/2
        y = x; return;
    end
    X = fftshift(fft(x));
    f = (-floor(N/2):ceil(N/2)-1)'*(Fs/N);
    mask = abs(f) <= cutoffHz;
    if numel(mask) ~= N
        mask = mask(1:N);
    end
    y = ifft(ifftshift(X.*mask));
end

function k = gaussian_kernel2d(sigH, sigF)
    sigH = max(sigH,0.1); sigF = max(sigF,0.1);
    h = (-ceil(3*sigH):ceil(3*sigH)).';
    f = (-ceil(3*sigF):ceil(3*sigF));
    gh = exp(-0.5*(h/sigH).^2);
    gf = exp(-0.5*(f/sigF).^2);
    k = gh*gf;
    k = k/sum(k(:));
end

function y = continuity_filter(mask, minH, minF)
    y = mask;
    if minF > 1
        y = conv2(double(y), ones(1,minF), 'same') >= minF;
    end
    if minH > 1
        y = conv2(double(y), ones(minH,1), 'same') >= minH;
    end
end

function w = height_width(h, active)
    if any(active)
        w = max(h(active)) - min(h(active));
    else
        w = NaN;
    end
end

function p = percentile_local(x, pct)
    x = x(isfinite(x));
    if isempty(x), p = NaN; return; end
    x = sort(x(:));
    r = 1 + (numel(x)-1)*pct/100;
    lo = floor(r); hi = ceil(r);
    if lo == hi
        p = x(lo);
    else
        p = x(lo) + (r-lo)*(x(hi)-x(lo));
    end
end

function fmax = max_freq(f, mask)
    if any(mask), fmax = max(f(mask)); else, fmax = NaN; end
end

function span = freq_span(f, mask)
    if any(mask), span = max(f(mask)) - min(f(mask)); else, span = NaN; end
end

function c = trace_continuity(f, mask)
    if ~any(mask), c = 0; return; end
    activeRange = f >= min(f(mask)) & f <= max(f(mask));
    c = sum(mask & activeRange)/max(sum(activeRange),1);
end

function y = sigmoid_soft(x, x0, tau)
    y = 1./(1+exp(-(x-x0)/max(tau,eps)));
end

function y = normalize_score(x, lo, hi)
    y = (x-lo)/max(hi-lo, eps);
    y = min(max(y,0),1);
end

function d = absdiff(a,b)
    if isfinite(a) && isfinite(b)
        d = abs(a-b);
    else
        d = NaN;
    end
end

function y = nan_penalty(x,p)
    if isfinite(x), y = x; else, y = p; end
end

function y = nan_to_value(x,v)
    if isfinite(x), y = x; else, y = v; end
end

function m = max_finite(x)
    x = x(isfinite(x));
    if isempty(x), m = NaN; else, m = max(x); end
end

function m = median_finite(x)
    x = x(isfinite(x));
    if isempty(x), m = NaN; else, m = median(x); end
end

function m = mean_finite(x)
    x = x(isfinite(x));
    if isempty(x), m = NaN; else, m = mean(x); end
end

function s = logical_to_text(tf)
    if tf, s = 'yes'; else, s = 'no'; end
end
