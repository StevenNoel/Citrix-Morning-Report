 <#
 Version Control:
 11/26/2018 -Added Event Viewer Function
 11/27/2018 -Corrected Maint mode function
 12/27/2018 -Added App-V Log checks
 01/15/2019 -Performance improvements in Get-RDSGracePeriod and Check-AppVLogs
 03/05/2019 -Updated Check-AppVLogs to work with App-V Scheduler 2.5 and 2.6
 03/05/2019 -Updated Get-RDSGracePeriod to not warn on 0 days, since that's now a success condition with working RDS licensing
 03/26/2019 -Added GPO Checks
 04/08/2019 -Updated App-V Checks
 06/19/2019 -updated GPO-Check function to include 'registered' for the get-brokermachine
 #>

 Param(
                [Parameter(Mandatory=$True,Position=1)]
                [string[]]$DeliveryControllers,
                [Parameter(Mandatory=$True)]
                [string]$LogDir,
                [string]$MaintTag = "None",
                #[ValidateSet($True,$False)]
                [Switch]$Email,
                [Switch]$LogOnly,
                [String]$SMTPserver,
                [string[]]$ToAddress,
                [string]$FromAddress
                )

cls
asnp citrix*

$script:bad=0

#Defines log path
$firstcomp = Get-Date
$filename = $firstcomp.month.ToString() + "-" + $firstcomp.day.ToString() + "-" + $firstcomp.year.ToString() + "-" + $firstcomp.hour.ToString() + "-" + $firstcomp.minute.ToString() + ".txt"
$outputloc = $LogDir + "\" + $filename

$hostname = hostname

Start-Transcript -Path $outputloc

Write-Host "-"

############ List Unregistered Machines ###########
Function ListUnregs
    {
        
        Write-Host "****************************************************"
       
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Unregistered Machines in " $DeliveryController ":" -ForegroundColor Green
                    $unregs = Get-BrokerMachine -AdminAddress $DeliveryController -MaxRecordCount 5000 -PowerState On -PowerActionPending $false -RegistrationState Unregistered | Sort-Object DNSName
                        foreach ($unreg in $unregs)
                            {
                                #write-host $unreg.dnsname
                                if ($unreg.SummaryState -like 'Available' -or $unreg.SummaryState -like 'Unregistered')
                                    {
                                        
                                        Try
                                            {
                                                if (!($LogOnly)){New-BrokerHostingPowerAction -AdminAddress $DeliveryController -Action Reset -MachineName $unreg.HostedMachineName | Out-Null}
                                                Write-host $unreg.DNSName.Split(".",2)[0] " (Force Restarting)"
                                            }
                                        Catch
                                            {
                                                Write-host $unreg.DNSName.Split(".",2)[0] " (Unable to Force Restart)"
                                            }
                                    }
                                else
                                    {
                                        Write-host $unreg.DNSName.Split(".",2)[0] " (Users Logged in, Can't Restart)"
                                    }
                                
                            }
                    if ($unregs){$script:bad=1}
                Write-host " "
                }#End Foreach Delivery Group
       Write-Host "****************************************************"
    }
############ END List Unregistered Machines ###########

############ List Powered Off Machines ###########
Function ListOff
    {
        
        Write-Host "****************************************************"
        
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Powered Off Machines in " $DeliveryController ":" -ForegroundColor Green
                    $poffs = Get-BrokerMachine -AdminAddress $DeliveryController -MaxRecordCount 5000 -PowerState Off -PowerActionPending $false -RegistrationState Unregistered | Sort-Object DNSName | Where-Object {($_.Tags -join(',')) -notlike "*$MaintTag*" -and $_.hostedmachinename -notlike 'ctxTEST*' -and $_.HostedMachineName -notlike 'CTXTST-*'}
                        foreach ($poff in $poffs)
                            {
                                
                                Try
                                    {
                                        
                                        if (!($LogOnly)){New-BrokerHostingPowerAction -Action TurnOn -MachineName $poff.HostedMachineName -AdminAddress $DeliveryController | Out-Null }
                                        Write-host $poff.DNSName.Split(".",2)[0] " (Powering On)"
                            
                                    }
                                Catch
                                    {
                                        Write-host $poff.DNSName.Split(".",2)[0] " (Unable to Turn On)"
                                    }
                            }
                    if ($poffs){$script:bad=1}
                Write-host " "
                }
        Write-Host "****************************************************"
    }
