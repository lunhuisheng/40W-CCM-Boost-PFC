% Compare three load-connection profiles with fixed 100 ms controlled startup.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_LoadConnection';
modelFile=fullfile(designDir,[modelName '.slx']);
resultDir=fullfile(designDir,'results','load_connection_study');
if ~isfolder(resultDir), mkdir(resultDir); end
load_system(modelFile);

strategyIds=[0 1 2];
strategyNames={'direct_40ohm','staged_160_80_40ohm','conductance_ramp_80ms'};
strategyLabels={'Direct 40 ohm','160 -> 80 -> 40 ohm','80 ms conductance ramp'};
observationStopTime=1.4;
caseResults=cell(numel(strategyIds),1);
caseData=cell(numel(strategyIds),1);

% Candidate comparison criteria, not pre-existing project requirements.
candidateMinimumOutput_V=34.0;
candidateRecoveryTime_s=0.35;
recoveryBand_V=[39.2 40.8];

for caseIndex=1:numel(strategyIds)
    strategy=strategyIds(caseIndex);
    simulationInput=Simulink.SimulationInput(modelName);
    simulationInput=simulationInput.setVariable('startup_ramp_time_s',100e-3);
    simulationInput=simulationInput.setVariable('load_connection_strategy',strategy);
    simulationInput=simulationInput.setModelParameter('StopTime',num2str(observationStopTime));
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
    [~,data.loadEnable]=values(logs,'controlled_load_enable');
    [~,data.startupState]=values(logs,'controlled_startup_state');
    [~,data.currentLimitActive]=values(logs,'current_limit_active');
    [~,data.dutySaturated]=values(logs,'duty_saturated');
    [~,data.overcurrentFault]=values(logs,'overcurrent_fault');

    loadIndex=risingIndex(data.loadEnable);
    fullLoadIndex=[];
    if ~isempty(loadIndex)
        candidates=find((1:numel(data.t))'>=loadIndex & ...
            data.rload<=Rload_nominal*(1+1e-9),1,'first');
        fullLoadIndex=candidates;
    end

    metrics=struct;
    metrics.strategy_id=strategy;
    metrics.strategy_name=strategyNames{caseIndex};
    metrics.completed_run_state=data.startupState(end)==4;
    metrics.final_startup_state=data.startupState(end);
    metrics.load_start=eventMetrics(data,loadIndex,f_line);
    metrics.full_load=eventMetrics(data,fullLoadIndex,f_line);
    if ~isempty(loadIndex)
        before=max(loadIndex-1,1);
        metrics.load_start.output_voltage_before_V=data.vout(before);
        metrics.load_start.load_resistance_before_ohm=data.rload(before);
        metrics.load_start.load_resistance_after_ohm=data.rload(loadIndex);
        [metrics.minimum_output_after_start_V,minOffset]=min(data.vout(loadIndex:end));
        minIndex=loadIndex+minOffset-1;
        metrics.minimum_output_time_s=data.t(minIndex);
        metrics.minimum_output_delay_from_start_s=data.t(minIndex)-data.t(loadIndex);
        metrics.peak_inductor_current_after_start_A=max(data.iL(loadIndex:end));
        metrics.recovery_time_to_39p2_40p8_s=recoveryTime( ...
            data.t,data.vout,recoveryBand_V,f_line,data.t(loadIndex));
    else
        metrics.load_start.output_voltage_before_V=NaN;
        metrics.load_start.load_resistance_before_ohm=NaN;
        metrics.load_start.load_resistance_after_ohm=NaN;
        metrics.minimum_output_after_start_V=NaN;
        metrics.minimum_output_time_s=NaN;
        metrics.minimum_output_delay_from_start_s=NaN;
        metrics.peak_inductor_current_after_start_A=NaN;
        metrics.recovery_time_to_39p2_40p8_s=NaN;
    end
    if ~isempty(fullLoadIndex) && ~isempty(loadIndex)
        metrics.full_load.delay_from_load_start_s= ...
            data.t(fullLoadIndex)-data.t(loadIndex);
        metrics.full_load.recovery_time_to_39p2_40p8_s= ...
            recoveryTime(data.t,data.vout,recoveryBand_V,f_line,data.t(fullLoadIndex));
    else
        metrics.full_load.delay_from_load_start_s=NaN;
        metrics.full_load.recovery_time_to_39p2_40p8_s=NaN;
    end
    metrics.peak_inductor_current_full_run_A=max(data.iL);
    metrics.current_limit_activated=any(data.currentLimitActive>0.5);
    metrics.overcurrent_fault_activated=any(data.overcurrentFault>0.5);
    pwmActive=data.startupState>=2;
    metrics.duty_saturation_fraction_during_pwm= ...
        safeMean(data.dutySaturated(pwmActive)>0.5);

    steady=data.t>=data.t(end)-0.10;
    steadyPower=data.t>=data.t(end)-0.20;
    metrics.steady_output_mean_V=mean(data.vout(steady));
    metrics.steady_output_ripple_pp_V=max(data.vout(steady))-min(data.vout(steady));
    metrics.steady_output_error_percent=100*(metrics.steady_output_mean_V-Vout_ref)/Vout_ref;
    metrics.steady_input_power_W=mean(data.vac(steadyPower).*data.iac(steadyPower));
    metrics.steady_output_power_W=mean(data.vout(steadyPower).^2./data.rload(steadyPower));
    metrics.steady_input_voltage_rms_V=rms(data.vac(steadyPower));
    metrics.steady_input_current_rms_A=rms(data.iac(steadyPower));
    metrics.steady_power_factor=metrics.steady_input_power_W/( ...
        metrics.steady_input_voltage_rms_V*metrics.steady_input_current_rms_A);
    metrics.steady_thd_percent=currentThd(data.t(steadyPower),data.iac(steadyPower),f_line);

    metrics.candidate_minimum_output_threshold_V=candidateMinimumOutput_V;
    metrics.candidate_recovery_limit_s=candidateRecoveryTime_s;
    metrics.candidate_pass_minimum_output= ...
        metrics.minimum_output_after_start_V>=candidateMinimumOutput_V;
    metrics.candidate_pass_recovery= ...
        metrics.recovery_time_to_39p2_40p8_s<=candidateRecoveryTime_s;
    metrics.pass_steady_voltage_regulation=abs(metrics.steady_output_error_percent)<=2;
    metrics.pass_steady_ripple=metrics.steady_output_ripple_pp_V<=2;
    metrics.pass_steady_pf=metrics.steady_power_factor>=0.95;
    metrics.pass_steady_thd=metrics.steady_thd_percent<=10;

    caseResults{caseIndex}=metrics;
    caseData{caseIndex}=data;
    save(fullfile(resultDir,[strategyNames{caseIndex} '_results.mat']),'metrics','data');
    writeText(fullfile(resultDir,[strategyNames{caseIndex} '_metrics.json']), ...
        jsonencode(metrics,PrettyPrint=true));
    fprintf(['LOAD_CASE %s: start %.6f s phase %.3f deg, full %.6f s, ', ...
        'Vmin %.4f V, recovery %.4f s, peak iL %.4f A\n'], ...
        strategyNames{caseIndex},metrics.load_start.time_s, ...
        metrics.load_start.ac_phase_deg,metrics.full_load.time_s, ...
        metrics.minimum_output_after_start_V, ...
        metrics.recovery_time_to_39p2_40p8_s, ...
        metrics.peak_inductor_current_full_run_A);
