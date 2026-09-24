@echo off
REM ====================================================
REM Add the folder of this script to the user PATH
REM ====================================================
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$d = '%~dp0'.TrimEnd('\');" ^
  "$p = [Environment]::GetEnvironmentVariable('Path', 'User');" ^
  "if ($null -eq $p) { $p = '' };" ^
  "if (($p -split ';') -contains $d) { Write-Host \"Already in user PATH: $d\" }" ^
  "else { [Environment]::SetEnvironmentVariable('Path', (($p.TrimEnd(';'), $d) -ne '' -join ';'), 'User'); Write-Host \"Added to user PATH: $d (open a new terminal)\" }"
pause
