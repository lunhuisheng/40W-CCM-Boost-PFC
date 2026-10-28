% BoostPFC_Design_Init
% Independent parameter set for the self-designed 40 W CCM Boost PFC model.

% Electrical specification
Vac_rms = 24;                 % Active test condition [V RMS]
Vac_min = 20;                 % Input range minimum [V RMS]
Vac_max = 28;                 % Input range maximum [V RMS]
f_line = 50;                  % AC line frequency [Hz]
Vout_ref = 40;                % Regulated output target [V]
Pout_rated = 40;              % Rated output power [W]
Rload_nominal = 40;           % Rated load [ohm]
f_sw = 50e3;                  % PWM switching frequency [Hz]
L_boost = 470e-6;             % Initial boost inductance [H]
C_out = 2200e-6;              % Initial output capacitance [F]

% Simulation setup: 20 samples per switching period.
Ts_sim = 1 / (20 * f_sw);     % Fixed simulation step [s]
sim_stop_time = 1.0;          % Nominal startup + steady-state run [s]

% Non-ideal assumptions used by the first design model.
ideal_components = false;
Vf_bridge = 0.70;             % One bridge-diode forward drop [V]
Vf_boost = 0.65;              % Boost-diode forward drop [V]
Rds_on = 0.040;               % MOSFET on resistance [ohm]
rL = 0.100;                   % Boost-inductor series resistance [ohm]

if ideal_components
    Vf_bridge_effective = 0;
    Vf_boost_effective = 0;
    Rds_on_effective = 0;
    rL_effective = 0;
else
    Vf_bridge_effective = Vf_bridge;
    Vf_boost_effective = Vf_boost;
    Rds_on_effective = Rds_on;
    rL_effective = rL;
end

% Control design targets and initial gains.
% Inner current loop: plant approximation Gid(s)=Vout/(L*s).
fc_i_target = 3.0e3;          % Target current-loop crossover [Hz]
fz_i = 500;                   % Current-PI zero [Hz]
Kp_i = 2*pi*fc_i_target*L_boost/Vout_ref;
Ki_i = Kp_i*2*pi*fz_i;

% Outer voltage loop: current-amplitude-to-voltage approximation
% Gvi(s)=Vac_rms/(sqrt(2)*Cout*Vout*s).
fc_v_target = 8;              % Target voltage-loop crossover [Hz]
fz_v = 1.5;                   % Voltage-PI zero [Hz]
gvi_coefficient = Vac_rms/(sqrt(2)*C_out*Vout_ref);
Kp_v = 2*pi*fc_v_target/gvi_coefficient;
Ki_v = Kp_v*2*pi*fz_v;

% Limits and startup management.
softstart_time = 0.25;         % Linear voltage-reference ramp [s]
Ipk_limit = 4.5;               % Inductor/current-reference limit [A]
duty_min = 0.0;
duty_max = 0.95;

% Input-capacitor precharge protection.  PWM is inhibited while the series
% resistor limits the uncontrolled bridge/boost-diode charging current.
precharge_resistance = 10;     % Temporary series resistance [ohm]
precharge_release_time = 0.20; % Resistor bypass and PWM enable time [s]

% Keep the load disconnected during precharge, then connect it when the
% precharge resistor is bypassed.  A large finite resistance represents the
% open load without changing the power-stage equations.
load_enable_time = precharge_release_time;
Rload_precharge = 1e9;         % Effective open-circuit load [ohm]

% Load profile: 0=constant, 1=50%->100%, 2=100%->50%.
load_step_mode = 0;
load_step_time = 0.45;

% Analytical component checks (not simulation results).
hold_time = 10e-3;
hold_v_start = 40;
hold_v_end = 34;
C_hold_min = 2*Pout_rated*hold_time/(hold_v_start^2-hold_v_end^2);
Vout_ripple_target_pp = 2;
C_ripple_min = Pout_rated/(2*pi*f_line*Vout_ref*Vout_ripple_target_pp);

fprintf(['BoostPFC_Design parameters loaded: Vac=%.1f Vrms, Vout=%.1f V, ', ...
    'Pout=%.1f W, L=%.0f uH, C=%.0f uF.\n'], ...
    Vac_rms, Vout_ref, Pout_rated, L_boost*1e6, C_out*1e6);
fprintf('Hold-up capacitance calculation: %.1f uF required.\n', C_hold_min*1e6);

