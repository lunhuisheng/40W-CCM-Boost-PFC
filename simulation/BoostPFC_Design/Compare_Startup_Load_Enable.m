% Compare the three preserved startup baselines with delayed load enabling.

clear;
close all;
designDir = fileparts(mfilename('fullpath'));
resultDir = fullfile(designDir, 'results');
archiveDir = fullfile(designDir, 'archive');
fLine = 50;
connectTime = 0.20;

caseNames = { ...
    'No precharge', ...
    '10 ohm / 80 ms / load connected', ...
    '10 ohm / 200 ms / load connected', ...
    '10 ohm / 200 ms / delayed load'};
caseFiles = { ...
    fullfile(archiveDir,'baseline_no_precharge','nominal_24Vac_results.mat'), ...
    fullfile(archiveDir,'precharge_10ohm_80ms','nominal_24Vac_results.mat'), ...
    fullfile(archiveDir,'precharge_10ohm_200ms_load_connected','nominal_24Vac_results.mat'), ...
    fullfile(resultDir,'nominal_24Vac_results.mat')};

cases = repmat(struct, numel(caseFiles), 1);
for index = 1:numel(caseFiles)
    assert(isfile(caseFiles{index}), 'Missing result file: %s', caseFiles{index});
    data = load(caseFiles{index});
    cases(index).name = caseNames{index};
    cases(index).file = caseFiles{index};
    cases(index).peak_inductor_current_A = max(data.iL);
    cases(index).settling_time_2percent_cycle_average_s = ...
        cycleSettlement(data.t, data.vout, 40, fLine);
    cases(index).time_s = data.t;
    cases(index).inductor_current_A = data.iL;
    cases(index).output_voltage_V = data.vout;
end

current = load(caseFiles{end});
beforeIndex = find(current.t < connectTime, 1, 'last');
atIndex = find(current.t >= connectTime, 1, 'first');
halfCycle = current.t >= connectTime & current.t <= connectTime + 1/(2*fLine);
halfIndices = find(halfCycle);
[nextRectifiedPeak, relativePeakIndex] = max(current.vrect(halfCycle));
nextPeakIndex = halfIndices(relativePeakIndex);
afterConnect = current.t >= connectTime;

connection = struct;
connection.control_type = 'Fixed-time command; no voltage-threshold completion detector';
connection.command_time_s = connectTime;
connection.output_voltage_before_connect_V = current.vout(beforeIndex);
connection.rectified_input_at_connect_V = current.vrect(atIndex);
connection.output_voltage_at_connect_V = current.vout(atIndex);
connection.output_minus_rectified_at_connect_V = ...
    current.vout(atIndex)-current.vrect(atIndex);
connection.next_rectified_peak_time_s = current.t(nextPeakIndex);
connection.next_rectified_peak_V = nextRectifiedPeak;
connection.output_voltage_at_next_rectified_peak_V = current.vout(nextPeakIndex);
connection.rectified_minus_output_at_next_peak_V = ...
    nextRectifiedPeak-current.vout(nextPeakIndex);
connection.load_resistance_before_connect_ohm = current.rload(beforeIndex);
connection.load_resistance_at_connect_ohm = current.rload(atIndex);
connection.peak_inductor_current_before_connect_A = max(current.iL(current.t < connectTime));
connection.peak_inductor_current_after_connect_A = max(current.iL(afterConnect));
connection.exceeds_controller_current_reference_limit_4p5A = ...
    connection.peak_inductor_current_after_connect_A > 4.5;

baseline = load(caseFiles{3}, 'metrics');
updated = current.metrics;
steadyComparison = struct;
steadyComparison.baseline_name = caseNames{3};
steadyComparison.updated_name = caseNames{4};
steadyComparison.output_voltage_mean_baseline_V = baseline.metrics.output_voltage_mean_V;
steadyComparison.output_voltage_mean_updated_V = updated.output_voltage_mean_V;
steadyComparison.output_voltage_mean_delta_V = updated.output_voltage_mean_V-baseline.metrics.output_voltage_mean_V;
steadyComparison.output_ripple_baseline_pp_V = baseline.metrics.output_voltage_ripple_pp_V;
steadyComparison.output_ripple_updated_pp_V = updated.output_voltage_ripple_pp_V;
steadyComparison.output_ripple_delta_pp_V = updated.output_voltage_ripple_pp_V-baseline.metrics.output_voltage_ripple_pp_V;
steadyComparison.power_factor_baseline = baseline.metrics.power_factor;
steadyComparison.power_factor_updated = updated.power_factor;
steadyComparison.power_factor_delta = updated.power_factor-baseline.metrics.power_factor;
steadyComparison.thd_baseline_percent = baseline.metrics.input_current_thd_percent;
steadyComparison.thd_updated_percent = updated.input_current_thd_percent;
steadyComparison.thd_delta_percent = updated.input_current_thd_percent-baseline.metrics.input_current_thd_percent;
steadyComparison.output_power_baseline_W = baseline.metrics.output_power_W;
steadyComparison.output_power_updated_W = updated.output_power_W;
steadyComparison.output_power_delta_W = updated.output_power_W-baseline.metrics.output_power_W;