############ END List Powered Off Machines ###########

############ List Machines in Maint Mode ###########
Function MaintMode
    {
        Write-Host "****************************************************"
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Machines in Maint Mode in " $DeliveryController ":" -ForegroundColor Green
                    $maints = Get-BrokerDesktop -AdminAddress $DeliveryController -MaxRecordCount 5000 -IsPhysical $False | Sort-Object DNSName | Where-Object {$_.HostedMachineName -notlike 'CTXTST-*'}
                        foreach ($maint in $maints)
                            {
                                if ($maint.Tags -like "$MaintTag*")
                                    {
                                        Write-host $maint.DNSName.Split(".",2)[0] "(Tagged for Maintenance Mode)"
                                            if (!($LogOnly))    
                                                {        
                                                    Try
                                                        {
                                                            Set-BrokerMachine -MachineName $maint.MachineName -InMaintenanceMode $True
                                                        }
                                                    Catch
                                                        {
                                                            Write-host $maint.DNSName.Split(".",2)[0] "(Unable to Enable Maintenance Mode)"
                                                        }
                                                }
                                    if ($maint){$script:bad = '1'}
				    }
                                elseif ($maint.Tags -notcontains "$MaintTag*" -and $maint.InMaintenanceMode -eq "True")
                                    {
                                        Write-host $maint.DNSName.Split(".",2)[0] " (Disabling Maint Mode)"
                                        if (!($LogOnly))
                                            {
                                                
                                                Try
                                                    {
                                                        Set-BrokerMachine -MachineName $maint.MachineName -InMaintenanceMode $false
                                                    }
                                                Catch
                                                    {
                                                        Write-host $maint.DNSName.Split(".",2)[0] "(Unable to Disable Maintenance Mode"
                                                    }
                                            }
                                    }
                                
                            }
                Write-host " "
                }
      Write-Host "****************************************************"
    }
############ END List Machines in Maint Mode ###########

############ List Bad Power States ###########
Function PowerState
    {
        Write-Host "****************************************************"
        
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Machines with Bad Power States in " $DeliveryController ":" -ForegroundColor Green
                    $pstates = Get-BrokerDesktop -AdminAddress $DeliveryController -MaxRecordCount 5000 | Sort-Object DNSName
                        foreach ($pstate in $pstates)
                            {
                                if ($pstate.PowerState -ne 'Off' -and $pstate.PowerState -ne 'On' -and $pstate.PowerState -ne 'Unmanaged')
                                    {
                                        Write-host $pstate.DNSName.Split(".",2)[0] $pstate.powerstate
                                        if ($pstates){$script:bad=1}
                                    }
                            }
                    
                Write-host " "
                }
        Write-Host "****************************************************"    
    }
############ END List Bad Power States ###########