end

caseMetrics=[caseResults{:}];
summary=struct;
summary.model=modelName;
summary.fixed_conditions=struct('Vac_rms',Vac_rms,'Vout_ref_V',Vout_ref, ...
    'Rload_nominal_ohm',Rload_nominal,'startup_ramp_time_s',100e-3, ...
    'load_stage_interval_s',load_stage_interval_s, ...
    'load_conductance_ramp_time_s',load_conductance_ramp_time_s, ...
    'voltage_PI_Kp',Kp_v,'voltage_PI_Ki',Ki_v, ...
    'current_PI_Kp',Kp_i,'current_PI_Ki',Ki_i);
summary.measurement_method=struct( ...
    'load_start','rising edge of the common sequencer load-enable signal', ...
    'minimum_output','minimum instantaneous sampled Vout from load start to simulation end', ...
    'recovery',['20 ms moving average first enters 39.2--40.8 V and remains there ' ...
        'through the simulation end'], ...
    'steady_output','last 0.10 s', ...
    'steady_power_pf_thd','last 0.20 s', ...
    'thd','harmonics 2--40 relative to fundamental; not an IEC compliance measurement');
summary.candidate_dynamic_criteria=struct( ...
    'status','study candidates only; not inherited project requirements', ...
    'minimum_output_V',candidateMinimumOutput_V, ...
    'recovery_band_V',recoveryBand_V, ...
    'recovery_limit_s',candidateRecoveryTime_s);
summary.cases=caseMetrics;
loadStarts=[caseMetrics.load_start];
summary.load_start_alignment=struct( ...
    'time_spread_s',max([loadStarts.time_s])-min([loadStarts.time_s]), ...
    'phase_spread_deg',max([loadStarts.ac_phase_deg])-min([loadStarts.ac_phase_deg]), ...
    'preload_voltage_spread_V',max([loadStarts.output_voltage_before_V])- ...
        min([loadStarts.output_voltage_before_V]));
save(fullfile(resultDir,'load_connection_summary.mat'),'summary');
writeText(fullfile(resultDir,'load_connection_summary.json'), ...
    jsonencode(summary,PrettyPrint=true));

