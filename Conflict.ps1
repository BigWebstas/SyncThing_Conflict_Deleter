# Grab the current PowerShell process and save its original priority
$currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
$originalPriority = $currentProcess.PriorityClass

try {
    # 1. Elevate CPU Priority to High
    Write-Host "Elevating PowerShell CPU priority to HIGH..." -ForegroundColor Cyan
    $currentProcess.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
    Write-Host "Active Priority: $($currentProcess.PriorityClass)`n" -ForegroundColor Green

    # 2. Define target directory ('.' is the current directory)
    $targetDir = "."
    
    Write-Host "Scanning for '*sync-conflict*' files in '$targetDir'..." -ForegroundColor Yellow
    Write-Host "Verbose deletion log starts below:" -ForegroundColor DarkGray
    Write-Host "------------------------------------------------"

    # 3. Recursively find and delete files with built-in Verbose logging
    Get-ChildItem -Path $targetDir -Filter "*sync-conflict*" -Recurse -File | 
        Remove-Item -Force -Verbose
        
    Write-Host "------------------------------------------------"
    Write-Host "Cleanup task completed successfully!" -ForegroundColor Green

} finally {
    # 4. Safely restore the original CPU priority even if the script is interrupted
    Write-Host "`nRestoring CPU priority back to $originalPriority..." -ForegroundColor Cyan
    $currentProcess.PriorityClass = $originalPriority
}
