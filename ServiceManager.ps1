# Team 3: Service & Process Manager Lab
## Lab Duration: 90 minutes
 
### Your Mission
Create a comprehensive service and process management module that monitors Windows services, processes, and system performance.
 
---
 
## Lab Setup
 
### 1. Create Your Script File
Create a new file: `ServiceManager.ps1`
 
### 2. Starter Template
```powershell
# Team 3 - Service & Process Manager
# File: ServiceManager.ps1
 
# Function 1: Manage and monitor Windows services
function Manage-Services {
    param(
        [string[]]$CriticalServices = @("Spooler", "BITS", "Winmgmt", "EventLog"),
        [switch]$RestartStopped
    )
   
    # Your code here
    # Hint: Use Get-Service and Set-Service
    # Use if/else to check critical service status
    # Implement service start/stop logic
}
 
# Function 2: Monitor processes and resource usage
function Monitor-Processes {
    param(
        [int]$CPUThreshold = 80,
        [int]$MemoryThresholdMB = 1000,
        [int]$MonitoringSeconds = 30
    )
   $logicalProcs = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors
    if (-not $logicalProcs -or $logicalProcs -lt 1) { $logicalProcs = 1 }

    $offenders = New-Object System.Collections.Generic.List[object]
    $allSamples = New-Object System.Collections.Generic.List[object]

    Write-Host "Monitoring processes for $MonitoringSeconds seconds (CPU>=$CPUThreshold% or Mem>=$MemoryThresholdMB MB)..." -ForegroundColor Cyan
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($stopwatch.Elapsed.TotalSeconds -lt $MonitoringSeconds) {
        $timestamp = Get-Date

        # Grab both CPU and ID counters in one call so we can correlate reliably
        $counters = $null
        try {
            $counters = Get-Counter -Counter '\Process(*)\% Processor Time','\Process(*)\ID Process' -ErrorAction Stop
        } catch {
            Write-Warning "Get-Counter failed: $($_.Exception.Message)"
            Start-Sleep -Seconds 1
            continue
        }

        # Build maps: InstanceName -> ID and InstanceName -> CPU%
        $idByInstance = @{}
        $cpuByInstance = @{}

        foreach ($sample in $counters.CounterSamples) {
            $path = $sample.Path  # e.g. \\MACHINE\process(chrome#3)\% processor time
            # Extract the instance name between 'process(' and ')'
            if ($path -match '\\process\((.+?)\)\\(.+)$') {
                $instance = $matches[1]
                $counterName = $matches[2].ToLowerInvariant()
                if ($counterName -eq '% processor time') {
                    $cpuByInstance[$instance] = $sample.CookedValue
                } elseif ($counterName -eq 'id process') {
                    $idByInstance[$instance] = [int]$sample.CookedValue
                }
            }
        }

        # Merge counters -> per-process metrics (normalize CPU by logical cores)
        $rows = foreach ($instance in $idByInstance.Keys) {
            $pid = $idByInstance[$instance]
            $rawCpu = if ($cpuByInstance.ContainsKey($instance)) { [double]$cpuByInstance[$instance] } else { 0 }
            $cpuPct = [math]::Round(($rawCpu / [double]$logicalProcs), 1)

            # Some instances (_Total, Idle) or dead PIDs—skip those without a live process
            if ($instance -in @('_Total','Idle')) { continue }

            # Safely lookup process info
            $p = $null
            try { $p = Get-Process -Id $pid -ErrorAction Stop } catch { continue }

            [pscustomobject]@{
                TimeStamp   = $timestamp
                Name        = $p.ProcessName
                Id          = $p.Id
                CPUPercent  = $cpuPct
                WS_MB       = [math]::Round(($p.WorkingSet64 / 1MB), 0)
                PM_MB       = [math]::Round(($p.PrivateMemorySize64 / 1MB), 0)
                Handles     = $p.Handles
                Threads     = $p.Threads.Count
            }
        }

        # Keep all samples (useful for post-analysis)
        $allSamples.AddRange($rows)

        # Identify offenders this tick
        $tickOffenders = $rows | Where-Object { $_.CPUPercent -ge $CPUThreshold -or $_.WS_MB -ge $MemoryThresholdMB }

        # Live view: top 8 by CPU or Memory
        $topNow = $rows | Sort-Object CPUPercent -Descending | Select-Object Name,Id,CPUPercent,WS_MB,PM_MB -First 5
        $topMem = $rows | Sort-Object WS_MB -Descending | Select-Object Name,Id,CPUPercent,WS_MB,PM_MB -First 3

        Clear-Host
        Write-Host ("[{0:T}] Top CPU" -f $timestamp) -ForegroundColor Yellow
        $topNow | Format-Table -AutoSize

        Write-Host ("`n[{0:T}] Top Memory (WS MB)" -f $timestamp) -ForegroundColor Yellow
        $topMem | Format-Table -AutoSize

        if ($tickOffenders) {
            Write-Host "`nThreshold offenders this second:" -ForegroundColor Red
            $tickOffenders |
                Select-Object Name, Id, CPUPercent, WS_MB, PM_MB |
                Format-Table -AutoSize

            # Record offenders (append with timestamp)
            foreach ($o in $tickOffenders) { $offenders.Add($o) }
        }

        Start-Sleep -Seconds 1
    }

    $stopwatch.Stop()
    Write-Host "`n=== Monitoring complete ===" -ForegroundColor Cyan

    # Summarize offenders across the whole window (group by PID then compute maxes/averages)
    $summary =
        $allSamples |
        Group-Object Id |
        ForEach-Object {
            $g = $_.Group
            [pscustomobject]@{
                Id             = $_.Name
                Name           = ($g | Select-Object -First 1).Name
                MaxCPUPercent  = ($g | Measure-Object -Property CPUPercent -Maximum).Maximum
                AvgCPUPercent  = [math]::Round(($g | Measure-Object -Property CPUPercent -Average).Average, 1)
                MaxWS_MB       = ($g | Measure-Object -Property WS_MB -Maximum).Maximum
                MaxPM_MB       = ($g | Measure-Object -Property PM_MB -Maximum).Maximum
                Samples        = $g.Count
                FirstSeen      = ($g | Select-Object -First 1).TimeStamp
                LastSeen       = ($g | Select-Object -Last 1).TimeStamp
                CrossedCPUThr  = ($g | Where-Object { $_.CPUPercent -ge $CPUThreshold }).Count -gt 0
                CrossedMemThr  = ($g | Where-Object { $_.WS_MB -ge $MemoryThresholdMB }).Count -gt 0
            }
        } |
        Where-Object { $_.CrossedCPUThr -or $_.CrossedMemThr } |
        Sort-Object @{Expression='MaxCPUPercent';Descending=$true}, @{Expression='MaxWS_MB';Descending=$true}

    # Pretty print summary
    if ($summary) {
        Write-Host "`n=== Offender Summary (any sample exceeded thresholds) ===" -ForegroundColor Red
        $summary | Select-Object Name,Id,MaxCPUPercent,AvgCPUPercent,MaxWS_MB,MaxPM_MB,Samples,FirstSeen,LastSeen |
            Format-Table -AutoSize
    } else {
        Write-Host "No processes exceeded the configured thresholds." -ForegroundColor Green
    }

    # Return both raw samples and the offender summary as a hashtable for programmatic use
    return [pscustomobject]@{
        AllSamples      = $allSamples
        OffenderSummary = $summary
    }


    # Your code here
    # Hint: Use Get-Process and performance counters
    # Use while loop to monitor for specified duration
    # Identify resource-intensive processes
}
 
# Function 3: Analyze system performance
function Get-PerformanceData {
    param(
        [switch]$IncludeDetailedCounters
    )
   
    # Your code here
    # Hint: Use Get-Counter and Get-CimInstance
    # Gather CPU, memory, disk performance data
    # Create performance summary report
}
 
# Main function that orchestrates service and process monitoring
function Start-ServiceMonitor {
    Write-Host "=== Service & Process Monitor Starting ===" -ForegroundColor Blue
   
    # Call your functions here in logical order
    # Display service status, process info, and performance data
   
    Write-Host "=== Service & Process Monitor Complete ===" -ForegroundColor Blue
}
 
# Export functions for use by megascript
Export-ModuleMember -Function Manage-Services, Monitor-Processes, Get-PerformanceData, Start-ServiceMonitor
```
 
---
 
## Step-by-Step Implementation Guide
 
### Step 1: Implement Manage-Services Function (30 minutes)
 
**Requirements:**
- Check status of critical Windows services
- Use `if/else` to identify stopped or problematic services
- Implement service restart capability
- Return service status information