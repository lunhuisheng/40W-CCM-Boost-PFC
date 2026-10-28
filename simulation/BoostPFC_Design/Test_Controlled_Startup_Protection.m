% Diagnostic tests for the independent cycle limiter and latched fault path.
% These forced thresholds are not nominal design results.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_ControlledStartup';
modelFile=fullfile(designDir,[modelName '.slx']);
resultDir=fullfile(designDir,'results','controlled_startup');
load_system(modelFile);

testNames={'forced_cycle_limit','forced_overcurrent_fault'};
cycleLimits=[0.20 4.00];
faultLimits=[4.50 0.20];
tests=cell(2,1);
plotData=cell(2,1);
for caseIndex=1:2
    input=Simulink.SimulationInput(modelName);
    input=input.setVariable('startup_ramp_time_s',50e-3);
    input=input.setVariable('actual_peak_cycle_limit_A',cycleLimits(caseIndex));
    input=input.setVariable('actual_peak_fault_limit_A',faultLimits(caseIndex));
    input=input.setModelParameter('StopTime','0.75');
    output=sim(input); logs=output.logsout;
    [t,iL]=values(logs,'iL');
    [~,pwm]=values(logs,'pwm');
    [~,limit]=values(logs,'current_limit_active');
    [~,fault]=values(logs,'overcurrent_fault');
    [~,state]=values(logs,'controlled_startup_state');
    [~,bypass]=values(logs,'controlled_bypass_enable');
    [~,loadEnable]=values(logs,'controlled_load_enable');
    faultIndex=find(diff(fault>0.5)==1,1,'first')+1;
    safeStateIndex=find(state==-2,1,'first');
    result=struct;
    result.name=testNames{caseIndex};
    result.forced_cycle_limit_A=cycleLimits(caseIndex);
    result.forced_fault_limit_A=faultLimits(caseIndex);
    result.current_limit_activated=any(limit>0.5);
    result.current_limit_activation_count=sum(diff(limit>0.5)==1);
    result.fault_activated=any(fault>0.5);
    result.final_state=state(end);
    result.peak_iL_A=max(iL);
    result.load_ever_connected=any(loadEnable>0.5);
    if isempty(faultIndex)
        result.fault_time_s=NaN;
        result.max_pwm_after_fault=NaN;
        result.max_load_enable_after_fault=NaN;
        result.max_bypass_enable_after_fault=NaN;
        result.fault_response_delay_s=NaN;
        result.max_pwm_in_fault_state=NaN;
        result.max_load_enable_in_fault_state=NaN;
        result.max_bypass_enable_in_fault_state=NaN;
    else
        result.fault_time_s=t(faultIndex);
        result.max_pwm_after_fault=max(pwm(faultIndex:end));
        result.max_load_enable_after_fault=max(loadEnable(faultIndex:end));
        result.max_bypass_enable_after_fault=max(bypass(faultIndex:end));
        if isempty(safeStateIndex)
            result.fault_response_delay_s=NaN;
            result.max_pwm_in_fault_state=NaN;
            result.max_load_enable_in_fault_state=NaN;
            result.max_bypass_enable_in_fault_state=NaN;
        else
            result.fault_response_delay_s=t(safeStateIndex)-t(faultIndex);
            result.max_pwm_in_fault_state=max(pwm(safeStateIndex:end));
            result.max_load_enable_in_fault_state=max(loadEnable(safeStateIndex:end));
            result.max_bypass_enable_in_fault_state=max(bypass(safeStateIndex:end));
        end
    end
    result.pass_expected_behavior = ...
        (caseIndex==1 && result.current_limit_activated && ~result.fault_activated) ...
        || (caseIndex==2 && result.fault_activated && result.final_state==-2 ...
        && result.max_pwm_in_fault_state==0 && result.max_load_enable_in_fault_state==0 ...
        && result.max_bypass_enable_in_fault_state==0);
    tests{caseIndex}=result;
    plotData{caseIndex}=struct('t',t,'iL',iL,'pwm',pwm,'limit',limit, ...
        'fault',fault,'state',state);
end
protection=struct('note','Forced thresholds for diagnostic validation only', ...
    'tests',[tests{:}]);
writeText(fullfile(resultDir,'protection_diagnostic.json'), ...
    jsonencode(protection,PrettyPrint=true));

fig=figure('Color','w','Position',[100 100 1200 900]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
for caseIndex=1:2
    nexttile; data=plotData{caseIndex};
    yyaxis left; plot(data.t,data.iL,'LineWidth',0.8); ylabel('i_L (A)');
    yyaxis right; stairs(data.t,data.limit,'LineWidth',0.8); hold on;
    stairs(data.t,data.fault,'LineWidth',0.8); stairs(data.t,data.state,'LineWidth',0.8);
    ylabel('Flags / state'); grid on; xlabel('Time (s)');
    title(testNames{caseIndex},'Interpreter','none');
    legend('i_L','cycle limit','fault','state','Location','best');
end
exportgraphics(fig,fullfile(resultDir,'protection_diagnostic.png'),'Resolution',180);
close(fig);
disp(protection);
close_system(modelName,0);

function [t,data]=values(logs,name)
element=logs.getElement(name); assert(~isempty(element),'Missing signal: %s',name);
t=element.Values.Time(:); data=element.Values.Data(:);
end

function writeText(fileName,textValue)
fileId=fopen(fileName,'w'); cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,textValue,'char');
end