% Common-axis transient comparison.
fig=figure('Color','w','Position',[80 60 1400 1120]);
tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
colors=lines(numel(strategyIds));
nexttile; hold on;
for k=1:numel(strategyIds), plot(caseData{k}.t,caseData{k}.vout,'Color',colors(k,:),'LineWidth',1); end
yline(39.2,'--'); yline(40.8,'--'); yline(candidateMinimumOutput_V,':');
grid on; ylabel('V_o (V)'); title('Load-connection dynamic comparison - fixed 100 ms startup');
legend([strategyLabels {'39.2 V','40.8 V','34 V candidate'}],'Location','best');
nexttile; hold on;
for k=1:numel(strategyIds), plot(caseData{k}.t,1./caseData{k}.rload,'Color',colors(k,:),'LineWidth',1); end
grid on; ylabel('Load G (S)');
nexttile; hold on;
for k=1:numel(strategyIds), plot(caseData{k}.t,caseData{k}.iL,'Color',colors(k,:),'LineWidth',0.8); end
yline(actual_peak_fault_limit_A,':','4.5 A diagnostic threshold');
grid on; ylabel('i_L (A)');
nexttile; hold on;
for k=1:numel(strategyIds), plot(caseData{k}.t,caseData{k}.vrect,'Color',colors(k,:),'LineWidth',0.8); end
grid on; ylabel('|V_{in}| (V)'); xlabel('Time (s)');
set(findall(fig,'Type','axes'),'XLim',[0.54 1.05]);
exportgraphics(fig,fullfile(resultDir,'load_connection_comparison.png'),'Resolution',180);
close(fig);

% One result panel per strategy.
for k=1:numel(strategyIds)
    data=caseData{k}; metrics=caseResults{k};
    fig=figure('Color','w','Position',[100 80 1300 1000]);
    tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
    nexttile; plot(data.t,data.vout,'LineWidth',1); hold on;
    yline(39.2,'--'); yline(40.8,'--'); yline(34,':');
    xline(metrics.load_start.time_s,':','load start');
    xline(metrics.full_load.time_s,':','full load'); grid on; ylabel('V_o (V)');
    title(strategyLabels{k});
    nexttile; plot(data.t,1./data.rload,'LineWidth',1); grid on; ylabel('Load G (S)');
    nexttile; plot(data.t,data.iL,'LineWidth',0.8); hold on; plot(data.t,data.iRef,'LineWidth',0.8);
    yline(actual_peak_fault_limit_A,':'); grid on; ylabel('Current (A)'); legend('i_L','i_L^*','4.5 A','Location','best');
    nexttile; plot(data.t,data.vrect,'LineWidth',0.8); hold on; plot(data.t,data.duty,'LineWidth',0.8);
    grid on; ylabel('Vrect / duty'); xlabel('Time (s)');
    set(findall(fig,'Type','axes'),'XLim',[0.54 1.05]);
    exportgraphics(fig,fullfile(resultDir,[strategyNames{k} '_waveforms.png']),'Resolution',180);
    close(fig);
end
close_system(modelName,0);

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
    'inductor_current_A',NaN,'load_resistance_ohm',NaN);
if isempty(index), return; end
event.time_s=data.t(index);
event.ac_phase_deg=mod(360*fLine*data.t(index),360);
event.rectified_phase_deg=mod(180*fLine*data.t(index),180);
event.rectified_voltage_V=data.vrect(index);
event.output_voltage_V=data.vout(index);
event.inductor_current_A=data.iL(index);
event.load_resistance_ohm=data.rload(index);
end

function result=recoveryTime(t,vout,band,fLine,eventTime)
dt=median(diff(t)); samplesPerLineCycle=round(1/(fLine*dt));
cycleAverage=movmean(vout,samplesPerLineCycle);
candidates=find(t>=eventTime & cycleAverage>=band(1) & cycleAverage<=band(2));
result=NaN;
for k=1:numel(candidates)
    index=candidates(k);
    if all(cycleAverage(index:end)>=band(1) & cycleAverage(index:end)<=band(2))
        result=t(index)-eventTime; return;
    end
end
end

function thd=currentThd(t,current,fLine)
harmonicRms=zeros(40,1);
for h=1:40
    c=2*mean(current.*cos(2*pi*h*fLine*t));
    s=2*mean(current.*sin(2*pi*h*fLine*t));
    harmonicRms(h)=hypot(c,s)/sqrt(2);
end
thd=100*sqrt(sum(harmonicRms(2:end).^2))/harmonicRms(1);
end

function value=safeMean(values)
if isempty(values), value=NaN; else, value=mean(values); end
end

function writeText(fileName,textValue)
fileId=fopen(fileName,'w'); cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,textValue,'char');
end