############ List Bad Up Time ###########
Function UpTime
    {
        
        Write-Host "****************************************************"
        
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Machines with Bad Uptime in " $DeliveryController ":" -ForegroundColor Green
                    $uptimes = Get-BrokerDesktop -AdminAddress $DeliveryController -MaxRecordCount 5000 -RegistrationState Registered | Where-Object PowerState -ne 'Unmanaged' | Sort-Object DNSName
                        foreach ($uptime in $uptimes)
                            {
                                #Write-host $uptime.HostedMachineName
                                if (Test-connection -ComputerName $uptime.DNSName -Count 1 -Quiet)
                                    {
                                        Try
                                            {
                                        
                                                #Write-host $uptime.HostedMachineName
                                                #Perform System Uptime Check
					                            $LastBoot = (Get-WmiObject -Class Win32_OperatingSystem -computername $uptime.DNSName).LastBootUpTime
        			                            $WMIsysuptime = (Get-Date) - [System.Management.ManagementDateTimeconverter]::ToDateTime($LastBoot)
        			                            $WMIdays = $WMIsysuptime.Days
			                                    $WMIDaystoHours = ($WMIsysuptime.Days)*24
        			                            $WMIhours = $WMIsysuptime.hours
        			                            $WMITotalHours = $WMIDaystoHours + $WMIhours
					                                if ($WMITotalHours -igt 24 -and ($uptime.SummaryState -like 'Available'))
						                                {
							                                if (!($LogOnly)){New-BrokerHostingPowerAction -AdminAddress $DeliveryController -Action Reset -MachineName $uptime.HostedMachineName | Out-Null}
                                                            Write-Host $uptime.DNSName.Split(".",2)[0] has been up for $WMITotalHours Hours " (Force Restarting)"
							                                $u++
							
										if ($uptime){$script:bad = '1'}
						                                }
                                                    Elseif ($WMITotalHours -igt 24 -and ($uptime.SummaryState -like 'InUse'))
                                                        {
                                                            Write-Host $uptime.DNSName.Split(".",2)[0] has been up for $WMITotalHours Hours " (Users Logged in, Can't Restart)"
                                                        	if ($uptime){$script:bad = '1'}
							}
                                            }
                                        Catch
                                            {
                                               write-host $uptime.DNSName.Split(".",2)[0] "(WMI Issues)"
                                            }
                                    
                                    }
                            }
                Write-host " "
                }
        Write-Host "****************************************************"    
    }
############ END List Bad Up Time ###########

############ List Delivery Group Stats ###########
Function DGStats
    {
        
        Write-Host "****************************************************"
        
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                   write-host "Delivery Group Stats in " $DeliveryController ":" -ForegroundColor Green
                    $DGs = Get-BrokerDesktopGroup -AdminAddress $DeliveryController
                        foreach ($DG in $DGs)
                            {
                                Write-Host **** Name: $DG.Name ****
                                Write-Host Sessions: $DG.Sessions
                                Write-Host Maint: $DG.InMaintenanceMode
                                Write-Host FuncLevel: $DG.MinimumFunctionalLevel
                                Write-Host "-"
                            }
                Write-host " "
                }
        Write-Host "****************************************************"    
    }
############ END List Delivery Group Stats ###########

############ List Decoms ###########
Function Decoms
    {
        Write-Host "****************************************************"
        
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Decoms in " $DeliveryController ":" -ForegroundColor Green
                    $decoms = Get-BrokerMachine -AdminAddress $DeliveryController -MaxRecordCount 5000 | Sort-Object DNSName | Where-Object {($_.Tags -join(',')) -like "*Decom*"}
                        foreach ($decom in $decoms)
                            {
                                
                                Write-host $Decom.dnsname
                            }
                    if ($decoms){$script:bad=1}
                Write-host " "
                }
        Write-Host "****************************************************" 
    }
############ END Decoms ###########

############ Load Eval ############
Function Reset-BadLoadEvaluators
    # Purpose: Some VDAs will come up from nightly reboot with Load Evaluator at 100% but 0 user sessions. These hosts will not take new sessions until this is reset, which can be done 
    # with a restart of the Citrix Desktop Service, aka BrokerAgent. This function identifies VDAs that need this and restarts the service accordingly.
    {
            Write-Host "****************************************************`n"
            Write-Host "Checking for bad load evaluator data`n" -ForegroundColor Green
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    # Evaluate current state:
                    # Get-BrokerMachine -AdminAddress $DeliveryController -SessionSupport MultiSession -Property SessionCount,LoadIndex,DNSName | Sort-Object @{Expression="LoadIndex";Descending=$True},@{Expression="SessionCount";Descending=$True}
                    Write-Host " "
                    $badMachines = @()
                    # Machines with 100% load evaluator and 0 sessions
                    try {
                        $badMachines = Get-BrokerMachine -AdminAddress $DeliveryController -SessionSupport MultiSession -Property SessionCount,LoadIndex,DNSName -ErrorAction Stop | Where-Object {($_.LoadIndex -eq 10000) -and ($_.SessionCount -eq 0)} | Select-Object -ExpandProperty DNSName
                    }
                    catch {
                        Write-Host "Unable to get data from DDC: $DeliveryController"
                        Break
                    }
                    if ($badMachines.Count -ne 0) {
                        if (!$LogOnly) {
                            Invoke-Command -ComputerName $badMachines {Restart-Service -Name BrokerAgent}
                            $badOutput = $badMachines -join ", "
                            Write-Host "Reset BrokerAgent service on VDAs:"
                            Write-Host "$badOutput"
                        }
                        else {
                            Write-Host "In logging mode - not taking action. Hosts in need of attention:"
                            Write-Host "$badOutput"
                        }
                    if ($badmachines){$script:bad=1}
		    }
                    else {
                    }
                    Write-Host " "
                }
            Write-Host "****************************************************`n"
    }
