% Parameters for the load-connection dynamic study.
% The complete safe-bypass, 100 ms controlled-startup and PI settings are
% inherited unchanged from the verified controlled-startup initializer.

initDir=fileparts(mfilename('fullpath'));
run(fullfile(initDir,'BoostPFC_Design_ControlledStartup_Init.m'));

% 0 = direct 40 ohm, 1 = 160->80->40 ohm, 2 = linear conductance ramp.
load_connection_strategy=0;

% The 8.13 Hz averaged voltage-loop crossover corresponds to about 19.6 ms.
% Forty milliseconds gives each discrete step about two such time constants;
% the conductance ramp uses the same total 80 ms transition duration.
load_stage_interval_s=40e-3;
load_conductance_ramp_time_s=80e-3;

fprintf(['Load-connection study: strategy %d, 100 ms voltage/current ramp, ', ...
    'stage interval %.1f ms, conductance ramp %.1f ms.\n'], ...
    load_connection_strategy,load_stage_interval_s*1e3, ...
    load_conductance_ramp_time_s*1e3);
clear initDir;
