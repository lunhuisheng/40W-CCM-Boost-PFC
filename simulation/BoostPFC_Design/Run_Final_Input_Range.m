% Final 20/24/28 Vac validation of the frozen controlled-startup baseline.
% Only Vac_rms changes. Input-dependent safe-bypass thresholds are derived
% from the existing formulas; all fractions, limits, timing, PI, L/C and the
% direct 40 ohm load strategy remain unchanged.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_LoadConnection';
modelFile=fullfile(designDir,[modelName '.slx']);
resultDir=fullfile(designDir,'results','final_input_range');
if ~isfolder(resultDir), mkdir(resultDir); end
load_system(modelFile);
run(fullfile(designDir,'BoostPFC_Design_LoadConnection_Init.m'));

inputCases=[20 24 28];
stopTime=1.6;
caseResults=cell(numel(inputCases),1);
caseData=cell(numel(inputCases),1);

for caseIndex=1:numel(inputCases)
    VacCase=inputCases(caseIndex);
    derived=deriveInputDependentThresholds(VacCase,Vf_bridge_effective, ...
        Vf_boost_effective,safe_output_fraction,safe_rectified_fraction);

    simulationInput=Simulink.SimulationInput(modelName);
    simulationInput=simulationInput.setVariable('Vac_rms',VacCase);
    simulationInput=simulationInput.setVariable('safe_rectified_peak_V',derived.rectified_peak_V);
    simulationInput=simulationInput.setVariable('safe_passive_ceiling_V',derived.passive_ceiling_V);
    simulationInput=simulationInput.setVariable('safe_output_threshold_V',derived.output_threshold_V);
    simulationInput=simulationInput.setVariable('safe_rectified_threshold_V',derived.rectified_threshold_V);
    simulationInput=simulationInput.setVariable('startup_ramp_time_s',100e-3);
    simulationInput=simulationInput.setVariable('load_connection_strategy',0);
    simulationInput=simulationInput.setModelParameter('StopTime',num2str(stopTime));
    simulationOutput=sim(simulationInput);
    logs=simulationOutput.logsout;

    data=struct;
    [data.t,data.vout]=values(logs,'vout');
    [~,data.vac]=values(logs,'vac');
    [~,data.iac]=values(logs,'iac');
    [~,data.vrect]=values(logs,'vrect');
    [~,data.iL]=values(logs,'iL');
    [~,data.iRef]=values(logs,'iL_ref');
    [~,data.duty]=values(logs,'duty');
    [~,data.pwm]=values(logs,'pwm');
    [~,data.rload]=values(logs,'Rload');
    [~,data.bypassEnable]=values(logs,'controlled_bypass_enable');
    [~,data.pwmEnable]=values(logs,'controlled_pwm_enable');
    [~,data.loadEnable]=values(logs,'controlled_load_enable');
    [~,data.startupState]=values(logs,'controlled_startup_state');
    [~,data.currentLimitActive]=values(logs,'current_limit_active');
    [~,data.dutySaturated]=values(logs,'duty_saturated');
    [~,data.overcurrentFault]=values(logs,'overcurrent_fault');

    bypassIndex=risingIndex(data.bypassEnable);
    pwmIndex=risingIndex(data.pwmEnable);
    loadIndex=risingIndex(data.loadEnable);
    metrics=struct;
    metrics.input_command_rms_V=VacCase;
    metrics.input_dependent_thresholds=derived;
    metrics.bypass=eventMetrics(data,bypassIndex,f_line);
    metrics.pwm_start=eventMetrics(data,pwmIndex,f_line);
    metrics.load_connect=eventMetrics(data,loadIndex,f_line);

    if isempty(bypassIndex)
        prechargeEnd=numel(data.t);
    else
        prechargeEnd=max(bypassIndex-1,1);
    end
    metrics.passive_precharge_peak_iL_A=max(data.iL(1:prechargeEnd));
    metrics.passive_precharge_peak_time_s=data.t(find(data.iL(1:prechargeEnd)== ...
        metrics.passive_precharge_peak_iL_A,1,'first'));
    metrics.bypass.criteria_satisfied=~isempty(bypassIndex) && ...
        metrics.bypass.output_voltage_V>=derived.output_threshold_V && ...
        metrics.bypass.rectified_voltage_V>=derived.rectified_threshold_V && ...
        abs(metrics.bypass.signed_vrect_minus_vout_V)<=safe_voltage_difference_max_V && ...
        metrics.bypass.inductor_current_A<=safe_bypass_current_max_A;
    metrics.bypass.output_threshold_margin_V= ...
        metrics.bypass.output_voltage_V-derived.output_threshold_V;
    metrics.bypass.rectified_threshold_margin_V= ...
        metrics.bypass.rectified_voltage_V-derived.rectified_threshold_V;
    metrics.bypass.difference_limit_margin_V= ...
        safe_voltage_difference_max_V-abs(metrics.bypass.signed_vrect_minus_vout_V);
    metrics.bypass.current_limit_margin_A= ...
        safe_bypass_current_max_A-metrics.bypass.inductor_current_A;

    metrics.final_state=data.startupState(end);
    metrics.completed_run_state=data.startupState(end)==4;
    metrics.current_limit_activated=any(data.currentLimitActive>0.5);
    metrics.current_limit_activation_count=sum(diff(data.currentLimitActive>0.5)==1);
    metrics.overcurrent_fault_activated=any(data.overcurrentFault>0.5) ...
        || any(data.startupState==-2);
    metrics.precharge_timeout=any(data.startupState==-1);
    metrics.startup_timeout=any(data.startupState==-3);
    metrics.full_run_peak_iL_A=max(data.iL);
    metrics.full_run_peak_iL_time_s=data.t(find(data.iL==metrics.full_run_peak_iL_A,1,'first'));
    metrics.peak_below_behavioral_fault_threshold= ...
        metrics.full_run_peak_iL_A<actual_peak_fault_limit_A;

    if ~isempty(loadIndex)
        before=max(loadIndex-1,1);
        metrics.load_connect.output_voltage_before_V=data.vout(before);
        [metrics.load_connect.minimum_output_after_V,minOffset]=min(data.vout(loadIndex:end));
        minIndex=loadIndex+minOffset-1;
        metrics.load_connect.minimum_output_time_s=data.t(minIndex);
        metrics.load_connect.minimum_output_delay_s=data.t(minIndex)-data.t(loadIndex);
        [recoveryDelay,recoveryTime]=recoveryWithHold(data.t,data.vout, ...
            [39.2 40.8],f_line,10e-3,data.t(loadIndex));
        metrics.load_connect.recovery_delay_to_39p2_40p8_hold10ms_s=recoveryDelay;
        metrics.load_connect.recovery_absolute_time_s=recoveryTime;
        startupEndTime=min(data.t(end),data.t(loadIndex)+0.10);
        startupWindow=data.t<=startupEndTime;
        metrics.startup_through_100ms_after_load_peak_iL_A=max(data.iL(startupWindow));
    else
        metrics.load_connect.output_voltage_before_V=NaN;
        metrics.load_connect.minimum_output_after_V=NaN;
        metrics.load_connect.minimum_output_time_s=NaN;
        metrics.load_connect.minimum_output_delay_s=NaN;
        metrics.load_connect.recovery_delay_to_39p2_40p8_hold10ms_s=NaN;
        metrics.load_connect.recovery_absolute_time_s=NaN;
        metrics.startup_through_100ms_after_load_peak_iL_A=max(data.iL);
    end

    steadyOutput=data.t>=data.t(end)-0.10;
    steady=data.t>=data.t(end)-0.20;
    metrics.steady=struct;
    metrics.steady.input_measured_rms_V=rms(data.vac(steady));
    metrics.steady.output_mean_V=mean(data.vout(steadyOutput));
    metrics.steady.output_error_percent=100*(metrics.steady.output_mean_V-Vout_ref)/Vout_ref;
    metrics.steady.output_ripple_pp_V=max(data.vout(steadyOutput))-min(data.vout(steadyOutput));
    metrics.steady.input_power_W=mean(data.vac(steady).*data.iac(steady));
    metrics.steady.output_power_W=mean(data.vout(steady).^2./data.rload(steady));
    metrics.steady.input_current_rms_A=rms(data.iac(steady));
    metrics.steady.input_current_peak_A=max(abs(data.iac(steady)));
    metrics.steady.power_factor=metrics.steady.input_power_W/( ...
        rms(data.vac(steady))*metrics.steady.input_current_rms_A);
    [metrics.steady.thd_harmonics_2_to_40_percent,harmonicRms]= ...
        currentThd(data.t(steady),data.iac(steady),f_line);
    metrics.steady.harmonic_rms_A=harmonicRms(:)';
    metrics.steady.inductor_peak_A=max(data.iL(steady));
    metrics.steady.duty_min=min(data.duty(steady));
    metrics.steady.duty_max=max(data.duty(steady));
    rectifiedPeak=max(data.vrect(steady));
    nearPeak=steady & data.vrect>=0.98*rectifiedPeak;
    metrics.steady.rectified_input_peak_V=rectifiedPeak;
    metrics.steady.boost_headroom_meanVout_minus_rectified_peak_V= ...
        metrics.steady.output_mean_V-rectifiedPeak;
    metrics.steady.duty_mean_near_rectified_peak=mean(data.duty(nearPeak));
    metrics.steady.duty_min_near_rectified_peak=min(data.duty(nearPeak));
    metrics.steady.duty_max_near_rectified_peak=max(data.duty(nearPeak));
    metrics.steady.duty_below_0p01_fraction=mean(data.duty(steady)<=0.01);
    metrics.steady.duty_below_0p02_fraction=mean(data.duty(steady)<=0.02);
    metrics.steady.duty_below_0p05_fraction=mean(data.duty(steady)<=0.05);
    metrics.steady.duty_below_0p05_near_peak_fraction=mean(data.duty(nearPeak)<=0.05);
    metrics.steady.duty_at_upper_limit_fraction=mean(data.duty(steady)>=duty_max-1e-12);
    metrics.steady.duty_saturated_flag_fraction=mean(data.dutySaturated(steady)>0.5);
    metrics.steady.duty_at_upper_limit_near_peak_fraction= ...
        mean(data.duty(nearPeak)>=duty_max-1e-12);
    upperLimit=steady & data.duty>=duty_max-1e-12;
    if any(upperLimit)
        metrics.steady.upper_limit_samples_near_line_zero_fraction= ...
            mean(data.vrect(upperLimit)<=0.10*rectifiedPeak);
    else
        metrics.steady.upper_limit_samples_near_line_zero_fraction=NaN;
    end
    metrics.steady.apparent_uncontrolled_near_peak_fraction=mean( ...
        data.duty(nearPeak)<=1e-6 & data.iRef(nearPeak)>0.05);
    distortion=distortionRegions(data.t(steady),data.vac(steady),data.iac(steady),f_line);
    metrics.steady.normalized_current_distortion=distortion;

    metrics.pass=struct;
    metrics.pass.output_regulation=abs(metrics.steady.output_error_percent)<=2;
    metrics.pass.output_ripple=metrics.steady.output_ripple_pp_V<=2;
    metrics.pass.power_factor=metrics.steady.power_factor>=0.95;
    metrics.pass.thd=metrics.steady.thd_harmonics_2_to_40_percent<=10;
    metrics.pass.state_machine_completed=metrics.completed_run_state;
    metrics.pass.no_behavioral_fault=~metrics.overcurrent_fault_activated;

    caseResults{caseIndex}=metrics;
    caseData{caseIndex}=data;
    caseStem=sprintf('%02dVac',VacCase);
    save(fullfile(resultDir,[caseStem '_raw_results.mat']),'data','metrics');
    writeText(fullfile(resultDir,[caseStem '_metrics.json']), ...
        jsonencode(metrics,PrettyPrint=true));
    fprintf(['INPUT_RANGE %d Vac: state %.0f, bypass %.6f s, load %.6f s, ', ...
        'peak %.4f A, Vout %.4f V, ripple %.4f Vpp, PF %.5f, THD %.4f%%\n'], ...
        VacCase,metrics.final_state,metrics.bypass.time_s,metrics.load_connect.time_s, ...
        metrics.full_run_peak_iL_A,metrics.steady.output_mean_V, ...
        metrics.steady.output_ripple_pp_V,metrics.steady.power_factor, ...
        metrics.steady.thd_harmonics_2_to_40_percent);