######### END Load Eval ###########

########### Check Event Viewer ############

Function Check-EventViewer
    {
        Write-Host "****************************************************"
        
            Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Event Viewer Events in " $DeliveryController ":" -ForegroundColor Green
                    
                    $beforedate = $firstcomp.AddDays(-1)
                    $events=0

                    #List of EventIDs to search for
                    $EventIDs = '1069'
                    
                    $VDAs = Get-BrokerDesktop -AdminAddress $DeliveryController -MaxRecordCount 5000 -RegistrationState Registered -IsPhysical $False | Sort-Object DNSName
                    Foreach ($VDA in $VDAs)
                        {
                            foreach ($EventID in $EventIDs)
                                {
                                    #$CheckSysEvents = Get-EventLog -ComputerName $vda.DNSName.Split(".",2)[0] -LogName 'System' -Newest 1 -InstanceId $EventID -After $beforedate -ErrorAction SilentlyContinue
                                    $CheckSysEvents = Get-WinEvent -ComputerName $vda.DNSName.Split(".",2)[0] -MaxEvents 1 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -FilterHashtable @{ LogName = "System"; StartTime = $beforedate; ID = $EventID}
                                    if ($CheckSysEvents)
                                        {
                                            if ($CheckSysEvents.ID -eq '1069')
                                                {
                                                    Write-host Name: $vda.DNSName.Split(".",2)[0] EventID: $CheckSysEvents.ID Message: $CheckSysEvents.Message
                            
                                                }
                                            $events++
                                        }
                                }
                        }

                    if ($events){$script:bad=1}
                Write-host " "
                }
        Write-Host "****************************************************" 
    }

########### END Check Event Viewer ########

############ Copy MOVE Log ###########
Function Get-MoveLogs
    {
        
        Write-Host "****************************************************"
        write-host "Running MOVE Log function (Only executes on Sunday), Share = \\NAS\Share" -ForegroundColor Green
        if ($firstcomp.DayOfWeek -like 'Sunday')
        {
            
            $MOVELog = "\\nas\share\Citrix\Logs\MOVE\" + $firstcomp.Year + "-" + $firstcomp.Month + "-" + $firstcomp.Day + "-" + "McafeeMOVEScans.csv"
            Copy-Item -Path \\servername\reports\McAfeeMOVEScans.csv -Destination $MOVELog -Force -Verbose
        }

        
        Write-Host "****************************************************"
    }
############ END Copy MOVE Log ###########

