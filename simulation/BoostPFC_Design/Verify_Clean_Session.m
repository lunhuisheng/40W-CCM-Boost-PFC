% Verify that the saved model initializes and runs from an unrelated folder.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelFile=fullfile(designDir,'BoostPFC_Design.slx');
restoredefaultpath;
rehash toolboxcache;
cd(tempdir);
assert(isempty(which('BoostPFC_Design_Init')), ...
    'Design directory unexpectedly remains on MATLAB path.');
load_system(modelFile);
sim('BoostPFC_Design');
statusFile=fullfile(designDir,'results','clean_session_verification.txt');
fileId=fopen(statusFile,'w');
cleanup=onCleanup(@()fclose(fileId));
fprintf(fileId,'PASS\nModel loaded and simulated from: %s\n',pwd);
fprintf(fileId,'InitFcn: %s\n',get_param('BoostPFC_Design','InitFcn'));
close_system('BoostPFC_Design',0);