end

caseMetrics=[caseResults{:}];
summary=struct;
summary.model=modelName;
summary.frozen_baseline=struct('startup_ramp_time_s',100e-3, ...
    'load_connection_strategy','direct 40 ohm','L_H',L_boost,'C_F',C_out, ...
    'f_sw_Hz',f_sw,'voltage_PI_Kp',Kp_v,'voltage_PI_Ki',Ki_v, ...
    'current_PI_Kp',Kp_i,'current_PI_Ki',Ki_i, ...
    'cycle_limit_A',actual_peak_cycle_limit_A, ...
    'behavioral_fault_threshold_A',actual_peak_fault_limit_A);
summary.threshold_handling=struct( ...
    'independent_change','Vac_rms only', ...
    'derived_values',['safe rectified peak, passive ceiling and 98 percent voltage ' ...
        'thresholds recomputed from the existing formulas for each Vac'], ...
    'unchanged_values',['98 percent fractions, 1.5 V difference, 0.25 A current, ' ...
        '0.2 ms dwell, 0.5 s timeout and every controller/power-stage parameter']);
summary.measurement_method=struct( ...
    'steady_output','last 0.10 s', ...
    'steady_electrical_metrics','last 0.20 s (10 complete 50 Hz line cycles)', ...
    'thd','harmonics 2--40, up to 2 kHz; not an IEC compliance measurement', ...
    'recovery',['20 ms moving-average Vout, searched after its post-load minimum; ' ...
        'first entry into 39.2--40.8 V held continuously for 10 ms'], ...
    'near_rectified_peak','samples at or above 98 percent of measured rectified peak', ...
    'startup_peak',['full-run peak retained plus peak through 100 ms after load ' ...
        'connection; 4.5 A is behavioral only, not hardware-validated protection']);
