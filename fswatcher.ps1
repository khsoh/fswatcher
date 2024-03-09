param ([string]$MonitorFolder = $(throw "MonitorFolder parameter is required"),
    [string]$FilesLog = $(throw "FilesLog parameter is required") )

$delayaction_ms = 2000

while (!(Test-Path $MonitorFolder)) {
    Start-Sleep -Seconds 30
}

try {
    $fsw = New-Object System.IO.FileSystemWatcher $MonitorFolder, "*" -Property @{IncludeSubdirectories = $false;NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite'}

    $timer = New-Object System.Timers.Timer
    $timer.Interval = $delayaction_ms
    $timer.AutoReset = $false


    $timeraction = {
        Write-Host "Starting delayed FileSystemWatcher (FSW) action"
        "" | Out-File $FilesLog -NoNewline
        Get-ChildItem -File "$MonitorFolder" | 
            ForEach-Object { ($_.LastWriteTime.ToString("dd/MM/yyyy hh:mm tt") + "`t" + 
                    (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLower() + 
                    "`t" + $_.Name ) } |
            Out-File $FilesLog -Append

        $timer.Stop()
        Write-Host "Completed FSW action"
    }

    # Action to respond to FileSystemWatcher events
    $action = {
        $timer.Stop()
        $timer.Start()
    }

    $handlers = . {
        Register-ObjectEvent $fsw Created -SourceIdentifier FileCreated -Action $action
        Register-ObjectEvent $fsw Deleted -SourceIdentifier FileDeleted -Action $action
        Register-ObjectEvent $fsw Changed -SourceIdentifier FileChanged -Action $action
        Register-ObjectEvent $fsw Renamed -SourceIdentifier FileRenamed -Action $action
        Register-ObjectEvent $timer -SourceIdentifier TimerAction -EventName Elapsed -Action $timeraction
    }

    $fsw.EnableRaisingEvents = $true

    Write-Host "Watching for changes to $MonitorFolder"
    $timer.Start()

    Wait-Event -SourceIdentifier "ExitScript"
} finally {
    $fsw.EnableRaisingEvents = $false
    Get-EventSubscriber -Force | Unregister-Event -Force
      
    # event handlers are technically implemented as a special kind
    # of background job, so remove the jobs now:
    $handlers | Remove-Job
      
    # properly dispose the FileSystemWatcher and Timer
    $fsw.Dispose()
    $timer.Dispose()

    Write-Warning "Event Handler disabled, monitoring ends."
}

