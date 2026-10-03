$ErrorActionPreference = "Continue"
$g = "d:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
$log = Join-Path $PSScriptRoot "_log_smoke_all.txt"
"" | Set-Content -Encoding UTF8 $log
foreach ($m in @("main_menu", "formation", "collection", "gacha", "battle", "stage_select", "adventure_data")) {
    $out = & $g --headless --path . --script ("res://tools/smoke_" + $m + ".gd") 2>&1
    $code = $LASTEXITCODE
    $out | Add-Content -Encoding UTF8 $log
    $fail = @($out | Select-String -Pattern "\[FAIL\]")
    $err = @($out | Select-String -Pattern "SCRIPT ERROR|Cannot open|Failed loading")
    $line = "{0,-16} exit={1}  FAIL={2}  ERR={3}" -f $m, $code, $fail.Count, $err.Count
    $line | Add-Content -Encoding UTF8 $log
    Write-Output $line
    foreach ($f in $fail) { "    FAIL: " + $f | Add-Content -Encoding UTF8 $log }
    foreach ($e in $err) { "    ERR : " + $e | Add-Content -Encoding UTF8 $log }
}