summary.cases=caseMetrics;

m24=caseMetrics([caseMetrics.input_command_rms_V]==24);
m28=caseMetrics([caseMetrics.input_command_rms_V]==28);
peakIncrease=m28.steady.normalized_current_distortion.peak_region_rms- ...
    m24.steady.normalized_current_distortion.peak_region_rms;
nonPeakIncrease=m28.steady.normalized_current_distortion.nonpeak_region_rms- ...
    m24.steady.normalized_current_distortion.nonpeak_region_rms;
summary.twenty_eight_special=struct( ...
    'boost_headroom_V',m28.steady.boost_headroom_meanVout_minus_rectified_peak_V, ...
    'minimum_duty',m28.steady.duty_min, ...
    'duty_below_0p05_fraction',m28.steady.duty_below_0p05_fraction, ...
    'duty_below_0p05_near_peak_fraction',m28.steady.duty_below_0p05_near_peak_fraction, ...
    'duty_saturated_flag_fraction',m28.steady.duty_saturated_flag_fraction, ...
    'duty_at_upper_limit_near_peak_fraction', ...
        m28.steady.duty_at_upper_limit_near_peak_fraction, ...
    'upper_limit_samples_near_line_zero_fraction', ...
        m28.steady.upper_limit_samples_near_line_zero_fraction, ...
    'apparent_uncontrolled_near_peak_fraction',m28.steady.apparent_uncontrolled_near_peak_fraction, ...
    'normalized_peak_region_distortion_increase_vs_24',peakIncrease, ...
    'normalized_nonpeak_region_distortion_increase_vs_24',nonPeakIncrease, ...
    'distortion_increase_more_concentrated_near_peak',peakIncrease>nonPeakIncrease, ...
    'third_harmonic_percent_of_fundamental_24Vac', ...
        100*m24.steady.harmonic_rms_A(3)/m24.steady.harmonic_rms_A(1), ...
    'third_harmonic_percent_of_fundamental_28Vac', ...
        100*m28.steady.harmonic_rms_A(3)/m28.steady.harmonic_rms_A(1), ...
    'startup_peak_change_vs_24_A', ...
        m28.startup_through_100ms_after_load_peak_iL_A- ...
        m24.startup_through_100ms_after_load_peak_iL_A, ...
    'load_minimum_change_vs_24_V',m28.load_connect.minimum_output_after_V- ...
        m24.load_connect.minimum_output_after_V, ...
    'load_recovery_change_vs_24_s', ...
        m28.load_connect.recovery_delay_to_39p2_40p8_hold10ms_s- ...
        m24.load_connect.recovery_delay_to_39p2_40p8_hold10ms_s);

