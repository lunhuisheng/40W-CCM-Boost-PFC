% Apply the documented precharge improvement to the current design model.

clear;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design';
modelFile=fullfile(designDir,[modelName '.slx']);
run(fullfile(designDir,'BoostPFC_Design_Init.m'));
load_system(modelFile);

controllerPath=[modelName '/Average_Current_Mode_Control'];
plantPath=[modelName '/Boost_Power_Stage_Switched'];

% Remove the earlier experimental time-input line before restoring the
% three-input plant interface.
oldPlantPorts=get_param(plantPath,'PortHandles');
if numel(oldPlantPorts.Inport)>=4
    oldTimeLine=get_param(oldPlantPorts.Inport(4),'Line');
    if oldTimeLine~=-1, delete_line(oldTimeLine); end
end

setChartScript(controllerPath,controllerCode());
setChartScript(plantPath,plantCode());
addMissingParameters(controllerPath,{ ...
    'Ts_sim','f_sw','Vout_ref','Vac_rms','Kp_v','Ki_v','Kp_i','Ki_i', ...
    'Ipk_limit','duty_min','duty_max','softstart_time','precharge_release_time'});
addMissingParameters(plantPath,{ ...
    'Ts_sim','L_boost','C_out','rL_effective','Rds_on_effective','Vf_boost_effective'});
removeChartData(plantPath,'t');
removeChartData(plantPath,'precharge_resistance');
removeChartData(plantPath,'precharge_release_time');
ensureScalarData(controllerPath,{'t','vout','vrect','iL','iRef','duty','pwm','vLoop','vRefSoft','precharge_release_time'});
ensureScalarData(plantPath,{'vin','pwm','Rload','iL','vout','iDiode','iMosfet'});

plantPorts=get_param(plantPath,'PortHandles');
if numel(plantPorts.Inport)~=3
    error('BoostPFC_Design:PortUpdateFailed','Plant interface did not return to three inputs.');
end

% Replace the direct rectified-voltage feed with a resistor-limited path
% selected by a timed bypass switch.  Only standard Simulink blocks are used.
try
    delete_line(modelName,'Rectified_Voltage_Clamp/1','Boost_Power_Stage_Switched/1');
catch
end
addIfMissing('simulink/Math Operations/Gain',[modelName '/Precharge_R_Drop'], ...
    {'Gain','precharge_resistance','Position',[500 70 555 100]});
addIfMissing('simulink/Math Operations/Sum',[modelName '/Precharge_Voltage_Subtract'], ...
    {'Inputs','+-','Position',[590 95 620 135]});
addIfMissing('simulink/Discontinuities/Saturation',[modelName '/Precharge_Voltage_Clamp'], ...
    {'LowerLimit','0','UpperLimit','inf','Position',[650 95 735 135]});
addIfMissing('simulink/Sources/Step',[modelName '/Precharge_Bypass_Command'], ...
    {'Time','precharge_release_time','Before','0','After','1','SampleTime','Ts_sim','Position',[650 35 735 65]});
addIfMissing('simulink/Signal Routing/Switch',[modelName '/Precharge_Bypass_Switch'], ...
    {'Threshold','0.5','Criteria','u2 >= Threshold','Position',[780 80 835 145]});
connectIfMissing(modelName,'Rectified_Voltage_Clamp/1','Precharge_Voltage_Subtract/1');
connectIfMissing(modelName,'iL_ADC_Delay/1','Precharge_R_Drop/1');
connectIfMissing(modelName,'Precharge_R_Drop/1','Precharge_Voltage_Subtract/2');
connectIfMissing(modelName,'Precharge_Voltage_Subtract/1','Precharge_Voltage_Clamp/1');
connectIfMissing(modelName,'Rectified_Voltage_Clamp/1','Precharge_Bypass_Switch/1');
connectIfMissing(modelName,'Precharge_Bypass_Command/1','Precharge_Bypass_Switch/2');
connectIfMissing(modelName,'Precharge_Voltage_Clamp/1','Precharge_Bypass_Switch/3');
connectIfMissing(modelName,'Precharge_Bypass_Switch/1','Boost_Power_Stage_Switched/1');

notes=find_system(modelName,'FindAll','on','Type','annotation');
if ~isempty(notes)
    text=get_param(notes(1),'Name');
    text=regexprep(text,'\nStartup protection:.*$','');
    set_param(notes(1),'Name',[text sprintf('\nStartup protection: parameterized precharge resistor and timed bypass/PWM enable.')]);
end

function addIfMissing(libraryPath,blockPath,arguments)
if getSimulinkBlockHandle(blockPath)<0
    add_block(libraryPath,blockPath,arguments{:});