comparison = struct;
comparison.change = 'Load open during precharge; 40 ohm load connected at 200 ms';
comparison.constants = struct('precharge_resistance_ohm',10, ...
    'precharge_release_time_s',0.20,'inductance_H',470e-6, ...
    'output_capacitance_F',2200e-6,'switching_frequency_Hz',50e3);
comparison.cases = rmfield(cases, {'time_s','inductor_current_A','output_voltage_V'});
comparison.connection = connection;
comparison.steady_state = steadyComparison;
comparison.peak_reduction_vs_200ms_load_connected_percent = ...
    100*(cases(3).peak_inductor_current_A-cases(4).peak_inductor_current_A) ...
    /cases(3).peak_inductor_current_A;
comparison.peak_reduction_vs_no_precharge_percent = ...
    100*(cases(1).peak_inductor_current_A-cases(4).peak_inductor_current_A) ...
    /cases(1).peak_inductor_current_A;

fig = figure('Color','w','Position',[100 100 1250 900]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
colors = lines(numel(cases));
nexttile;
hold on;
for index = 1:numel(cases)
    window = cases(index).time_s <= 0.35;
    plot(cases(index).time_s(window), cases(index).inductor_current_A(window), ...
        'LineWidth', 1.0, 'Color', colors(index,:));
end
xline(connectTime,'--k','200 ms load connect');
grid on; ylabel('i_L (A)'); title('Startup current comparison');
legend(caseNames,'Location','northeast');

nexttile;
hold on;
for index = 1:numel(cases)
    window = cases(index).time_s <= 0.85;
    plot(cases(index).time_s(window), cases(index).output_voltage_V(window), ...
        'LineWidth', 1.0, 'Color', colors(index,:));
end
xline(connectTime,'--k','200 ms load connect');
yline(40,'--','40 V target');
grid on; ylabel('V_o (V)'); xlabel('Time (s)');
title('Startup output-voltage comparison');
exportgraphics(fig, fullfile(resultDir,'startup_load_enable_comparison.png'), ...
    'Resolution', 180);
close(fig);

save(fullfile(resultDir,'startup_load_enable_comparison.mat'), ...
    'comparison','cases');
writeText(fullfile(resultDir,'startup_load_enable_comparison.json'), ...
    jsonencode(comparison, PrettyPrint=true));

fprintf('STARTUP_LOAD_ENABLE_COMPARISON_DONE\n');
for index = 1:numel(cases)
    fprintf('%s: peak iL=%.4f A, settling=%.4f s\n', cases(index).name, ...
        cases(index).peak_inductor_current_A, ...
        cases(index).settling_time_2percent_cycle_average_s);
end
disp(connection);
disp(steadyComparison);

function settlingTime = cycleSettlement(t, vout, target, fLine)
dt = median(diff(t));
samplesPerCycle = round(1/(fLine*dt));
completeCycles = floor(numel(vout)/samplesPerCycle);
cycleMean = zeros(completeCycles,1);
cycleEnd = zeros(completeCycles,1);
for cycleIndex = 1:completeCycles
    indices = (cycleIndex-1)*samplesPerCycle+(1:samplesPerCycle);
    cycleMean(cycleIndex) = mean(vout(indices));
    cycleEnd(cycleIndex) = t(indices(end));
end
inBand = abs(cycleMean-target) <= 0.02*target;
firstSettled = find(arrayfun(@(index) all(inBand(index:end)), ...
    (1:completeCycles)'), 1, 'first');
if isempty(firstSettled)
    settlingTime = NaN;
else
    settlingTime = cycleEnd(firstSettled);
end
end

function writeText(fileName, textValue)
fileId = fopen(fileName,'w');
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId,textValue,'char');
end