save(fullfile(resultDir,'final_input_range_summary.mat'),'summary');
writeText(fullfile(resultDir,'final_input_range_summary.json'), ...
    jsonencode(summary,PrettyPrint=true));

% Unified full startup comparison.
fig=figure('Color','w','Position',[60 40 1450 1150]);
tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
colors=lines(numel(inputCases));
nexttile; hold on;
for k=1:numel(inputCases), plot(caseData{k}.t,caseData{k}.vout,'Color',colors(k,:)); end
yline(40,'--'); grid on; ylabel('V_o (V)'); title('Final controlled-startup input-range validation');
legend('20 Vac','24 Vac','28 Vac','40 V','Location','best');
nexttile; hold on;
for k=1:numel(inputCases), plot(caseData{k}.t,caseData{k}.iL,'Color',colors(k,:)); end
yline(actual_peak_fault_limit_A,':','4.5 A behavioral threshold'); grid on; ylabel('i_L (A)');
nexttile; hold on;
for k=1:numel(inputCases), stairs(caseData{k}.t,caseData{k}.startupState,'Color',colors(k,:)); end
grid on; ylabel('State');
nexttile; hold on;
for k=1:numel(inputCases), plot(caseData{k}.t,caseData{k}.vrect,'Color',colors(k,:)); end
grid on; ylabel('V_{rect} (V)'); xlabel('Time (s)');
exportgraphics(fig,fullfile(resultDir,'input_range_startup_comparison.png'),'Resolution',180);
close(fig);

