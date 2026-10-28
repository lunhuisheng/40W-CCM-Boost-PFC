% Initialization for the independent AC-dropout hold-up test model.

initDir=fileparts(mfilename('fullpath'));
run(fullfile(initDir,'BoostPFC_Design_LoadConnection_Init.m'));

% The automated test overrides this for the requested line phases.
hold_up_command_time_s=1.200;

fprintf('Hold-up test input gate command: %.6f s.\n',hold_up_command_time_s);
clear initDir;
