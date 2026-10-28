% Compare all preserved startup baselines with voltage qualification.

clear;
close all;
designDir=fileparts(mfilename('fullpath'));
resultDir=fullfile(designDir,'results');
archiveDir=fullfile(designDir,'archive');
fLine=50;

caseNames={ ...
    'No precharge', ...
    '10 ohm / 80 ms / load connected', ...
    '10 ohm / 200 ms / load connected', ...
    '10 ohm / 200 ms / delayed load', ...
    'Voltage qualified / delayed load'};
caseFiles={ ...
    fullfile(archiveDir,'baseline_no_precharge','nominal_24Vac_results.mat'), ...
    fullfile(archiveDir,'precharge_10ohm_80ms','nominal_24Vac_results.mat'), ...
    fullfile(archiveDir,'precharge_10ohm_200ms_load_connected','nominal_24Vac_results.mat'), ...
    fullfile(archiveDir,'precharge_10ohm_200ms_delayed_load','nominal_24Vac_results.mat'), ...
    fullfile(resultDir,'voltage_qualified','nominal_24Vac_results.mat')};

cases=repmat(struct,numel(caseFiles),1);
for index=1:numel(caseFiles)
    data=load(caseFiles{index});
    cases(index).name=caseNames{index};
    cases(index).file=caseFiles{index};
    cases(index).peak_inductor_current_A=max(data.iL);
    [cases(index).settling_time_2percent_cycle_average_s, ...
        cases(index).settled]=cycleSettlement(data.t,data.vout,40,fLine);
    cases(index).time_s=data.t;
    cases(index).inductor_current_A=data.iL;
    cases(index).output_voltage_V=data.vout;
end

updated=load(caseFiles{5});
baseline=load(caseFiles{4},'metrics');
triggerIndex=find(diff(updated.startupEnable>0.5)==1,1,'first')+1;
assert(~isempty(triggerIndex),'Voltage-qualified case did not trigger.');
nextPeakWindow=updated.t>=updated.t(triggerIndex) ...
    & updated.t<=updated.t(triggerIndex)+1/(2*fLine);
windowIndices=find(nextPeakWindow);
[nextPeakVrect,relativePeakIndex]=max(updated.vrect(nextPeakWindow));
nextPeakIndex=windowIndices(relativePeakIndex);

trigger=struct;
trigger.threshold_V=updated.metrics.precharge_voltage_threshold_V;
trigger.qualification_time_s=updated.metrics.precharge_qualification_time_s;
trigger.timeout_time_s=updated.metrics.precharge_timeout_time_s;
trigger.time_s=updated.t(triggerIndex);
trigger.ac_phase_deg=mod(360*fLine*updated.t(triggerIndex),360);
trigger.rectified_phase_deg=mod(360*fLine*updated.t(triggerIndex),180);
trigger.rectified_input_V=updated.vrect(triggerIndex);
trigger.output_voltage_V=updated.vout(triggerIndex);
trigger.inductor_current_A=updated.iL(triggerIndex);
trigger.next_rectified_peak_time_s=updated.t(nextPeakIndex);
trigger.next_rectified_peak_V=nextPeakVrect;
trigger.output_voltage_at_next_peak_V=updated.vout(nextPeakIndex);
trigger.rectified_minus_output_at_next_peak_V= ...
    nextPeakVrect-updated.vout(nextPeakIndex);
trigger.peak_inductor_current_A=max(updated.iL);
trigger.exceeds_4p5A_reference_limit=trigger.peak_inductor_current_A>4.5;
trigger.timeout_occurred=updated.metrics.precharge_timed_out;

steady=struct;
steady.output_voltage_mean_V=updated.metrics.output_voltage_mean_V;
steady.output_voltage_error_percent=updated.metrics.output_voltage_error_percent;
steady.output_ripple_pp_V=updated.metrics.output_voltage_ripple_pp_V;
steady.power_factor=updated.metrics.power_factor;
steady.thd_percent=updated.metrics.input_current_thd_percent;
steady.output_power_W=updated.metrics.output_power_W;
steady.pwm_frequency_Hz=updated.metrics.pwm_frequency_Hz;
steady.delta_vs_200ms_delayed_load=struct( ...
    'output_voltage_mean_V',updated.metrics.output_voltage_mean_V-baseline.metrics.output_voltage_mean_V, ...
    'output_ripple_pp_V',updated.metrics.output_voltage_ripple_pp_V-baseline.metrics.output_voltage_ripple_pp_V, ...
    'power_factor',updated.metrics.power_factor-baseline.metrics.power_factor, ...
    'thd_percentage_point',updated.metrics.input_current_thd_percent-baseline.metrics.input_current_thd_percent, ...
    'output_power_W',updated.metrics.output_power_W-baseline.metrics.output_power_W);