% Two-cycle steady-state comparison.
fig=figure('Color','w','Position',[70 50 1450 1150]);
tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on;
for k=1:numel(inputCases)
    mask=caseData{k}.t>=caseData{k}.t(end)-0.04;
    plot(caseData{k}.t(mask)-caseData{k}.t(end),caseData{k}.vout(mask),'Color',colors(k,:));
end
grid on; ylabel('V_o (V)'); title('Final two line cycles'); legend('20 Vac','24 Vac','28 Vac','Location','best');
nexttile; hold on;
for k=1:numel(inputCases)
    mask=caseData{k}.t>=caseData{k}.t(end)-0.04;
    vac=caseData{k}.vac(mask); iac=caseData{k}.iac(mask);
    plot(caseData{k}.t(mask)-caseData{k}.t(end),vac/max(abs(vac)),'--','Color',colors(k,:));
    plot(caseData{k}.t(mask)-caseData{k}.t(end),iac/max(abs(iac)),'Color',colors(k,:));
end
grid on; ylabel('Normalized');
nexttile; hold on;
for k=1:numel(inputCases)
    mask=caseData{k}.t>=caseData{k}.t(end)-0.04;
    plot(caseData{k}.t(mask)-caseData{k}.t(end),caseData{k}.iL(mask),'Color',colors(k,:));
end
grid on; ylabel('i_L (A)');
nexttile; hold on;
for k=1:numel(inputCases)
    mask=caseData{k}.t>=caseData{k}.t(end)-0.04;
    plot(caseData{k}.t(mask)-caseData{k}.t(end),caseData{k}.duty(mask),'Color',colors(k,:));
end
grid on; ylabel('Duty'); xlabel('Time before end (s)');
exportgraphics(fig,fullfile(resultDir,'input_range_steady_comparison.png'),'Resolution',180);
close(fig);

