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
    [double]$min_bellow_radius = $top_radius,   # Minimum radius for the bellow, defaults to top_radius
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
        [double]$amplitudeFactor,      # Amplitude factor for corrugation steepness (1.0 = about 45° slopes) .6 is my favorite
        [double]$min_bellow_radius  # Minimum radius for the bellow, defaults to top_radius
    )

    Write-Verbose "Generating bellow profile with parameters:"
    Write-Verbose "  Top Radius: $top_radius"
    Write-Verbose "  Bottom Radius: $bottom_radius"
    Write-Verbose "  Total Height: $total_height"
    Write-Verbose "  Offset: $offset"
    Write-Verbose "  Min Step Height: $min_step_height"
    Write-Verbose "  Decimals: $decimals"
    Write-Verbose "  Amplitude Factor: $amplitudeFactor"
    Write-Verbose "  Minimum Bellow Radius: $min_bellow_radius"

    # Input validation
    if ($total_height - 2 * $offset -le 0) { throw "total_height must be > 2*offset." }
    if ($bottom_radius -le $top_radius) { throw "bottom_radius must be > top_radius." }
    if ($min_step_height -le 0) { throw "min_step_height must be > 0." }
    if ($amplitudeFactor -le 0) { throw "amplitudeFactor must be > 0." }
    if ($decimals -lt 0) { throw "decimals must be >= 0." } 
    if ($decimals -gt 10) { throw "decimals must be <= 10." }
    if ($offset -le 0) { throw "offset must be > 0." }
    if ($top_radius -le 0) { throw "top_radius must be > 0." }
    if ($bottom_radius -le 0) { throw "bottom_radius must be > 0." }
    if ($min_bellow_radius -le 0) { throw "min_bellow_radius must be > 0." }
    if ($amplitudeFactor -gt 1.4) { Write-Warning "Amplitude factor > 1 will result in steeper slopes." }
    if ($amplitudeFactor -lt .6) { Write-Warning "Amplitude factor < 1 will result in shallow slopes." }

    # Derived values
    $usable_height = $total_height - 2 * $offset
    $num_pairs = [math]::Floor($usable_height / (2 * $min_step_height))
    $deltaH = $usable_height / (2 * $num_pairs)
    $deltaR = ($bottom_radius - $top_radius) / ($num_pairs * 2)
    $amplitude = $amplitudeFactor * $deltaH   # amplitude tweak factor

    # Collect points
    $points = @()
    $h = $total_height
    $r = $top_radius

    # Top section
    $points += [PSCustomObject]@{ Radius = [math]::Round($r, $decimals); Height = [math]::Round($h, $decimals); Step = "TopEnd" }
    $h -= $offset
    $points += [PSCustomObject]@{ Radius = [math]::Round($r, $decimals); Height = [math]::Round($h, $decimals); Step = "TopFlat" }

    # Corrugations (start and end on a shrink)
    for ($i = $num_pairs; $i -ge 1; $i--) {
        # Shrink first
        $h -= $deltaH
        $r = [math]::Max($min_bellow_radius, $top_radius + (2 * $num_pairs - (2 * $i - 1)) * $deltaR - $amplitude)
        $points += [PSCustomObject]@{ Radius = [math]::Round($r, $decimals); Height = [math]::Round($h, $decimals); Step = "Shrink#$i" }

        # Only add Grow if it's not the final loop
        if ($i -gt 1) {
            $h -= $deltaH
            $r = $top_radius + (2 * $num_pairs - (2 * $i - 2)) * $deltaR + $amplitude
            $points += [PSCustomObject]@{ Radius = [math]::Round($r, $decimals); Height = [math]::Round($h, $decimals); Step = "Grow#$i" }
        }
    }


    # Bottom section
    $h = $offset
    $r = $bottom_radius
    $points += [PSCustomObject]@{ Radius = [math]::Round($r, $decimals); Height = [math]::Round($h, $decimals); Step = "BottomFlat" }
    $h = 0
    $points += [PSCustomObject]@{ Radius = [math]::Round($r, $decimals); Height = [math]::Round($h, $decimals); Step = "BottomStart" }

    # Output
    return $points
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
function New-ScadCode {
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
    -amplitudeFactor $amplitudeFactor `
    -min_bellow_radius $min_bellow_radius
                 
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
        New-ScadCode -points $scad_points -top_radius $top_radius -bottom_radius $bottom_radius -total_height $total_height -exportPath $exportSCAD
    }
}
else {
    Write-Error "No points generated for the bellow profile."
}