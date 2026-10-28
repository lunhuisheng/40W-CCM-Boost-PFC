clear;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design';
load_system(fullfile(designDir,[modelName '.slx']));
charts={'Average_Current_Mode_Control','Boost_Power_Stage_Switched'};
chartData=struct;
for chartIndex=1:numel(charts)
    chart=find(sfroot,'-isa','Stateflow.EMChart','Path',[modelName '/' charts{chartIndex}]);
    dataItems=find(chart,'-isa','Stateflow.Data');
    rows=struct('name',{},'scope',{},'size',{},'datatype',{});
    for dataIndex=1:numel(dataItems)
        rows(dataIndex).name=dataItems(dataIndex).Name;
        rows(dataIndex).scope=dataItems(dataIndex).Scope;
        rows(dataIndex).size=dataItems(dataIndex).Props.Array.Size;
        rows(dataIndex).datatype=dataItems(dataIndex).DataType;
    end
    chartData.(charts{chartIndex})=rows;
end
diagnostic=struct('identifier',{},'message',{});
try
    set_param(modelName,'SimulationCommand','update');
    diagnostic(1).identifier='NO_ERROR';
    diagnostic(1).message='Model update succeeded.';
catch errorObject
    diagnostic(1).identifier=errorObject.identifier;
    diagnostic(1).message=errorObject.message;
    for index=1:numel(errorObject.cause)
        diagnostic(index+1).identifier=errorObject.cause{index}.identifier;
        diagnostic(index+1).message=errorObject.cause{index}.message;
    end
end
fileId=fopen(fullfile(designDir,'compile_diagnostic.json'),'w','n','UTF-8');
cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,jsonencode(diagnostic,PrettyPrint=true),'char');
fileId2=fopen(fullfile(designDir,'chart_data_diagnostic.json'),'w','n','UTF-8');
cleanup2=onCleanup(@()fclose(fileId2));
fwrite(fileId2,jsonencode(chartData,PrettyPrint=true),'char');
close_system(modelName,0);