comparison=struct;
comparison.change='Fixed 200 ms command replaced by 90% passive-ceiling voltage qualification';
comparison.constants=struct('precharge_resistance_ohm',10, ...
    'inductance_H',470e-6,'output_capacitance_F',2200e-6, ...
    'switching_frequency_Hz',50e3);
comparison.cases=rmfield(cases,{'time_s','inductor_current_A','output_voltage_V'});
comparison.trigger=trigger;
comparison.steady_state=steady;
comparison.peak_change_vs_200ms_delayed_load_percent= ...
    100*(cases(5).peak_inductor_current_A-cases(4).peak_inductor_current_A) ...
    /cases(4).peak_inductor_current_A;
comparison.pass_peak_current_limit=cases(5).peak_inductor_current_A<=4.5;
comparison.pass_voltage_regulation=updated.metrics.pass_voltage_regulation;
comparison.pass_output_ripple=updated.metrics.pass_output_ripple;
comparison.pass_pf=updated.metrics.pass_pf;
comparison.pass_thd=updated.metrics.pass_thd;

fig=figure('Color','w','Position',[100 100 1250 900]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
colors=lines(numel(cases));
nexttile; hold on;
for index=1:numel(cases)
    window=cases(index).time_s<=0.35;
    plot(cases(index).time_s(window),cases(index).inductor_current_A(window), ...
        'LineWidth',1.0,'Color',colors(index,:));
end
xline(trigger.time_s,'--k','voltage-qualified trigger');
yline(4.5,':r','4.5 A reference limit');
grid on; ylabel('i_L (A)'); title('Five-way startup current comparison');
legend(caseNames,'Location','northeast');

nexttile; hold on;
for index=1:numel(cases)
    window=cases(index).time_s<=0.85;
    plot(cases(index).time_s(window),cases(index).output_voltage_V(window), ...
        'LineWidth',1.0,'Color',colors(index,:));
end
xline(trigger.time_s,'--k','voltage-qualified trigger');
yline(40,'--','40 V target');
grid on; ylabel('V_o (V)'); xlabel('Time (s)');
title('Five-way startup output-voltage comparison');
exportgraphics(fig,fullfile(resultDir,'voltage_qualified_startup_comparison.png'), ...
    'Resolution',180);
close(fig);

save(fullfile(resultDir,'voltage_qualified_startup_comparison.mat'), ...
    'comparison','cases');
writeText(fullfile(resultDir,'voltage_qualified_startup_comparison.json'), ...
    jsonencode(comparison,PrettyPrint=true));

fprintf('VOLTAGE_QUALIFIED_STARTUP_COMPARISON_DONE\n');
for index=1:numel(cases)
    fprintf('%s: peak iL=%.4f A, settling=%.4f s\n',cases(index).name, ...
        cases(index).peak_inductor_current_A, ...
        cases(index).settling_time_2percent_cycle_average_s);
end
disp(trigger);
disp(steady);

function [settlingTime,settled]=cycleSettlement(t,vout,target,fLine)
dt=median(diff(t));
samplesPerCycle=round(1/(fLine*dt));
completeCycles=floor(numel(vout)/samplesPerCycle);
cycleMean=zeros(completeCycles,1);
cycleEnd=zeros(completeCycles,1);
for cycleIndex=1:completeCycles
    indices=(cycleIndex-1)*samplesPerCycle+(1:samplesPerCycle);
    cycleMean(cycleIndex)=mean(vout(indices));
    cycleEnd(cycleIndex)=t(indices(end));
end
inBand=abs(cycleMean-target)<=0.02*target;
firstSettled=find(arrayfun(@(index)all(inBand(index:end)), ...
    (1:completeCycles)'),1,'first');
settled=~isempty(firstSettled);
if settled, settlingTime=cycleEnd(firstSettled); else, settlingTime=NaN; end
end

function writeText(fileName,textValue)
fileId=fopen(fileName,'w');
cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,textValue,'char');
end
