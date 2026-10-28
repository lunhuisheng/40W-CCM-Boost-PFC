% Run and record the isolated safe-bypass experiment.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_SafeBypass';
modelFile=fullfile(designDir,[modelName '.slx']);
resultDir=fullfile(designDir,'results','safe_bypass');
if ~isfolder(resultDir), mkdir(resultDir); end
load_system(modelFile);
simulationOutput=sim(modelName);
logs=simulationOutput.logsout;

t=signal(logs,'vout').Time(:);
vout=signal(logs,'vout').Data(:);
vrect=signal(logs,'vrect').Data(:);
iL=signal(logs,'iL').Data(:);
pwm=signal(logs,'pwm').Data(:);
rload=signal(logs,'Rload').Data(:);
enable=signal(logs,'safe_bypass_enable').Data(:);
state=signal(logs,'safe_bypass_state').Data(:);
triggerIndex=find(diff(enable>0.5)==1,1,'first')+1;

result=struct;
result.thresholds=struct( ...
    'output_voltage_V',safe_output_threshold_V, ...
    'rectified_voltage_V',safe_rectified_threshold_V, ...
    'absolute_voltage_difference_V',safe_voltage_difference_max_V, ...
    'inductor_current_A',safe_bypass_current_max_A, ...
    'hold_time_s',safe_condition_hold_time_s, ...
    'timeout_s',safe_bypass_timeout_s);
result.timed_out=any(state<-.5);
result.triggered=~isempty(triggerIndex);
if result.triggered
    result.trigger_time_s=t(triggerIndex);
    result.trigger_ac_phase_deg=mod(360*f_line*t(triggerIndex),360);
    result.trigger_rectified_voltage_V=vrect(triggerIndex);
    result.trigger_output_voltage_V=vout(triggerIndex);
    result.trigger_signed_vrect_minus_vout_V=vrect(triggerIndex)-vout(triggerIndex);
    result.trigger_absolute_voltage_difference_V=abs(vrect(triggerIndex)-vout(triggerIndex));
    result.trigger_inductor_current_A=iL(triggerIndex);
    result.peak_inductor_current_before_bypass_A=max(iL(1:triggerIndex));
    result.peak_inductor_current_after_bypass_A=max(iL(triggerIndex:end));
else
    result.trigger_time_s=NaN;
end
result.pwm_max=max(pwm);
result.minimum_load_resistance_ohm=min(rload);
result.pass_pwm_off=result.pwm_max<0.5;
result.pass_load_disconnected=result.minimum_load_resistance_ohm>1e8;
result.pass_all_conditions=result.triggered && ~result.timed_out ...
    && result.trigger_output_voltage_V>=safe_output_threshold_V ...
    && result.trigger_rectified_voltage_V>=safe_rectified_threshold_V ...
    && result.trigger_absolute_voltage_difference_V<=safe_voltage_difference_max_V ...
    && result.trigger_inductor_current_A<=safe_bypass_current_max_A ...
    && result.pass_pwm_off && result.pass_load_disconnected;

save(fullfile(resultDir,'safe_bypass_results.mat'), ...
    'result','t','vout','vrect','iL','pwm','rload','enable','state');
writeText(fullfile(resultDir,'safe_bypass_metrics.json'), ...
    jsonencode(result,PrettyPrint=true));

fig=figure('Color','w','Position',[100 100 1200 900]);
tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
nexttile; plot(t,vout,'LineWidth',1); hold on; plot(t,vrect,'LineWidth',0.8);
yline(safe_output_threshold_V,'--','Vo threshold'); grid on;
ylabel('Voltage (V)'); legend('V_o','V_{rect}','Location','best');
title('Isolated safe-bypass qualification');
nexttile; plot(t,vrect-vout,'LineWidth',1); hold on;
yline(safe_voltage_difference_max_V,'--'); yline(-safe_voltage_difference_max_V,'--');
grid on; ylabel('Vrect-Vo (V)');
nexttile; plot(t,iL,'LineWidth',0.8); hold on;
yline(safe_bypass_current_max_A,'--'); grid on; ylabel('i_L (A)');
nexttile; stairs(t,enable,'LineWidth',1); hold on; stairs(t,state,'LineWidth',1);
grid on; ylabel('State'); xlabel('Time (s)'); legend('bypass','state');
exportgraphics(fig,fullfile(resultDir,'safe_bypass_waveforms.png'),'Resolution',180);
close(fig);
disp(result);
close_system(modelName,0);

function ts=signal(logs,name)
element=logs.getElement(name);
assert(~isempty(element),'Missing logged signal: %s',name);
ts=element.Values;
end

function writeText(fileName,textValue)
fileId=fopen(fileName,'w'); cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,textValue,'char');
end
