% Consolidate historical startup baselines and controlled-startup cases.
% This script reads archived results only; it does not rerun or alter models.

clear;
close all;
designDir=fileparts(mfilename('fullpath'));
archiveDir=fullfile(designDir,'archive');
resultDir=fullfile(designDir,'results','controlled_startup');

baselineNames={ ...
    'No precharge', ...
    '10 ohm / 80 ms / load connected', ...
    '10 ohm / 200 ms / load connected', ...
    '10 ohm / 200 ms / delayed load', ...
    '90% passive ceiling / 5 ms'};
baselineFolders={ ...
    'baseline_no_precharge', ...
    'precharge_10ohm_80ms', ...
    'precharge_10ohm_200ms_load_connected', ...
    'precharge_10ohm_200ms_delayed_load', ...
    'voltage_qualified_90pct_5ms'};

emptyItem=struct( ...
    'strategy','', ...
    'source','', ...
    'peak_inductor_current_A',NaN, ...
    'settling_time_2percent_s',NaN, ...
    'output_overshoot_percent',NaN, ...
    'steady_output_mean_V',NaN, ...
    'steady_output_ripple_pp_V',NaN, ...
    'steady_power_factor',NaN, ...
    'steady_thd_percent',NaN, ...
    'pass_peak_below_4p5A',false, ...
    'bypass_time_s',NaN, ...
    'pwm_start_time_s',NaN, ...
    'load_connect_time_s',NaN, ...
    'load_connect_min_100ms_V',NaN, ...
    'load_recovery_time_2percent_s',NaN, ...
    'current_limit_activated',NaN, ...
    'overcurrent_fault_activated',NaN);
entries=repmat(emptyItem,0,1);
for index=1:numel(baselineFolders)
    metrics=readJson(fullfile(archiveDir,baselineFolders{index}, ...
        'nominal_24Vac_metrics.json'));
    item=emptyItem;
    item.strategy=baselineNames{index};
    item.source='archived historical baseline';
    item.peak_inductor_current_A=metrics.inductor_current_overall_max_A;
    item.settling_time_2percent_s=metrics.settling_time_2percent_s;
    item.output_overshoot_percent=metrics.startup_overshoot_percent;
    item.steady_output_mean_V=metrics.output_voltage_mean_V;
    item.steady_output_ripple_pp_V=metrics.output_voltage_ripple_pp_V;
    item.steady_power_factor=metrics.power_factor;
    item.steady_thd_percent=metrics.input_current_thd_percent;
    item.pass_peak_below_4p5A=metrics.inductor_current_overall_max_A<4.5;
    entries(end+1,1)=item; %#ok<SAGROW>
end

controlled=readJson(fullfile(resultDir,'controlled_startup_summary.json'));
for index=1:numel(controlled.cases)
    caseResult=controlled.cases(index);
    item=emptyItem;
    item.strategy=sprintf('Safe bypass + %.0f ms soft start', ...
        caseResult.ramp_time_s*1e3);
    item.source='controlled startup simulation';
    item.peak_inductor_current_A=caseResult.peak_inductor_current_A;
    item.settling_time_2percent_s=caseResult.settling_time_2percent_s;
    item.output_overshoot_percent=caseResult.output_overshoot_percent;
    item.steady_output_mean_V=caseResult.steady_output_mean_V;
    item.steady_output_ripple_pp_V=caseResult.steady_output_ripple_pp_V;
    item.steady_power_factor=caseResult.steady_power_factor;
    item.steady_thd_percent=caseResult.steady_thd_percent;
    item.pass_peak_below_4p5A=caseResult.pass_peak_below_fault_limit;
    item.bypass_time_s=caseResult.bypass.time_s;
    item.pwm_start_time_s=caseResult.pwm_start.time_s;
    item.load_connect_time_s=caseResult.load_connect.time_s;
    item.load_connect_min_100ms_V=caseResult.load_connect.output_min_first_100ms_V;
    item.load_recovery_time_2percent_s=caseResult.load_connect.recovery_time_2percent_s;
    item.current_limit_activated=caseResult.current_limit_activated;
    item.overcurrent_fault_activated=caseResult.overcurrent_fault_activated;
    entries(end+1,1)=item; %#ok<SAGROW>
end

comparison=struct;
comparison.note=['The 4.5 A line is the measured-current fault threshold in the ' ...
    'controlled model, not merely the current-reference amplitude limit.'];
comparison.reference_amplitude_limit_A=controlled.reference_amplitude_limit_A;
comparison.actual_cycle_limit_A=controlled.actual_cycle_limit_A;
comparison.actual_fault_limit_A=controlled.actual_fault_limit_A;
comparison.strategies=entries;
writeText(fullfile(resultDir,'all_startup_strategy_comparison.json'), ...
    jsonencode(comparison,PrettyPrint=true));

labels={entries.strategy};
peaks=[entries.peak_inductor_current_A];
settling=[entries.settling_time_2percent_s];
overshoot=[entries.output_overshoot_percent];
fig=figure('Color','w','Position',[100 100 1500 900]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile;
bar(peaks,'FaceColor',[0.18 0.50 0.75]); hold on;
yline(4.0,'--','Cycle limiter (4.0 A)','LineWidth',1.1);
yline(4.5,'-.','Fault threshold (4.5 A)','LineWidth',1.1);
set(gca,'XTick',1:numel(labels),'XTickLabel',labels,'XTickLabelRotation',22);
ylabel('Full-cycle peak i_L (A)'); grid on;
title('Startup peak-current comparison (archived and controlled cases)');
for index=1:numel(peaks)
    text(index,peaks(index)+0.45,sprintf('%.2f',peaks(index)), ...
        'HorizontalAlignment','center','FontSize',9);
end
nexttile;
yyaxis left; bar(settling,0.65,'FaceColor',[0.32 0.65 0.38]);
ylabel('2% settling time (s)');
yyaxis right; plot(1:numel(labels),overshoot,'o-','LineWidth',1.3, ...
    'Color',[0.82 0.32 0.22]); ylabel('Output overshoot (%)');
set(gca,'XTick',1:numel(labels),'XTickLabel',labels,'XTickLabelRotation',22);
grid on; title('Startup settling-time and overshoot tradeoff');
exportgraphics(fig,fullfile(resultDir,'all_startup_strategy_comparison.png'), ...
    'Resolution',180);
close(fig);

fprintf('Saved comparison for %d startup strategies.\n',numel(entries));
fprintf('Controlled peaks (50/100/200 ms): %.4f / %.4f / %.4f A.\n', ...
    peaks(end-2),peaks(end-1),peaks(end));

function result=readJson(fileName)
result=jsondecode(fileread(fileName));
end

function writeText(fileName,textValue)
fileId=fopen(fileName,'w');
cleanup=onCleanup(@()fclose(fileId)); %#ok<NASGU>
fwrite(fileId,textValue,'char');
end
