% Run the requested 50/100/200 ms controlled-startup ramp comparison.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_ControlledStartup';
modelFile=fullfile(designDir,[modelName '.slx']);
resultDir=fullfile(designDir,'results','controlled_startup');
if ~isfolder(resultDir), mkdir(resultDir); end
load_system(modelFile);

rampCases=[50 100 200]*1e-3;
observationStopTime=1.2;
caseResults=cell(numel(rampCases),1);
caseData=cell(numel(rampCases),1);

for caseIndex=1:numel(rampCases)
    rampTime=rampCases(caseIndex);
    simulationInput=Simulink.SimulationInput(modelName);
    simulationInput=simulationInput.setVariable('startup_ramp_time_s',rampTime);
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
    [~,data.bypassEnable]=values(logs,'controlled_bypass_enable');
    [~,data.pwmEnable]=values(logs,'controlled_pwm_enable');
    [~,data.loadEnable]=values(logs,'controlled_load_enable');
    [~,data.startupState]=values(logs,'controlled_startup_state');
    [~,data.currentLimitActive]=values(logs,'current_limit_active');
    [~,data.dutySaturated]=values(logs,'duty_saturated');
    [~,data.overcurrentFault]=values(logs,'overcurrent_fault');
    [~,data.currentAmpLimit]=values(logs,'current_amp_limit');

    bypassIndex=risingIndex(data.bypassEnable);
    pwmIndex=risingIndex(data.pwmEnable);
    loadIndex=risingIndex(data.loadEnable);
    metrics=struct;
    metrics.ramp_time_s=rampTime;
    metrics.completed_run_state=data.startupState(end)==4;
    metrics.final_startup_state=data.startupState(end);
    metrics.precharge_timeout=any(data.startupState==-1);
    metrics.overcurrent_fault_state=any(data.startupState==-2) ...
        || any(data.overcurrentFault>0.5);
    metrics.startup_timeout=any(data.startupState==-3);
    metrics.bypass=eventMetrics(data,bypassIndex,f_line);
    metrics.pwm_start=eventMetrics(data,pwmIndex,f_line);
    metrics.load_connect=eventMetrics(data,loadIndex,f_line);
    metrics.peak_inductor_current_A=max(data.iL);
    metrics.peak_current_reference_A=max(data.iRef);
    metrics.current_amplitude_limit_max_A=max(data.currentAmpLimit);
    metrics.current_limit_activated=any(data.currentLimitActive>0.5);
    metrics.current_limit_activation_count=countRises(data.currentLimitActive);
    metrics.overcurrent_fault_activated=any(data.overcurrentFault>0.5);

    pwmActive=data.pwmEnable>0.5;
    metrics.duty_saturation_fraction_during_pwm= ...
        safeFraction(data.dutySaturated(pwmActive)>0.5);
    metrics.duty_min_during_pwm=safeMin(data.duty(pwmActive));
    metrics.duty_max_during_pwm=safeMax(data.duty(pwmActive));
    if ~isempty(pwmIndex) && ~isempty(loadIndex)
        rampWindow=(1:numel(data.t))'>=pwmIndex & (1:numel(data.t))'<loadIndex;
        afterLoadWindow=(1:numel(data.t))'>=loadIndex;
        metrics.peak_iL_pwm_ramp_A=max(data.iL(rampWindow));
        metrics.peak_iL_after_load_A=max(data.iL(afterLoadWindow));
        metrics.duty_saturation_fraction_pwm_ramp= ...
            mean(data.dutySaturated(rampWindow)>0.5);
        metrics.duty_saturation_fraction_after_load= ...
            mean(data.dutySaturated(afterLoadWindow)>0.5);
    else
        metrics.peak_iL_pwm_ramp_A=NaN;
        metrics.peak_iL_after_load_A=NaN;
        metrics.duty_saturation_fraction_pwm_ramp=NaN;
        metrics.duty_saturation_fraction_after_load=NaN;
    end

    if ~isempty(pwmIndex)
        metrics.output_max_after_pwm_V=max(data.vout(pwmIndex:end));
        metrics.output_overshoot_percent=max(0, ...
            100*(metrics.output_max_after_pwm_V-Vout_ref)/Vout_ref);
    else
        metrics.output_max_after_pwm_V=NaN;
        metrics.output_overshoot_percent=NaN;
    end
    [metrics.settling_time_2percent_s,metrics.settled]= ...
        cycleSettlement(data.t,data.vout,Vout_ref,f_line);

    if ~isempty(loadIndex)
        loadWindow=data.t>=data.t(loadIndex) & data.t<=data.t(loadIndex)+0.10;
        metrics.load_connect.output_min_first_100ms_V=min(data.vout(loadWindow));
        metrics.load_connect.peak_iL_first_100ms_A=max(data.iL(loadWindow));
        metrics.load_connect.recovery_time_2percent_s= ...
            recoveryTime(data.t,data.vout,Vout_ref,f_line,data.t(loadIndex));
    else
        metrics.load_connect.output_min_first_100ms_V=NaN;
        metrics.load_connect.peak_iL_first_100ms_A=NaN;
        metrics.load_connect.recovery_time_2percent_s=NaN;
    end

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
    metrics.steady_thd_percent=currentThd(data.t(steadyPower), ...
        data.iac(steadyPower),f_line);
    metrics.pass_peak_below_fault_limit= ...
        metrics.peak_inductor_current_A<actual_peak_fault_limit_A;
    metrics.pass_voltage_regulation=abs(metrics.steady_output_error_percent)<=2;
    metrics.pass_output_ripple=metrics.steady_output_ripple_pp_V<=2;
    metrics.pass_pf=metrics.steady_power_factor>=0.95;
    metrics.pass_thd=metrics.steady_thd_percent<=10;

    caseResults{caseIndex}=metrics;
    caseData{caseIndex}=data;
    caseName=sprintf('ramp_%03dms',round(rampTime*1e3));
    save(fullfile(resultDir,[caseName '_results.mat']),'metrics','data');
    writeText(fullfile(resultDir,[caseName '_metrics.json']), ...
        jsonencode(metrics,PrettyPrint=true));
    fprintf(['CONTROLLED_CASE %d ms: state %.0f, peak %.4f A, ', ...
        'bypass %.6f s, PWM %.6f s, load %.6f s\n'], ...
        round(rampTime*1e3),metrics.final_startup_state, ...
        metrics.peak_inductor_current_A,metrics.bypass.time_s, ...
        metrics.pwm_start.time_s,metrics.load_connect.time_s);
