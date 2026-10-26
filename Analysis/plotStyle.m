function ST = plotStyle()
% PLOTSTYLE  Shared figure template (matches the step9 ST block): Arial bold, thick
% box, grid off, blue/orange/red palette. Used by step10 and available to any step.
    ST.font      = 'Arial';
    ST.szSgtitle = 18;   % overall layout title
    ST.szTitle   = 16;   % panel title
    ST.szLabel   = 16;   % axis labels
    ST.szTick    = 13;   % tick numbers
    ST.szLegend  = 14;   % legend text
    ST.szSub     = 12;   % subtitle / annotation
    ST.boxWidth  = 2.0;  % axes box-border thickness
    ST.errW      = 1.2;  % error-bar / whisker thickness
    ST.levelW    = 2.4;  % level-walk reference line thickness
    ST.bold      = true;
    ST.gridOn    = false;
    ST.pngDPI    = 300;
    ST.colLead   = [0.20 0.40 0.80];   % blue   - Leading limb
    ST.colTrail  = [0.90 0.50 0.10];   % orange - Trailing limb
    ST.colLevel  = [0.85 0.10 0.10];   % red    - Level-walk reference
end