############ RDS Grace Period Check ###########
Function Get-RDSGracePeriod
    {
        Foreach ($DeliveryController in $DeliveryControllers)
                {
                    write-host "Check RDS Grace Period in" $DeliveryController ":" -ForegroundColor Green
                    $RDSVMs = Get-BrokerMachine -AdminAddress $DeliveryController -MaxRecordCount 5000 -RegistrationState Registered | Where-Object {$_.PowerState -ne 'Unmanaged' -and $_.SessionSupport -like "MultiSession"}  | Sort-Object DNSName
                        Foreach ($RDSVM in $RDSVMs)
                        {
                               $vmName = $RDSVM.DNSName.Split(".",2)[0]
                               Try
                               {
                                   #$GracePeriod = Invoke-Command -ComputerName $RDSVM.DNSName.Split(".",2)[0] -ScriptBlock {
                                   #         (Invoke-WmiMethod -PATH (gwmi -namespace root\cimv2\terminalservices -class win32_terminalservicesetting).__PATH -name GetGracePeriodDays).daysleft                 
                                   #}
                                    $GracePeriod = (Invoke-WmiMethod -Path (Get-WmiObject -Namespace "root\cimv2\terminalservices" -Class "Win32_TerminalServiceSetting" -ComputerName $vmName).__PATH -Name GetGracePeriodDays).DaysLeft
                                    If ($GracePeriod -ilt '5' -and $GracePeriod -igt '0')
                                        {
                                            Write-host "$vmName Grace Period BAD - NEEDS ATTENTION ($GracePeriod)"
					    if ($GracePeriod){$script:bad=1}
                                        }
                                        Else
                                        {
                                            #Write-host $RDSVM.DNSName.Split(".",2)[0] Grace Period Good $GracePeriod
                                        }
                               }
                               Catch
                               {
                               }

                        }
                }
        
        Write-Host "****************************************************"
    }
############ END RDS Grace Period Check ###########

############ Check GPO Application ############
## This function is reserved to check specific company type GPO settings upon boot ##
Function Check-GPO
    {
        Write-Host "****************************************************`n"
        Write-Host "Checking for successful GPO application`n" -ForegroundColor Green

        Foreach ($DeliveryController in $DeliveryControllers)
            {
                #Skip certain Citrix Sites
                if ($DeliveryController -match "DeliveryControllerName") {
                    Write-Verbose "Skipping check in Specific Site"
                    Continue
                }
                $servers = (Get-BrokerMachine -AdminAddress $DeliveryController -RegistrationState Registered -SessionSupport MultiSession).HostedMachineName

                $runTime = (Get-Date -Format s).ToString().Replace(":","-")

                $objs = Invoke-Command -ComputerName $servers -ScriptBlock {
   
                    # Checks
                    $wc = Get-Item -Path "\\localhost\d$\vdiskdif.vhdx"
                    $pfLastWrite = Get-ChildItem -Path "\\localhost\d$" -Force | Where-Object {$_.Name -eq "pagefile.sys"} | Select-Object -ExpandProperty LastWriteTime

                    $obj = [pscustomobject]@{
                        HostName = $env:COMPUTERNAME
                        WCTime = $wc.CreationTime
                        PF = $pfLastWrite
                    }

                    Return $obj
                }

                $objs | Sort-Object HostName | Format-Table HostName,WCTime,PF | Out-File "\\NAS\Share\Citrix\Logs\BootChecks\BootChecks-$runTime.log"
                Write-Host "$DeliveryController results written to \\NAS\Share\Citrix\Logs\BootChecks\BootChecks-$runTime.log"
            }
        Write-Host "`n****************************************************`n"
        }

############ End Check GPO Application ############