end

summary=struct;
summary.model=modelName;
summary.unchanged_power_stage=struct('L_H',L_boost,'C_F',C_out, ...
    'Vac_rms',Vac_rms,'Vout_ref_V',Vout_ref,'f_sw_Hz',f_sw);
summary.reference_amplitude_limit_A=Ipk_limit;
summary.actual_cycle_limit_A=actual_peak_cycle_limit_A;
summary.actual_fault_limit_A=actual_peak_fault_limit_A;
summary.observation_stop_time_s=observationStopTime;
caseMetrics=[caseResults{:}];
summary.cases=caseMetrics;
writeText(fullfile(resultDir,'controlled_startup_summary.json'), ...
    jsonencode(summary,PrettyPrint=true));
save(fullfile(resultDir,'controlled_startup_summary.mat'),'summary');

% One comparison figure with identical axes for all three ramp times.
fig=figure('Color','w','Position',[100 100 1350 1100]);
tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
colors=lines(numel(rampCases));
nexttile; hold on;
for k=1:numel(rampCases), plot(caseData{k}.t,caseData{k}.vout,'Color',colors(k,:)); end
yline(Vout_ref,'--'); grid on; ylabel('V_o (V)'); title('Controlled-startup ramp comparison');
legend('50 ms','100 ms','200 ms','40 V target','Location','best');
nexttile; hold on;
for k=1:numel(rampCases), plot(caseData{k}.t,caseData{k}.iL,'Color',colors(k,:)); end
yline(actual_peak_cycle_limit_A,'--','cycle limit');
yline(actual_peak_fault_limit_A,':','fault limit'); grid on; ylabel('i_L (A)');
nexttile; hold on;
for k=1:numel(rampCases), plot(caseData{k}.t,caseData{k}.iRef,'Color',colors(k,:)); end
grid on; ylabel('i_L^* (A)');
nexttile; hold on;
for k=1:numel(rampCases), stairs(caseData{k}.t,caseData{k}.startupState,'Color',colors(k,:)); end
grid on; ylabel('State'); xlabel('Time (s)');
exportgraphics(fig,fullfile(resultDir,'controlled_startup_comparison.png'),'Resolution',180);
close(fig);

