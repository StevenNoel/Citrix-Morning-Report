# Citrix-Morning-Report
This script is something that can be scheduled to be run every morning to understand what the environment looks like.  Also takes corrective actions if needed.

Tested with XA/XD 7.15LTSR and 7.18, however this should work with pretty much all 7.x versions.
# Prerequisites
You can run this on a Delivery Controller or a machine that has Studio installed.  See link for more information: https://developer-docs.citrix.com/projects/delivery-controller-sdk/en/latest/?_ga=2.136519158.731763323.1530151703-1594485461.1522783813#use-the-sdk 

# Functions
## Function ListUnregs
This Function lists Unregistered Machines.

## Function ListOff
This Function lists Powered Off machines.

## Function MaintMode
This Function lists Machines in Maintenance Mode.

## Function PowerState
This Function lists Machines that have a 'bad' Power State.  An Example might be a Power State that is 'Unknown' to the hypervisor (hosting connection) or maybe stuck in a 'Turning On' state.

## Function UpTime
This Function lists Machines that haven't been restarted in a certain period of time.

## Function DGStats
This Function lists Delivery Group statistics, including Name, # of Session, Maintenance Mode, and Functional Level

# Examples
```
.\Citrix-Morning-Report-Git.ps1 -DeliveryControllers xd7-dc01 -LogDir c:\temp
```
This Example runs the script on Delivery Controll 'xd7-dc01' and logs the results to 'C:\Temp'
```
.\Citrix-Morning-Report-Git.ps1 -DeliveryControllers xd7-dc01 -LogDir c:\temp -LogOnly
```
This Example puts the script in 'Log Mode' in which it will report everything, but won't take any action.  Such as restarting Machines or Powering them on.
```
.\Citrix-Morning-Report-Git.ps1 -DeliveryControllers xd7-dc01 -LogDir c:\temp -Email -SMTPserver smtp.domain.local -ToAddress Steve@adf.com -FromAddress Steve@adf.com
```
This uses the '-Email' Flag along with the SMTP Server and To/From Address
