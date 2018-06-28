 Param(
                [Parameter(Mandatory=$True,Position=1)]
                [string[]]$DeliveryControllers,
                [Parameter(Mandatory=$True)]
                [string]$LogDir,
                #[ValidateSet($True,$False)]
                [Switch]$Email,
                [Switch]$LogOnly,
                [String]$SMTPserver,
                [string]$ToAddress,
                [string]$FromAddress
                )

cls
asnp citrix*

$bad=0

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
                    $unregs = Get-BrokerDesktop -AdminAddress $DeliveryController -MaxRecordCount 5000 -PowerState On -PowerActionPending $false -RegistrationState Unregistered | Sort-Object DNSName
                        foreach ($unreg in $unregs)
                            {
                                #write-host $unreg.dnsname
                                if (!($unreg.AssociatedUserNames))
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
                    $poffs = Get-BrokerDesktop -AdminAddress $DeliveryController -MaxRecordCount 5000 -PowerState Off -PowerActionPending $false -RegistrationState Unregistered | Sort-Object DNSName
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
                    $maints = Get-BrokerDesktop -AdminAddress $DeliveryController -MaxRecordCount 5000 -InMaintenanceMode $true | Sort-Object DNSName
                        foreach ($maint in $maints)
                            {
                                Write-host $maint.DNSName.Split(".",2)[0]
                            }
                    if ($maints){$script:bad=1}
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
        			                            $WMIsysuptime = (Get-Date)  [System.Management.ManagementDateTimeconverter]::ToDateTime($LastBoot)
        			                            $WMIdays = $WMIsysuptime.Days
			                                    $WMIDaystoHours = ($WMIsysuptime.Days)*24
        			                            $WMIhours = $WMIsysuptime.hours
        			                            $WMITotalHours = $WMIDaystoHours + $WMIhours
					                                if ($WMITotalHours -igt 24 -and (!($uptime.AssociatedUserNames)))
						                                {
							                                if (!($LogOnly)){New-BrokerHostingPowerAction -AdminAddress $DeliveryController -Action Reset -MachineName $uptime.HostedMachineName | Out-Null}
                                                            Write-Host $uptime.DNSName.Split(".",2)[0] has been up for $WMITotalHours Hours " (Force Restarting)"
							                                $u++
							
							
						                                }
                                                    Elseif ($WMITotalHours -igt 24 -and ($uptime.AssociatedUserNames))
                                                        {
                                                            Write-Host $uptime.DNSName.Split(".",2)[0] has been up for $WMITotalHours Hours " (Users Logged in, Can't Restart)"
                                                        }
                                            }
                                        Catch
                                            {
                                               write-host $uptime.DNSName.Split(".",2)[0] "(WMI Issues)"
                                            }
                                    
                                    }
                            }
                    if ($uptimes){$script:bad=1}
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


############ Email SMTP ###########
Function Email
    {
        if ($bad -eq '1')
            {
                $results = (Get-Content -Path $outputloc -raw)
            }
        else
            {
                $results = "Citrix is all good in the hood!"
            }
        $smtpserver = $SMTPserver
        $msg = New-Object Net.Mail.MailMessage
        $smtp = New-Object net.Mail.SmtpClient($smtpserver)
        $msg.From = $FromAddress
        $msg.To.Add($ToAddress)
        $msg.Subject = "**Citrix Morning Report**"
        $msg.body = "$results"
        #$msg.Attachments.Add($att)
        $smtp.Send($msg)
    }

############ END Email SMTP ###########

###### Call out Functions ############

ListUnregs

write-host "-"

ListOff

write-host "-"

MaintMode

write-host "-"

PowerState

write-host "-"

UpTime

write-host "-"

DGStats


####################### Get Elapsed Time of Script ###########
$lastcomp = Get-date
$diff = ($lastcomp - $firstcomp)

Write-Host This Script took $diff.Minutes minutes and $diff.Seconds seconds to complete.
Write-Host "This Script Runs at 5:30AM from ($hostname)"

##############################################################

Stop-Transcript

if ($Email) {Email}

###### END Call out Functions ############








