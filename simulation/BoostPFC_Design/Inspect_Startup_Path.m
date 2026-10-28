% Read-only inspection of the current startup signal path.

clear;
bdclose('all');
designDir = fileparts(mfilename('fullpath'));
modelName = 'BoostPFC_Design';
modelFile = fullfile(designDir, [modelName '.slx']);
load_system(modelFile);

blockNames = { ...
    'Time','AC_Source_20_to_28_Vrms','Bridge_Rectifier_abs','Rectified_Voltage_Clamp', ...
    'Precharge_R_Drop','Precharge_Voltage_Subtract','Precharge_Voltage_Clamp', ...
    'Precharge_Bypass_Command','Precharge_Bypass_Switch', ...
    'Load_Profile','Average_Current_Mode_Control','Boost_Power_Stage_Switched'};

inspection = struct;
inspection.model_file = modelFile;
inspection.init_fcn = get_param(modelName,'InitFcn');
inspection.blocks = struct;
for blockIndex = 1:numel(blockNames)
    blockName = blockNames{blockIndex};
    blockPath = [modelName '/' blockName];
    assert(getSimulinkBlockHandle(blockPath) >= 0, 'Missing block: %s', blockPath);
    block = struct;
    block.type = get_param(blockPath,'BlockType');
    block.connections = connections(blockPath);
    inspection.blocks.(matlab.lang.makeValidName(blockName)) = block;
end

currentData = load(fullfile(designDir,'results','nominal_24Vac_results.mat'), ...
    't','vrect','vout','iL','rload');
passivePeak = sqrt(2)*24 - 2*0.70 - 0.65;
inspection.passive_precharge = struct;
inspection.passive_precharge.derived_ceiling_V = passivePeak;
inspection.passive_precharge.voltage_at_200ms_V = ...
    currentData.vout(find(currentData.t<0.20,1,'last'));
inspection.passive_precharge.peak_current_before_200ms_A = ...
    max(currentData.iL(currentData.t<0.20));
inspection.passive_precharge.load_before_200ms_ohm = ...
    currentData.rload(find(currentData.t<0.20,1,'last'));

outputFile = fullfile(designDir,'startup_path_inspection.json');
fileId = fopen(outputFile,'w');
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId,jsonencode(inspection,PrettyPrint=true),'char');
close_system(modelName,0);
fprintf('STARTUP_PATH_INSPECTION_DONE\n%s\n',outputFile);

function rows = connections(blockPath)
ports = get_param(blockPath,'PortHandles');
rows = struct('direction',{},'port',{},'peer',{});
rowIndex = 0;
directions = {'Inport','Outport'};
for directionIndex = 1:numel(directions)
    direction = directions{directionIndex};
    handles = ports.(direction);
    for portIndex = 1:numel(handles)
        lineHandle = get_param(handles(portIndex),'Line');
        rowIndex = rowIndex+1;
        rows(rowIndex).direction = direction;
        rows(rowIndex).port = portIndex;
        rows(rowIndex).peer = linePeer(lineHandle,direction);
    end
end
end

function peer = linePeer(lineHandle,direction)
if lineHandle == -1
    peer = '<unconnected>';
    return;
end
if strcmp(direction,'Inport')
    handle = get_param(lineHandle,'SrcBlockHandle');
else
    handle = get_param(lineHandle,'DstBlockHandle');
    if numel(handle)>1, handle=handle(1); end
end
if isempty(handle) || handle == -1
    peer = '<unconnected>';
else
    peer = getfullname(handle);
end
end
