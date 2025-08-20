# Team 3 - Service & Process Manager
# File: ServiceManager.ps1

# Function 1: Manage and monitor Windows services (lăsată ca în template)
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

# Function 2: Monitor processes and resource usage (implementată complet)
# Function 2: Monitor processes and resource usage
function Monitor-Processes {
    [CmdletBinding()]
    param(
        [int]$CPUThreshold = 80,          # % CPU (normalizat la nr. de procesoare logice)
        [int]$MemoryThresholdMB = 1000,   # Working Set (MB)
        [int]$MonitoringSeconds = 30
    )

    # număr procesoare logice (pt. normalizare CPU)
    $logicalProcs = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors
    if (-not $logicalProcs -or $logicalProcs -lt 1) { $logicalProcs = 1 }

    $offenders  = New-Object System.Collections.Generic.List[object]
    $allSamples = New-Object System.Collections.Generic.List[object]

    Write-Host "Monitoring processes for $MonitoringSeconds seconds (CPU>=$CPUThreshold% or Mem>=$MemoryThresholdMB MB)..." -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($sw.Elapsed.TotalSeconds -lt $MonitoringSeconds) {
        $ts = Get-Date

        # citim simultan %CPU și PID pentru corelare corectă
        $counters = $null
        try {
            $counters = Get-Counter -Counter '\Process(*)\% Processor Time','\Process(*)\ID Process' -ErrorAction Stop
        } catch {
            Write-Warning "Get-Counter failed: $($_.Exception.Message)"
            Start-Sleep -Seconds 1
            continue
        }

        $idByInstance  = @{}
        $cpuByInstance = @{}

        foreach ($s in $counters.CounterSamples) {
            $path = $s.Path  # \\PC\process(chrome#3)\% processor time
            if ($path -match '\\process\((.+?)\)\\(.+)$') {
                $instance   = $matches[1]
                $counter    = $matches[2].ToLowerInvariant()
                if ($counter -eq '% processor time') { $cpuByInstance[$instance] = [double]$s.CookedValue }
                elseif ($counter -eq 'id process')    { $idByInstance[$instance]  = [int]$s.CookedValue }
            }
        }

        # compunem rânduri per proces (sărim _Total/Idle și instanțele dispărute)
        $rows = foreach ($instance in $idByInstance.Keys) {
            if ($instance -in @('_Total','Idle')) { continue }
            $procId = $idByInstance[$instance]
            $rawCpu = if ($cpuByInstance.ContainsKey($instance)) { $cpuByInstance[$instance] } else { 0 }
            $cpuPct = [math]::Round(($rawCpu / [double]$logicalProcs), 1)

            $p = $null
            try { $p = Get-Process -Id $procId -ErrorAction Stop } catch { continue }

            [pscustomobject]@{
                TimeStamp   = $ts
                Name        = $p.ProcessName
                Id          = $p.Id
                CPUPercent  = $cpuPct
                WS_MB       = [math]::Round(($p.WorkingSet64 / 1MB), 0)
                PM_MB       = [math]::Round(($p.PrivateMemorySize64 / 1MB), 0)
                Handles     = $p.Handles
                Threads     = $p.Threads.Count
            }
        }

        $allSamples.AddRange($rows)

        # „live view”: top CPU & top mem
        $topCPU = $rows | Sort-Object CPUPercent -Descending | Select-Object Name,Id,CPUPercent,WS_MB,PM_MB -First 5
        $topMem = $rows | Sort-Object WS_MB -Descending     | Select-Object Name,Id,CPUPercent,WS_MB,PM_MB -First 5

        Clear-Host
        Write-Host ("[{0:T}] Top CPU" -f $ts) -ForegroundColor Yellow
        $topCPU | Format-Table -AutoSize
        Write-Host ("`n[{0:T}] Top Memory (WS MB)" -f $ts) -ForegroundColor Yellow
        $topMem | Format-Table -AutoSize

        # semnalăm procesele care depășesc pragurile la acest tick
        $tickOffenders = $rows | Where-Object { $_.CPUPercent -ge $CPUThreshold -or $_.WS_MB -ge $MemoryThresholdMB }
        if ($tickOffenders) {
            Write-Host "`nThreshold offenders this second:" -ForegroundColor Red
            $tickOffenders | Select-Object Name,Id,CPUPercent,WS_MB,PM_MB | Format-Table -AutoSize
            foreach ($o in $tickOffenders) { $offenders.Add($o) }
        }

        Start-Sleep -Seconds 1
    }

    $sw.Stop()
    Write-Host "`n=== Monitoring complete ===" -ForegroundColor Cyan

    # sumar: agregăm pe PID și calculăm maxime/medii + dacă au depășit pragurile
    $summary =
        $allSamples |
        Group-Object Id |
        ForEach-Object {
            $g = $_.Group
            [pscustomobject]@{
                Id             = [int]$_.Name
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

    if ($summary) {
        Write-Host "`n=== Offender Summary (exceeded thresholds) ===" -ForegroundColor Red
        $summary | Select-Object Name,Id,MaxCPUPercent,AvgCPUPercent,MaxWS_MB,MaxPM_MB,Samples,FirstSeen,LastSeen |
            Format-Table -AutoSize
    } else {
        Write-Host "No processes exceeded the configured thresholds." -ForegroundColor Green
    }

    # return pentru utilizare programatică
    [pscustomobject]@{
        AllSamples      = $allSamples
        OffenderSummary = $summary
    }
}


# Function 3: Analyze system performance (lăsată ca în template)
function Get-PerformanceData {
    param(
        [switch]$IncludeDetailedCounters
    )
   
    # Your code here
    # Hint: Use Get-Counter and Get-CimInstance
    # Gather CPU, memory, disk performance data
    # Create performance summary report
}

# Main function (nu schimbăm fluxul; doar mesaje)
function Start-ServiceMonitor {
    Write-Host "=== Service & Process Monitor Starting ===" -ForegroundColor Blue
    # Call your functions here in logical order
    # Display service status, process info, and performance data
    Write-Host "=== Service & Process Monitor Complete ===" -ForegroundColor Blue
}

# Export-ModuleMember „safe”: doar când fișierul e încărcat ca modul (.psm1)
try {
    if ($PSCommandPath -and ($PSCommandPath -like '*.psm1')) {
        Export-ModuleMember -Function Manage-Services, Monitor-Processes, Get-PerformanceData, Start-ServiceMonitor -ErrorAction Stop
    }
} catch {
    # ignorăm în .ps1; Export-ModuleMember cere modul
}