% 28 Vac headroom and line-peak detail.
k=find(inputCases==28,1); data=caseData{k}; metrics=caseResults{k};
mask=data.t>=data.t(end)-0.04;
fig=figure('Color','w','Position',[80 60 1400 1050]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
nexttile; plot(data.t(mask)-data.t(end),data.vout(mask),'LineWidth',1); hold on;
plot(data.t(mask)-data.t(end),data.vrect(mask),'LineWidth',1); grid on;
ylabel('Voltage (V)'); legend('Vout','Vrect','Location','best');
title(sprintf('28 Vac detail: measured headroom %.3f V', ...
    metrics.steady.boost_headroom_meanVout_minus_rectified_peak_V));
nexttile; plot(data.t(mask)-data.t(end),data.duty(mask),'LineWidth',1); grid on;
ylabel('Duty'); yline(0.05,':','5%');
nexttile; plot(data.t(mask)-data.t(end),data.vac(mask)/max(abs(data.vac(mask))),'--','LineWidth',1); hold on;
plot(data.t(mask)-data.t(end),data.iac(mask)/max(abs(data.iac(mask))),'LineWidth',1);
grid on; ylabel('Normalized'); xlabel('Time before end (s)');
legend('Vac','Iac','Location','best');
exportgraphics(fig,fullfile(resultDir,'28Vac_headroom_and_waveform_detail.png'),'Resolution',180);
close(fig);

close_system(modelName,0);

function derived=deriveInputDependentThresholds(Vac,VfBridge,VfBoost,outFraction,rectFraction)
derived=struct;
derived.rectified_peak_V=sqrt(2)*Vac-2*VfBridge;
derived.passive_ceiling_V=derived.rectified_peak_V-VfBoost;
derived.output_threshold_V=outFraction*derived.passive_ceiling_V;
derived.rectified_threshold_V=rectFraction*derived.rectified_peak_V;
end

function [t,data]=values(logs,name)
element=logs.getElement(name); assert(~isempty(element),'Missing signal: %s',name);
t=element.Values.Time(:); data=element.Values.Data(:);
end

function index=risingIndex(signal)
index=find(diff(signal>0.5)==1,1,'first')+1;
end

function event=eventMetrics(data,index,fLine)
event=struct('occurred',~isempty(index),'time_s',NaN,'ac_phase_deg',NaN, ...
    'rectified_phase_deg',NaN,'rectified_voltage_V',NaN,'output_voltage_V',NaN, ...
    'signed_vrect_minus_vout_V',NaN,'inductor_current_A',NaN);
if isempty(index), return; end
event.time_s=data.t(index);
event.ac_phase_deg=mod(360*fLine*data.t(index),360);
event.rectified_phase_deg=mod(360*fLine*data.t(index),180);
event.rectified_voltage_V=data.vrect(index);
event.output_voltage_V=data.vout(index);
event.signed_vrect_minus_vout_V=data.vrect(index)-data.vout(index);
event.inductor_current_A=data.iL(index);
end

function [delay,recoveryTime]=recoveryWithHold(t,vout,band,fLine,holdTime,eventTime)
dt=median(diff(t)); nAverage=round(1/(fLine*dt));
average=movmean(vout,nAverage);
eventIndex=find(t>=eventTime,1,'first');
[~,offset]=min(average(eventIndex:end));
searchStart=eventIndex+offset-1;
nHold=max(1,ceil(holdTime/dt));
inBand=average>=band(1) & average<=band(2);
delay=NaN; recoveryTime=NaN;
for index=searchStart:numel(t)-nHold+1
    if all(inBand(index:index+nHold-1))
        recoveryTime=t(index); delay=t(index)-eventTime; return;
    end
end
end

function [thd,harmonicRms]=currentThd(t,current,fLine)
harmonicRms=zeros(40,1);
for h=1:40
    c=2*mean(current.*cos(2*pi*h*fLine*t));
    s=2*mean(current.*sin(2*pi*h*fLine*t));
    harmonicRms(h)=hypot(c,s)/sqrt(2);
end
thd=100*sqrt(sum(harmonicRms(2:end).^2))/harmonicRms(1);
end

function result=distortionRegions(t,vac,iac,fLine)
c=2*mean(iac.*cos(2*pi*fLine*t));
s=2*mean(iac.*sin(2*pi*fLine*t));
fundamental=c*cos(2*pi*fLine*t)+s*sin(2*pi*fLine*t);
fundamentalPeak=hypot(c,s);
normalizedResidual=(iac-fundamental)/max(fundamentalPeak,eps);
peakRegion=abs(vac)>=0.90*max(abs(vac));
result=struct;
result.peak_region_definition='abs(Vac) >= 90 percent of measured peak';
result.peak_region_sample_fraction=mean(peakRegion);
result.peak_region_rms=rms(normalizedResidual(peakRegion));
result.nonpeak_region_rms=rms(normalizedResidual(~peakRegion));
result.peak_region_fraction_of_residual_energy= ...
    sum(normalizedResidual(peakRegion).^2)/sum(normalizedResidual.^2);
end

function writeText(fileName,textValue)
fileId=fopen(fileName,'w'); cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,textValue,'char');
end
