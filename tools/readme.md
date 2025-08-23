# Tools
Non-specific tools that are not inherently Rx-7 related but have purpose.

:bulb: You might need to unblock the execution of this file before running locally. Please search online for how to do this. Search terms can be: _"this file came from another computer and might be blocked"_

## generateBellows.ps1
This is a Powershell script that generates bellows for openSCAD. Afterwhich, you may export the model and print.

Usage is well-documented at the beginning of the script.

![.\generateBellows.ps1 -top_radius 7.5 -bottom_radius 60.5 -total_height 130 -offset 10 -min_step_height 7 -decimals 2 -amplitudeFactor .6 -min_bellow_radius 7.5 -exportSCAD ./shifter_bellowscls.scad -asci](generateBellows.png)

<hr>
