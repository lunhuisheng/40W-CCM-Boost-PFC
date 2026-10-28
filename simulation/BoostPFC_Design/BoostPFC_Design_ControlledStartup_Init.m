% Parameters for safe bypass plus current-limited controlled startup.

initDir=fileparts(mfilename('fullpath'));
run(fullfile(initDir,'BoostPFC_Design_SafeBypass_Init.m'));

% Delay PWM until passive current has decayed after the qualified bypass.
bypass_settle_min_time_s=1e-3;
pwm_start_current_max_A=0.10;
pwm_start_condition_hold_s=0.2e-3;
pwm_start_timeout_s=0.60;

% Only this value is swept in the three requested soft-start cases.
startup_ramp_time_s=100e-3;
startup_current_limit_initial_A=0.50;

% This is an actual measured-inductor-current limiter, distinct from the
% 4.5 A PFC current-amplitude reference limit Ipk_limit.
actual_peak_cycle_limit_A=4.00;
actual_peak_fault_limit_A=4.50;

% Connect the 40 ohm load only after closed-loop output has settled unloaded.
load_connect_voltage_tolerance_V=0.01*Vout_ref;
load_connect_stable_time_s=10e-3;
load_connect_timeout_s=0.95;

fprintf(['Controlled startup: ramp %.1f ms, current-amplitude limit ', ...
    '%.2f->%.2f A, cycle limit %.2f A, fault %.2f A.\n'], ...
    startup_ramp_time_s*1e3,startup_current_limit_initial_A,Ipk_limit, ...
    actual_peak_cycle_limit_A,actual_peak_fault_limit_A);
clear initDir;