end
end

function connectIfMissing(modelName,sourcePort,destinationPort)
destinationBlock=extractBefore(destinationPort,'/');
destinationNumber=str2double(extractAfter(destinationPort,'/'));
ports=get_param([modelName '/' destinationBlock],'PortHandles');
if get_param(ports.Inport(destinationNumber),'Line')==-1
    add_line(modelName,sourcePort,destinationPort,'autorouting','on');
end
end

save_system(modelName,modelFile);
close_system(modelName,0);
fprintf('Applied precharge upgrade to: %s\n',modelFile);

function setChartScript(blockPath,codeText)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
chart.Script=codeText;
end

function addMissingParameters(blockPath,names)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
existing=find(chart,'-isa','Stateflow.Data');
existingNames=arrayfun(@(item)string(item.Name),existing);
for index=1:numel(names)
    if ~any(existingNames==names{index})
        dataObject=Stateflow.Data(chart);
        dataObject.Name=names{index};
        dataObject.Scope='Parameter';
    end
end
end

function removeChartData(blockPath,name)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
dataItems=find(chart,'-isa','Stateflow.Data','Name',name);
for index=1:numel(dataItems)
    delete(dataItems(index));
end
end

function ensureScalarData(blockPath,names)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
for index=1:numel(names)
    dataItems=find(chart,'-isa','Stateflow.Data','Name',names{index});
    if ~isempty(dataItems)
        dataItems(1).Props.Array.Size='1';
        dataItems(1).DataType='Inherit: Same as Simulink';
    end
end
end

function code=controllerCode()
code=sprintf([ ...
'function [iRef,duty,pwm,vLoop,vRefSoft] = fcn(t,vout,vrect,iL)\n', ...
'%% Average-current-mode PFC control with precharge, PI anti-windup and PWM.\n', ...
'persistent intV intI carrier\n', ...
'if isempty(intV), intV=0; intI=0; carrier=0; end\n', ...
'controlTime=max(t-precharge_release_time,0);\n', ...
'vRefSoft=Vout_ref*min(controlTime/softstart_time,1);\n', ...
'eV=vRefSoft-vout; vUnsat=Kp_v*eV+intV;\n', ...
'vLoop=min(max(vUnsat,0),Ipk_limit);\n', ...
'if (vUnsat==vLoop)||(vUnsat>Ipk_limit&&eV<0)||(vUnsat<0&&eV>0), intV=intV+Ki_v*Ts_sim*eV; end\n', ...
'vPeak=max(sqrt(2)*Vac_rms,1); iRef=min(Ipk_limit,max(0,vLoop*vrect/vPeak));\n', ...
'eI=iRef-iL; dFeedforward=1-vrect/max(Vout_ref,1); dUnsat=dFeedforward+Kp_i*eI+intI;\n', ...
'duty=min(max(dUnsat,duty_min),duty_max);\n', ...
'if (dUnsat==duty)||(dUnsat>duty_max&&eI<0)||(dUnsat<duty_min&&eI>0), intI=intI+Ki_i*Ts_sim*eI; end\n', ...
'carrier=carrier+f_sw*Ts_sim; if carrier>=1, carrier=carrier-floor(carrier); end\n', ...
'if t<precharge_release_time, duty=0; pwm=0; else, pwm=double(duty>carrier); end\n']);
end

function code=plantCode()
code=sprintf([ ...
'function [iL,vout,iDiode,iMosfet] = fcn(vin,pwm,Rload)\n', ...
'%% Cycle-resolved switched boost equations.\n', ...
'persistent iState vState\n', ...
'if isempty(iState), iState=0; vState=0; end\n', ...
'loadCurrent=vState/max(Rload,1e-6);\n', ...
'if pwm>=0.5\n', ...
' di=(vin-iState*(rL_effective+Rds_on_effective))/L_boost; dv=-loadCurrent/C_out; iMosfet=iState; iDiode=0;\n', ...
'else\n', ...
' if (iState>0)||(vin>vState+Vf_boost_effective)\n', ...
'  di=(vin-vState-Vf_boost_effective-iState*rL_effective)/L_boost; iDiode=max(iState,0); dv=(iDiode-loadCurrent)/C_out;\n', ...
' else\n', ...
'  di=0; iState=0; iDiode=0; dv=-loadCurrent/C_out;\n', ...
' end\n', ...
' iMosfet=0;\n', ...
'end\n', ...
'iState=max(iState+Ts_sim*di,0); vState=max(vState+Ts_sim*dv,0); iL=iState; vout=vState;\n']);
end
