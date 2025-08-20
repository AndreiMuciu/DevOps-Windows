
# Function 1: Manage and monitor Windows services
function Manage-Services {
    param(
        [string[]]$CriticalServices = @("Spooler", "BITS", "Winmgmt", "EventLog"),
        [switch]$RestartStopped
    )
   
    # Warn if not running elevated (some services require admin to start/stop)
    try {
        $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
        $wp = New-Object Security.Principal.WindowsPrincipal($wi)
        if (-not $wp.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
            Write-Warning "You are not running PowerShell as Administrator. Some service operations may fail."
        }
    } catch { }

    # Your code here
    # Hint: Use Get-Service and Set-Service
    # Use if/else to check critical service status
    # Implement service start/stop logic

    foreach ($serviceName in $CriticalServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if ($null -eq $service) {
            Write-Host "Service '$serviceName' not found." -ForegroundColor Yellow
            continue
        }

        Write-Host "Service '$($service.Name)' is currently: $($service.Status)"

        if ($service.Status -ne 'Running') {
            Write-Host "Service '$($service.Name)' is stopped!" -ForegroundColor Red
            if ($RestartStopped) {
                try {
                    # If startup type is Disabled, try set it to Manual before starting
                    try {
                        if ($service.StartType -eq 'Disabled') {
                            Write-Host "Service '$($service.Name)' is Disabled. Changing StartupType to Manual..." -ForegroundColor Yellow
                            Set-Service -Name $service.Name -StartupType Manual -ErrorAction Stop
                        }
                    } catch {
                        throw "Unable to change StartupType for '$($service.Name)': $($_.Exception.Message)"
                    }

                    # Attempt start with terminating error behavior
                    Start-Service -Name $service.Name -ErrorAction Stop

                    # Verify it actually reached Running state (up to 10s)
                    $svc = Get-Service -Name $service.Name -ErrorAction Stop
                    try { $svc.WaitForStatus('Running', (New-TimeSpan -Seconds 10)) } catch { }
                    $svc.Refresh()
                    if ($svc.Status -eq 'Running') {
                        Write-Host "Service '$($service.Name)' started successfully." -ForegroundColor Green
                    } else {
                        throw "Service '$($service.Name)' did not reach Running state (current: $($svc.Status))."
                    }
                }
                catch {
                    Write-Host "Failed to start service '$($service.Name)': $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "Service '$($service.Name)' is running." -ForegroundColor Green
        }
    }
}
 
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

 
# Function 3: Analyze system performance
function Get-PerformanceData {
    param(
        [switch]$IncludeDetailedCounters
    )
   
    Write-Host "=== System Performance Analysis ===" -ForegroundColor Cyan
    
    $performanceData = @{}
    
    try {
        # Get CPU usage
        $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 3
        $avgCpuUsage = ($cpuCounter.CounterSamples | Measure-Object -Property CookedValue -Average).Average
        $performanceData.CPU = [math]::Round($avgCpuUsage, 2)
        
        $memory = Get-CimInstance -ClassName Win32_OperatingSystem
        $totalMemoryGB = [math]::Round($memory.TotalVisibleMemorySize / 1MB, 2)
        $freeMemoryGB = [math]::Round($memory.FreePhysicalMemory / 1MB, 2)
        $usedMemoryGB = [math]::Round($totalMemoryGB - $freeMemoryGB, 2)
        $memoryUsagePercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 2)
        
        $performanceData.Memory = @{
            Total = $totalMemoryGB
            Used = $usedMemoryGB
            Free = $freeMemoryGB
            UsagePercent = $memoryUsagePercent
        }
        
        $diskCounters = Get-Counter '\PhysicalDisk(_Total)\% Disk Time' -SampleInterval 1 -MaxSamples 2
        $avgDiskUsage = ($diskCounters.CounterSamples | Measure-Object -Property CookedValue -Average).Average
        $performanceData.Disk = [math]::Round($avgDiskUsage, 2)
        
        Write-Host "CPU Usage: $($performanceData.CPU)%" -ForegroundColor Yellow
        Write-Host "Memory Usage: $($performanceData.Memory.UsagePercent)% ($($performanceData.Memory.Used)GB / $($performanceData.Memory.Total)GB)" -ForegroundColor Yellow
        Write-Host "Disk Usage: $($performanceData.Disk)%" -ForegroundColor Yellow
        
        if ($IncludeDetailedCounters) {
            Write-Host "`n=== Detailed Performance Counters ===" -ForegroundColor Cyan
            
            $networkCounters = Get-Counter '\Network Interface(*)\Bytes Total/sec' -SampleInterval 1 -MaxSamples 2
            $totalNetworkBytes = ($networkCounters.CounterSamples | Where-Object {$_.InstanceName -ne "_Total" -and $_.InstanceName -notlike "*Loopback*"} | 
                                Measure-Object -Property CookedValue -Sum).Sum
            $performanceData.NetworkBytesPerSec = [math]::Round($totalNetworkBytes, 2)
            Write-Host "Network Activity: $($performanceData.NetworkBytesPerSec) bytes/sec" -ForegroundColor Green
            
            $processCount = (Get-Process).Count
            $performanceData.ProcessCount = $processCount
            Write-Host "Running Processes: $processCount" -ForegroundColor Green
            
            $uptime = (Get-Date) - (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
            $performanceData.Uptime = "$($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"
            Write-Host "System Uptime: $($performanceData.Uptime)" -ForegroundColor Green
            
            $topProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 Name, CPU, WorkingSet
            $performanceData.TopProcesses = $topProcesses
            Write-Host "`nTop 5 CPU Consuming Processes:" -ForegroundColor Magenta
            $topProcesses | ForEach-Object {
                $cpuTime = if ($_.CPU) { [math]::Round($_.CPU, 2) } else { "N/A" }
                $memoryMB = [math]::Round($_.WorkingSet / 1MB, 2)
                Write-Host "  $($_.Name): CPU=$cpuTime, Memory=$memoryMB MB" -ForegroundColor White
            }
        }
        
        Write-Host "`n=== Performance Analysis Complete ===" -ForegroundColor Green
        return $performanceData
        
    } catch {
        Write-Host "Error gathering performance data: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
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

