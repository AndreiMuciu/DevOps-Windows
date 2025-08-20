
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
                    Start-Service -Name $service.Name
                    Write-Host "Service '$($service.Name)' started successfully." -ForegroundColor Green
                }
                catch {
                    Write-Host "Failed to start service '$($service.Name)': $_" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "Service '$($service.Name)' is running." -ForegroundColor Green
        }
    }
}
 
# Function 2: Monitor processes and resource usage
function Monitor-Processes {
    param(
        [int]$CPUThreshold = 80,
        [int]$MemoryThresholdMB = 1000,
        [int]$MonitoringSeconds = 30
    )
   
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
Export-ModuleMember -Function Manage-Services,Start-ServiceMonitor