% Per-case event-focused plots.
for k=1:numel(rampCases)
    data=caseData{k}; metrics=caseResults{k};
    fig=figure('Color','w','Position',[100 100 1250 1000]);
    tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
    nexttile; plot(data.t,data.vout,'LineWidth',1); hold on; yline(Vout_ref,'--');
    addEvents(metrics); grid on; ylabel('V_o (V)');
    title(sprintf('Controlled startup - %.0f ms ramp',rampCases(k)*1e3));
    nexttile; plot(data.t,data.iL,'LineWidth',0.8); hold on; plot(data.t,data.iRef,'LineWidth',0.8);
    yline(actual_peak_cycle_limit_A,'--'); addEvents(metrics); grid on;
    ylabel('Current (A)'); legend('i_L','i_L^*','cycle limit','Location','best');
    nexttile; plot(data.t,data.duty,'LineWidth',0.8); hold on;
    stairs(data.t,data.currentLimitActive,'LineWidth',0.8); stairs(data.t,data.dutySaturated,'LineWidth',0.8);
    addEvents(metrics); grid on; ylabel('Duty / flags');
    legend('duty','current limit','duty saturated','Location','best');
    nexttile; stairs(data.t,data.startupState,'LineWidth',1); hold on;
    stairs(data.t,data.pwmEnable,'LineWidth',0.8); stairs(data.t,data.loadEnable,'LineWidth',0.8);
    grid on; ylabel('State / enable'); xlabel('Time (s)');
    legend('state','PWM enable','load enable','Location','best');
    exportgraphics(fig,fullfile(resultDir,sprintf('ramp_%03dms_waveforms.png', ...
        round(rampCases(k)*1e3))),'Resolution',180);
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
    'rectified_voltage_V',NaN,'output_voltage_V',NaN, ...
    'signed_vrect_minus_vout_V',NaN,'inductor_current_A',NaN);
if isempty(index), return; end
event.time_s=data.t(index);
event.ac_phase_deg=mod(360*fLine*data.t(index),360);
event.rectified_voltage_V=data.vrect(index);
event.output_voltage_V=data.vout(index);
event.signed_vrect_minus_vout_V=data.vrect(index)-data.vout(index);
event.inductor_current_A=data.iL(index);
end

function count=countRises(signal)
count=sum(diff(signal>0.5)==1);
end

function value=safeFraction(values)
if isempty(values), value=NaN; else, value=mean(values); end
end
function value=safeMin(values)
if isempty(values), value=NaN; else, value=min(values); end
end
function value=safeMax(values)
if isempty(values), value=NaN; else, value=max(values); end
end

function [settlingTime,settled]=cycleSettlement(t,vout,target,fLine)
dt=median(diff(t)); n=round(1/(fLine*dt)); count=floor(numel(vout)/n);
means=zeros(count,1); ends=zeros(count,1);
for k=1:count, idx=(k-1)*n+(1:n); means(k)=mean(vout(idx)); ends(k)=t(idx(end)); end
inBand=abs(means-target)<=0.02*target;
first=find(arrayfun(@(k)all(inBand(k:end)),(1:count)'),1,'first');
settled=~isempty(first); if settled, settlingTime=ends(first); else, settlingTime=NaN; end
end

function result=recoveryTime(t,vout,target,fLine,eventTime)
dt=median(diff(t)); n=round(1/(fLine*dt)); average=movmean(vout,n);
candidates=find(t>=eventTime & abs(average-target)<=0.02*target);
result=NaN;
for k=1:numel(candidates)
    index=candidates(k);
    if all(abs(average(index:end)-target)<=0.02*target)
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

function addEvents(metrics)
if metrics.bypass.occurred, xline(metrics.bypass.time_s,':','bypass'); end
if metrics.pwm_start.occurred, xline(metrics.pwm_start.time_s,':','PWM'); end
if metrics.load_connect.occurred, xline(metrics.load_connect.time_s,':','load'); end
end

function writeText(fileName,textValue)
fileId=fopen(fileName,'w'); cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,textValue,'char');
end
