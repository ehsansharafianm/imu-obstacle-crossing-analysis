function MJ = manualJointValues()
% MANUALJOINTVALUES  Hand-calculated joint max/min values (one place, both steps).
%
% Read by BOTH step7 (the joint max/min figure) and step9 (joint max/min table + ROM),
% so you edit it HERE once and it affects both. Add one SECTION PER PARTICIPANT below.
%
% Each row:
%   {Test, joint, terrain, role('Leading'/'Trailing'), stat('max'/'min'), value, sd}
%     joint   : 'hip_flexion' | 'knee_angle' | 'ankle_angle'
%     value   : a number overrides the bar;  [] = keep the AUTOMATIC (computed) value
%     sd      : a number overrides the error bar;  [] = keep automatic SD;  0 = no error bar
%
% These are REAL, manually-measured values (the automatic ones were corrupted by IMU
% heading drift). In each participant's section, note briefly HOW you computed them.

    MJ = {};

    % ===================== Participant 108 =====================
    % Right-leg IMU heading drift; hip/knee/ankle max/min re-measured by hand.
    MJ = [MJ; {
       108, 'hip_flexion',  'W1_H1', 'Trailing', 'max',  12, [];
       108, 'hip_flexion',  'W1_H3', 'Trailing', 'max',  28, [];
       108, 'hip_flexion',  'W1_H3', 'Leading',  'max',  [],  5;

       108, 'hip_flexion',  'W1_H1', 'Leading',  'min', -20, [];
       108, 'hip_flexion',  'W1_H2', 'Leading',  'min', -48, 10;
       108, 'hip_flexion',  'W1_H3', 'Leading',  'min', -30, [];
       108, 'hip_flexion',  'W1_H3', 'Trailing', 'min', -54, 10;

       108, 'knee_angle',   'W1_H2', 'Trailing', 'max',  +4,  1;
       108, 'knee_angle',   'W1_H3', 'Trailing', 'max',  [], 20;
       108, 'knee_angle',   'W1_H1', 'Trailing', 'min', -31, [];

       108, 'ankle_angle',  'W1_H2', 'Trailing', 'max',  43, 21;
       108, 'ankle_angle',  'W1_H1', 'Trailing', 'min',  -6,  4;
       108, 'ankle_angle',  'W1_H2', 'Trailing', 'min', -10, [];
    }];

    % ===================== Participant NNN =====================
    % Copy the block above, change the test number, and fill in your values.
    % MJ = [MJ; {
    %    NNN, 'hip_flexion', 'W1_H1', 'Leading', 'min', -40, [];
    % }];

end
