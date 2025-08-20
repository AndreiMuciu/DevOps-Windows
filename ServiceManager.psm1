
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
Export-ModuleMember -Function Manage-Services,Start-ServiceMonitor

