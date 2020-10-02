<#
 __      _________ _____ __  __ 
 \ \    / /__ /_  )_   _|  \/  |
  \ \/\/ / |_ \/ /  | | | |\/| |
   \_/\_/ |___/___| |_| |_|  |_|
                               
Description:
    This script does the following:
        1. Ask AD for a List of Machines in the "Servers" OU
        2. Compares the time of each machine in the "Servers" OU against the server it is run from
            2.b. Please note, if this is not ran from a DC, this will need to be changed to ask the DC for the time instead
        3. Generates a Peer list for each machine
            3.b. The plan is to filter this peer list and send an email alert if each any point to a non-DC
        4. Sends an email if any are off by more than the called out amount of time


  ___ _   _ _  _  ___ _____ ___ ___  _  _ ___ 
 | __| | | | \| |/ __|_   _|_ _/ _ \| \| / __|
 | _|| |_| | .` | (__  | |  | | (_) | .` \__ \
 |_|  \___/|_|\_|\___| |_| |___\___/|_|\_|___/
                                    
This area calls out the functions the script will use. This must be at the top of the script. Anything changed
here will change the email that comes out and will be ran anytime the function is called.
#>

#Enter Domain Controller Name Here
$dc = ""
#Enter FROM Email Address
$sendermailaddress = ""
#Enter TO Email Address
$usermailaddress = ""
#Enter IP Address of SMTP Relay
$SMTPserver = "" 


function SendMail ($SMTPserver,$sendermailaddress,$usermailaddress,$mailBody,$badserver)
     {
 
        $smtpServer = $SMTPserver
        $msg = new-object Net.Mail.MailMessage
        $smtp = new-object Net.Mail.SmtpClient($smtpServer)
        $msg.From = $sendermailaddress
        $msg.To.Add($usermailaddress)
        $msg.Subject = "NTP Alert"
        $msg.Body = $mailBody
	    $msg.IsBodyHTML = $true
        $smtp.Send($msg)
 
     }
<#_   ___   ___ ___   _   ___ _    ___ ___ 
 \ \ / /_\ | _ \_ _| /_\ | _ ) |  | __/ __|
  \ V / _ \|   /| | / _ \| _ \ |__| _|\__ \
   \_/_/ \_\_|_\___/_/ \_\___/____|___|___/
                                           
This section starts all the variables and objects that will be used when the script runs. It also makes the 
log file.
$Logfile is the location of the logfile
$desync is the array of servers that are not in sync with the DC
$peererr is the array of servers that do not peer to a DC
$errchk is the number of error reports that will be emailed
$Domain is the Domain of the Host PC
$DN is the Domain in LDAP format
$ou is the OU we pull the servers from
$Servers is the array of servers reported from the DC
#>

#Create Log-File and Set Date the Script ran
$Logfile = "C:\Admin\Scripts\W32TM\w32tm.log"
"W32TM Script Ran: " + (Get-Date) | Out-File $Logfile
"By: " + $env:UserName | Out-File $Logfile -Append

#Variable for Servers that are not in sync
$desync = ""
#Variable for Servers with incorrect NTP Peers
$peererr = ""
#Variable to set status of email message
$errchck = 0

#Pull Domain Name from Current PC
$Domain = $env:USERDNSDOMAIN
$DN = 'DC=' + $Domain.Replace('.',',DC=')
$ou = "ou=Servers,ou=NorthernRockies,"
$ou += $DN

#GetServerNames
$Servers = (Get-ADComputer -filter {OperatingSystem -Like "Windows*"} -searchbase $ou).name

<#_    ___   ___  ___  ___ 
 | |  / _ \ / _ \| _ \/ __|
 | |_| (_) | (_) |  _/\__ \
 |____\___/ \___/|_|  |___/
This section runs the loops, this is the actual meat and potatoes of the script. We will get the servers
from the DC, pull the time from each and compare it to the DC.

Notes:
Below is the list of what each variable is in this section

$dctime = Current time of the Host PC
$time = Current time of the Remote PC
$difftime = The Difference in time between the Host and Remote PC
$tmquery = the NTP peers fo the RemotePC
#>
foreach ($Servers1 in $Servers)
{
    #Get Time from Server and from DC
    $time = Invoke-Command -ComputerName $Servers1 -ScriptBlock {Get-Date -DisplayHint Time}
    $dctime = Get-Date -DisplayHint Time
    $difftime = ([math]:: abs(($time - $dctime).totalminutes))
    
    #If difftime is off by more than the tolerance
    if ($difftime -gt .01)
    {
        "WARNING: Time Difference, Server: " + $Servers1 + " is off by: " + $difftime | Out-File $Logfile -Append
        $desync += ("<br>    " + $Servers1)
    }
          
    #Pull peers on each server
    $tmquery = Invoke-Command -ComputerName $Servers1 -ScriptBlock {(w32tm /query /peers)}
    if ($tmquery -Like $dc)
    {}
    else
    {
        $Servers1 + "Server Peer is not a Domain Controller" | Out-File $Logfile -Append
        $peererr += ("<br>    " + $Servers1)
    }
}

<#___ __  __   _   ___ _    
 | __|  \/  | /_\ |_ _| |   
 | _|| |\/| |/ _ \ | || |__ 
 |___|_|  |_/_/ \_\___|____|
         
This section builds and sends the email that reports on the findings of the loop.               
#>

$mailbody = "Below is the Status Report for the Domain Time Synchronization"
$mailbody += "<br>"

#If there are desynced servers, add them to the email
if ($desync -ne "")
{
    $mailBody += "The following servers are not in sync with the Domain Controller: "
    $mailBody += $desync
    $errchk += 1
    $mailBody += "<br>"
}

#If there are peer error servers, add them to the email
if ($peererr -ne "")
{
    $mailBody += "<br>The following servers are reporting incorrect NTP Peers: "
    $mailBody += $peererr
    $errchk += 1
    $mailBody += "<br>"
}

#If there were no errors, add this to the email
if ($errchck = 0)
{
    $mailbody += "<br> No Issues to Report."
}
#Email body complete and send
$mailbody += "<br> Status Report Complete."
SendMail $SMTPserver $sendermailaddress $usermailaddress $mailBody $badserver