############ Check App-V Logs ############
Function Check-AppVLogs
    {
        $ErrorActionPreference = 'SilentlyContinue'
        Write-Host "****************************************************`n"
        Write-Host "Checking for App-V Scheduler log errors`n" -ForegroundColor Green
        Foreach ($DeliveryController in $DeliveryControllers)
            {
                $servers = Get-BrokerMachine -AdminAddress $DeliveryController -SessionSupport MultiSession
                #Skipping specific Delivery Controller
                if ($DeliveryController -match "DeliveryControllerName") {
                    Write-Verbose "Skipping App-V check in DeliveryControllerName"
                    Continue
                }
                
                foreach ($s in $servers) {
                    $serverName = $s.HostedMachineName
                    #Write-Host "Checking $serverName"
                    try {
                        $reachable = Test-Connection -ComputerName $serverName -Count 1 -Quiet
                        if ($reachable) {
                            # App-V 2.5 uses this name for the service
                            $service25 = Get-Service -ComputerName $serverName -Name "AppV5SchedulerService"
                            # App-V 2.6 uses this name for the service
                            $service26 = Get-Service -ComputerName $serverName -Name "AppVSchedulerService"
                            if (($service25 -eq $null) -and ($service26 -eq $null)) {
                                Throw
                            }
                        }
                        else {
                            Write-Host "$serverName not reachable. Continuing."
                            Continue
                        }
                    }
                    catch {
                        Write-Host "App-V Scheduler service not found on host $serverName"
                        Continue 
                    }
                    try {
                        if ($service25) {
                            # App-V 2.5 logs to this location
                            $errorCount = (Get-WinEvent -ComputerName $serverName -FilterHashtable @{LogName='App-V 5 Scheduler';ProviderName='App-V 5 Scheduler Service';Id=0} | Where-Object {$_.Message -match "CoCreateInstance"}).Count
                            if ($errorCount -gt 0) {
                                Write-Host "App-V Errors logged on $serverName. Restarting service."
                                if (!$LogOnly) {Invoke-Command -ComputerName $serverName -ScriptBlock {Restart-Service -Name AppV5SchedulerService}}
                            }
                        }
                        elseif ($service26) {
                            # App-V 2.6 logs to this location
                            $errorCount = (Get-WinEvent -ComputerName $serverName -FilterHashtable @{LogName='App-V 5 Scheduler Agent';ProviderName='App-V 5 Scheduler Service';Id=0} | Where-Object {$_.Message -match "CoCreateInstance"}).Count
                            if ($errorCount -gt 0) {
                                Write-Host "App-V Errors logged on $servername. Restarting service."
                                if (!$LogOnly) {Invoke-Command -ComputerName $serverName -ScriptBlock {Restart-Service -Name AppVSchedulerService}}
                            }
                        }
                    }
                    catch {
                        Continue
                    }  
                }  
            }
        Write-Host ""
        Write-Host "****************************************************`n"
        $ErrorActionPreference = 'Continue'
    }
############ END Check App-V Logs ############

############ Email SMTP ###########
Function Email
    {
        if ($script:bad -eq '1')
            {
                $results = (Get-Content -Path $outputloc -raw)
            }
        else
            {
                $results = "Citrix Morning Report is Clean.  Check log for details ($LogDir)."
            }
        $smtpserver = $SMTPserver
        $msg = New-Object Net.Mail.MailMessage
        $smtp = New-Object net.Mail.SmtpClient($smtpserver)
        $msg.From = $FromAddress
        Foreach ($to in $Toaddress){$msg.To.Add($to)}
        $msg.Subject = "**Citrix Morning Report**"
        $msg.body = "$results"
        #$msg.Attachments.Add($att)
        $smtp.Send($msg)
    }

############ END Email SMTP ###########



###### Call out Functions ############

ListUnregs

$now = Get-Date -Format s
write-host "- $now"

ListOff

$now = Get-Date -Format s
write-host "- $now"

MaintMode

$now = Get-Date -Format s
write-host "- $now"

PowerState

$now = Get-Date -Format s
write-host "- $now"

UpTime

$now = Get-Date -Format s
write-host "- $now"

Decoms

$now = Get-Date -Format s
write-host "- $now"

#DGStats

Reset-BadLoadEvaluators

$now = Get-Date -Format s
write-host "- $now"

#Check-EventViewer (disabling function now that we have the Get-RDSGracePeriod function)
Get-RDSGracePeriod

$now = Get-Date -Format s
write-host "- $now"

Get-MoveLogs

$now = Get-Date -Format s
write-host "- $now"

Check-GPO

$now = Get-Date -Format s
write-host "- $now"

Check-AppVLogs

####################### Get Elapsed Time of Script ###########
$lastcomp = Get-date
$diff = ($lastcomp - $firstcomp)

Write-Host This Script took $diff.Minutes minutes and $diff.Seconds seconds to complete.
Write-Host "This Script Runs at 4:00AM from ($hostname)"

##############################################################

Stop-Transcript

if ($Email) {Email}

###### END Call out Functions ############
