<#
.SYNOPSIS  
    Generates a bellow profile with corrugations based on specified parameters.

.DESCRIPTION
    This script creates a bellow profile with corrugations, allowing customization of parameters such as top
     and bottom radius, total height, offset, minimum step height, and amplitude factor for the corrugation
     steepness. It can output the profile in ASCII format, generate SCAD code for 3D modeling, and export the
     profile to a CSV file.
#>

param (
    [double]$top_radius = 7.5,          # Top radius of the bellow
    [double]$bottom_radius = 60.5,      # Bottom radius of the bellow
    [double]$total_height = 150,        # Overall height of the bellow
    [double]$offset = 10,               # Flat height at bottom and top
    [double]$min_step_height = 7,       # Minimum height for each corrugation step
    [int]$decimals = 2,                 # Decimal places for output rounding
    [double]$amplitudeFactor = .6,     # Amplitude factor for corrugation steepness (1.0 = about 45° slopes) .6 is my favorite
    [switch]$ascii,                     # Switch to show ASCII sketch
    [switch]$scad,                      # Switch to generate SCAD code
    [string]$exportSCAD = ".\bellow_profile.scad",  # Path to export SCAD cod
    [string]$exportCSV = ".\bellow_profile.csv"  # Path to export the profile CSV
)

function New-BellowProfile {
    [CmdletBinding()]
    param (
        [double]$top_radius,          # Top radius of the bellow
        [double]$bottom_radius,      # Bottom radius of the bellow
        [double]$total_height,        # Overall height of the bellow
        [double]$offset,               # Flat height at bottom and top
        [double]$min_step_height,       # Minimum height for each corrugation step
        [int]$decimals,                 # Decimal places for output rounding
        [double]$amplitudeFactor      # Amplitude factor for corrugation steepness (1.0 = about 45° slopes) .6 is my favorite
    )

    Write-Verbose "Generating bellow profile with parameters:"
    Write-Verbose "  Top Radius: $top_radius"
    Write-Verbose "  Bottom Radius: $bottom_radius"
    Write-Verbose "  Total Height: $total_height"
    Write-Verbose "  Offset: $offset"
    Write-Verbose "  Min Step Height: $min_step_height"
    Write-Verbose "  Decimals: $decimals"
    Write-Verbose "  Amplitude Factor: $amplitudeFactor"

    # === Validation ===
    if ($total_height - 2 * $offset -le 0) { throw "total_height must be > 2*offset." }
    if ($bottom_radius -le $top_radius) { throw "bottom_radius must be > top_radius." }

    # === Derived spans ===
    $usable_height = [double]($total_height - 2 * $offset)
    $usable_radius = [double]($bottom_radius - $top_radius)
    if ($usable_height -le 0) { throw "total_height must be > 2*offset." }
    if ($bottom_radius -le $top_radius) { throw "bottom_radius must be > top_radius." }

    # Half-step count (force odd so we END on a Shrink)
    $M = [int][math]::Floor($usable_height / $min_step_height)
    if ($M -lt 1) { throw "Not enough room for any corrugation half-steps." }
    if (($M % 2) -eq 0) { $M -= 1 }   # make it odd to finish on Shrink
    if ($M -lt 1) { $M = 1 }

    # Step sizes
    $deltaH = $usable_height / $M
    # For a ±45° (or steeper) look, use amplitude around the baseline near ΔH
    $amplitude = $deltaH * $amplitudeFactor # amplitude of corrugation, can be adjusted for more/less steepness

    # === Build profile points ===
    $private:points = @()
    function Add-Point([string]$Step, [double]$Radius, [double]$Height) {
        if ($Radius -lt $top_radius) { $Radius = $top_radius }
        if ($Radius -gt $bottom_radius) { $Radius = $bottom_radius }
        $private:points += [PSCustomObject]@{
            Radius = [math]::Round($Radius, $decimals)
            Height = [math]::Round($Height, $decimals)
            Step   = $Step
        }
        Write-Verbose ("Added Point: {0,-12} Radius: {1,-8} Height: {2,-8}" -f $Step, $Radius, $Height)
        return $private:points
    }

    # Linear baseline radius at height h in the corrugation span
    function Get-Baseline([double]$h) {
        $t = ($h - $offset) / $usable_height
        return $bottom_radius - $t * $usable_radius
    }

    # Bottom
    Add-Point "BottomStart" $bottom_radius 0
    Add-Point "BottomFlat"  $bottom_radius $offset

    # Corrugations: start with SHRINK and end with SHRINK
    $stopped = $false
    for ($k = 1; $k -le $M; $k++) {
        $h = $offset + $k * $deltaH
        $baseline = Get-Baseline $h

        # odd k => Shrink (inward), even k => Grow (outward)
        if ($k % 2 -eq 1) {
            $r = $baseline - $amplitude
            if ($r -le $top_radius + 1e-9) {
                # Land on top radius and stop — we still end on a Shrink as desired
                Add-Point ("Shrink#{0}" -f [int][math]::Ceiling($k / 2)) $top_radius $h
                $stopped = $true
                break
            }
            Add-Point ("Shrink#{0}" -f [int][math]::Ceiling($k / 2)) $r $h
        }
        else {
            $r = $baseline + $amplitude
            Add-Point ("Grow#{0}" -f [int]($k / 2)) $r $h
        }
    }

    # Top flat and end
    $topFlatH = $total_height - $offset
    # If we stopped early, ensure we don't place TopFlat below the last point
    if (-not $stopped -and $private:points[-1].Height -gt $topFlatH) { $topFlatH = $private:points[-1].Height }
    Add-Point "TopFlat" $top_radius $topFlatH
    Add-Point "TopEnd"  $top_radius $total_height

    return $private:points
}
function Export-BellowProfile {
    [CmdletBinding()]
    param (
        [array]$points,
        [string]$exportPath
    )

    if (-not (Test-Path -Path $exportPath)) {
        New-Item -Path $exportPath -ItemType File | Out-Null
    }

    $points | Export-Csv -Path $exportPath -NoTypeInformation
    Write-Host "Profile exported to $exportPath"
}
function Show-AsciiSketch {
    [CmdletBinding()]
    param (
        [array]$points
    )

    [array]::Reverse($points) # flips back to bottom-to-top for drawing
    Write-Host "`nASCII sketch (top to bottom):`n"

    $maxR = ($points | Measure-Object Radius -Maximum).Maximum
    $center = [int][math]::Ceiling($maxR) + 2

    # Scale rows directly to vertical height between successive points
    for ($pIndex = $points.Count - 1; $pIndex -gt 0; $pIndex--) {
        $p1 = $points[$pIndex]
        $p2 = $points[$pIndex - 1]

        $rows = [int][math]::Max(1, [math]::Round($p2.Height - $p1.Height))
        $r = [int][math]::Round($p1.Radius)

        $pad = " " * ($center - $r)
        $bar = "*" * (2 * $r)

        for ($k = 0; $k -lt $rows; $k++) {
            Write-Host ($pad + $bar)
        }
    }
}
function Create-ScadCode {
    [CmdletBinding()]
    param (
        [array]$points,
        [double]$top_radius,
        [double]$bottom_radius,
        [double]$total_height,
        [string]$exportPath
    )

    $scadCode = @"
// Generated SCAD code for a bellow profile with corrugations
// Thanks to the original author for the design inspiration
// This code is based on the bellow design from Thingiverse:
// hegner_bellows - http://thingiverse.com/thing:4614117
// 
// Contributor: Yeti13b
// https://github.com/yeti13b
//
// - change wallThickness if needed for your nozzle/filament choice
//   (goal was 2 perimiters to ensure a reasonably airtight result)

intRadiusTop    = $top_radius;   // internal radius at top
intRadiusBot    = $bottom_radius;   // internal radius at bottom
wallThickness   = 1;    // 1mm --> 2 perimeters works great with TPU
lipThickness    = 1;    // extra thickness for the top/bottom lips
lipHeight       = 2;    // height of top/bottom lips

height          = $total_height;  // overall height

bellowsIntPts = [   // internal points of the bellow shape
    [0,     height],
    [intRadiusTop,   height],
    $($points -join "`r`n    ")
    [intRadiusBot,   0], 
    [0,     0]
];
        
lipB = [    // points for the add-on bottom lip
    [0, 0],                                                                 //  +--+
    [0, lipHeight],                                                         //  |  |
    [intRadiusBot + wallThickness + lipThickness, lipHeight],               //  +--+
    [intRadiusBot + wallThickness + lipThickness, 0]
];
    
lipT = [    // points for the add-on top lip (has taper to avoid overhang)
    [0, height],                                                            //  +--+
    [intRadiusTop + wallThickness + lipThickness, height],                  //  |  |
    [intRadiusTop + wallThickness + lipThickness, height - lipHeight],      //  |  +
    [intRadiusTop + wallThickness, height - lipHeight - 1.5 * lipThickness],//  | /
    [0, height - lipHeight - 1.5 * lipThickness]                            //  +
];

module bellows(sweep=360) {
    rotate_extrude(angle=sweep, `$fn=180)
        difference() { 
            union() {   // form exterior shape
                polygon(lipT);
                polygon(lipB);
                translate([wallThickness, 0, 0])  polygon(bellowsIntPts);
            }
            polygon(bellowsIntPts);     // subtract internal shape
        }
}


bellows();

// uncommented next line of code to also show the sidewall construction (make sure you zoom out, as the cutaway model is shown next to the complete model

//translate ([3*intRadiusBot,0,0]) bellows(270);  
"@

    Set-Content -Path $exportPath -Value $scadCode
}

$bellow_points = New-BellowProfile -top_radius $top_radius `
    -bottom_radius $bottom_radius `
    -total_height $total_height `
    -offset $offset `
    -min_step_height $min_step_height `
    -decimals $decimals `
    -amplitudeFactor $amplitudeFactor

[array]::Reverse($bellow_points) # flips the table to show from top to bottom

                 
if ($bellow_points) {
    # Output the profile points
    Write-Host "`nProfile Points (Top to Bottom):"
    $bellow_points | Format-Table -AutoSize

    # Draw the ASCII sketch
    if ($ascii) {
        Show-AsciiSketch -points $bellow_points
    }
    
    # Export the profile to CSV
    if ($exportPath) {
        Export-BellowProfile -points $bellow_points -exportPath $exportCSV 
    }
    # Generate SCAD code
    if ($scad) {
        $scad_points = $bellow_points | ForEach-Object { Write-Output "[$($_.radius), $($_.Height)]," }
        Create-ScadCode -points $scad_points -top_radius $top_radius -bottom_radius $bottom_radius -total_height $total_height -exportPath $exportSCAD
    }
}
else {
    Write-Error "No points generated for the bellow profile."
}