﻿#Create VM in corp.viamonstra.com
#Set Values

#Import-Modules
$TotalTime = Measure-Command {
    Import-Module C:\setup\Functions\VIAHyperV.psm1 -Force
    Import-Module C:\setup\Functions\VIADeploy.psm1 -Force
    Import-Module C:\Setup\Functions\VIAUtility.psm1 -Force
}
$TotalTime.ToString()

#Set Values
$TotalTime = Measure-Command {
    $Servers = "VIASRV001"
    #,"VIASRV002","VIASRV003","VIASRV004","VIASRV005","VIASRV006","VIASRV007","VIASRV008","VIASRV009"
    $VHDImage = "C:\Setup\VHD\WS2016 G2 Datacenter GUI RTM.vhdx"
    $ServerRole = "SCVMM2016"
}
$TotalTime.ToString()

#Set Values
$TotalTime = Measure-Command {
    $MountFolder = "C:\MountVHD"
    $AdminPassword = "P@ssw0rd"
    $DomainInstaller = "Administrator"
    $DomainName = "corp.viamonstra.com"
    $DomainAdminPassword = "P@ssw0rd"
    $VMLocation = "D:\VMs\DEMO"
    $VMMemory = 2GB
    $VMSwitchName = "UplinkSwitchNAT"
    $localCred = new-object -typename System.Management.Automation.PSCredential -argumentlist "Administrator", (ConvertTo-SecureString $adminPassword -AsPlainText -Force)
    $domainCred = new-object -typename System.Management.Automation.PSCredential -argumentlist "$($domainName)\Administrator", (ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force)
    $VIASetupCompletecmdCommand = "cmd.exe /c PowerShell.exe -Command New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest' -Name OSDeployment -Value Done -PropertyType String`ncscript.exe C:\Deploy\Scripts\LiteTouch.vbs /TaskSequenceID:HYDV10-001 /Adminpassword:$AdminPassword /DOMAINADMINDOMAIN:$DomainName /DOMAININSTALLERPASSWORD:$DomainAdminPassword /DOMAININSTALLER:$DomainInstaller /ServerRole:$ServerRole"
    $SetupRoot = "C:\Setup"
    $HydrationRoot = "C:\Setup\HYDV10\MDT"
}
$TotalTime.ToString()

#Build VMs
$TotalTime = Measure-Command {
    Foreach($Server in $Servers){
        If ((Test-VIAVMExists -VMname $Server) -eq $true){Write-Host "$Server already exist";Break}
        Write-Host "Creating $Server"
        $VM = New-VIAVM -VMName $Server -VMMem $VMMemory -VMvCPU 2 -VMLocation $VMLocation -VHDFile $VHDImage -DiskMode Diff -VMSwitchName $VMSwitchName -VMGeneration 2 -Verbose
        $VIAUnattendXML = New-VIAUnattendXML -Computername $Server -OSDAdapter0IPAddressList DHCP -DomainOrWorkGroup Domain -ProtectYourPC 1 -DNSDomain $DomainName -ProductKey 'CB7KF-BWN84-R7R2Y-793K2-8XDDG' -Verbose
        $VIASetupCompletecmd = New-VIASetupCompleteCMD -Command $VIASetupCompletecmdCommand -Verbose
        $VHDFile = (Get-VMHardDiskDrive -VMName $Server).Path
        Mount-VIAVHDInFolder -VHDfile $VHDFile -VHDClass UEFI -MountFolder $MountFolder 
        New-Item -Path "$MountFolder\Windows\Panther" -ItemType Directory -Force | Out-Null
        New-Item -Path "$MountFolder\Windows\Setup" -ItemType Directory -Force | Out-Null
        New-Item -Path "$MountFolder\Windows\Setup\Scripts" -ItemType Directory -Force | Out-Null
        Copy-Item -Path $VIAUnattendXML.FullName -Destination "$MountFolder\Windows\Panther\$($VIAUnattendXML.Name)" -Force
        Copy-Item -Path $VIASetupCompletecmd.FullName -Destination "$MountFolder\Windows\Setup\Scripts\$($VIASetupCompletecmd.Name)" -Force
        Copy-Item -Path $SetupRoot\functions -Destination $MountFolder\Setup\Functions -Container -Recurse
        Copy-Item -Path $SetupRoot\HYDV10 -Destination $MountFolder\Setup\HYDV10 -Container -Recurse
        Copy-Item -Path $HydrationRoot -Destination $MountFolder\Deploy -Container -Recurse
        Dismount-VIAVHDInFolder -VHDfile $VHDFile -MountFolder $MountFolder
        Remove-Item -Path $VIAUnattendXML.FullName
        Remove-Item -Path $VIASetupCompletecmd.FullName
        Get-VM -Name $Server -Verbose
    }
}
$TotalTime.ToString()

#Add datadrives
$TotalTime = Measure-Command {
    Foreach($server in $servers){
        New-VIAVMHarddrive -VMname $Server -NoOfDisks 3 -DiskSize 250GB
    }
}
$TotalTime.ToString()

#Mount ISO
$TotalTime = Measure-Command {
    Foreach($server in $servers){
        Get-VM -Name $server | Get-VMDvdDrive | Set-VMDvdDrive -Path D:\HYDV10ISO\HYDV10.iso
    }
}
$TotalTime.ToString()

#Add more memory
$TotalTime = Measure-Command {
    Get-VM -Name $servers | Set-VMMemory -StartupBytes 4096mb -ErrorAction Stop
}
$TotalTime.ToString()

#Deploy them
$TotalTime = Measure-Command {
    foreach($Server in $Servers){
        Write-Host "Working on $Server"
        Start-VM $Server
        Wait-VIAVMIsRunning -VMname $Server
        Wait-VIAVMHaveICLoaded -VMname $Server
        Wait-VIAVMHaveIP -VMname $Server
        Wait-VIAVMDeployment -VMname $Server
    }
}
$TotalTime.ToString()

#Wait for TaskSequence to finish
$TotalTime = Measure-Command {
    foreach($Server in $Servers){
        Write-Host "Finializing $Server"
        Wait-VIAVMTaskSequenceDeployment -VMname $Server
        #Stop-VM $Server
    }
}
$TotalTime.ToString()

BREAK

Remove-VIAVM -VMName $Servers





#Install SCVMM
$Session = New-PSSession -VMName $Servers -Credential $domainCred
$ISOFile = "C:\ISO\mu_system_center_2016_virtual_machine_manager_x64_dvd_9368503.iso"
foreach($server in $servers){
    Get-VM -Name $Server | Get-VMDvdDrive | Set-VMDvdDrive -Path $ISOFile
    Get-VM -Name $Server | Get-VMDvdDrive
}
$InstallJob = Invoke-Command -Session $Session -ScriptBlock {
    $SCVMRole = "Full"
    $SCVMMDomain = 'corp.viamonstra.com'
    $SCVMMSAccount = 'SVC_SCVMM'
    $SCVMMSAccountPW = 'P@ssw0rd'
    $SCVMMProductKey = 'NONE'
    $SCVMMUserName = 'ViaMonstra'
    $SCVMMCompanyName = 'ViaMonstra'
    $SCVMMBitsTcpPort = '8443'
    $SCVMMVmmServiceLocalAccount
    $SCVMMTopContainerName 
    $SCVMMLibraryDrive

    C:\Setup\HYDV7\Scripts\Invoke-VIAInstallSCVM.ps1 -SCVMSetup D:\setup.exe -SCVMRole Full -SCVMMDomain -SCVMMSAccount -SCVMMSAccountPW -SCVMMProductKey -SCVMMUserName -SCVMMCompanyName -SCVMMBitsTcpPort -SCVMMVmmServiceLocalAccount -SCVMMTopContainerName -SCVMMLibraryDrive -Verbose
} -AsJob
do{}until($($InstallJob.State) -eq "Completed")
foreach($Job in $InstallJob.ChildJobs){
    Write-Host ""
    Write-Host "Result on: $($Job.Location)"
    Write-Host ""
    Receive-Job -Job $Job -Keep
}
$Session | Remove-PSSession


Restart-VIAVM -VMname $Servers

foreach ($VM in $Servers){Wait-VIAVMIsRunning -VMname $VM}
foreach ($VM in $Servers){Wait-VIAVMHaveICLoaded -VMname $VM}
foreach ($VM in $Servers){Wait-VIAVMHaveIP -VMname $VM}
foreach ($VM in $Servers){Wait-VIAVMHavePSDirect -VMname $VM}



#Step 3: Use the foreach loop to create 8 hard disks for each virtual machine
Foreach($Server in $Servers){
    $VM = Get-VM -Name $Server 
    1..4|%{
        $VHDLocation = "$($vm.ConfigurationLocation)\Virtual Hard Disks"
        $VHDDisk = New-VHD -Path "$VHDLocation\datadisk$_.vhdx" -SizeBytes 120GB 
        Add-VMHardDiskDrive -VM $VM -Path $VHDDisk.Path
    }
}

#Step 3: Use the foreach loop to create 8 hard disks for each virtual machine
Foreach($Server in $Servers){
    $VM = Get-VM -Name $Server 
    5..8|%{
        $VHDLocation = "$($vm.ConfigurationLocation)\Virtual Hard Disks"
        $VHDDisk = New-VHD -Path "$VHDLocation\datadisk$_.vhdx" -SizeBytes 1200GB 
        Add-VMHardDiskDrive -VM $VM -Path $VHDDisk.Path
    }
}

#Rename the NIC's
Foreach($Server in $Servers){
    $VMNetworkAdapter = Get-VMNetworkAdapter -VMName $Server
    $VMNetworkAdapter | Set-VMNetworkAdapter -DeviceNaming On
    $VMNetworkAdapter | Rename-VMNetworkAdapter -NewName Ethernet
}

#Rename the NIC's
Foreach($Server in $Servers){
    Add-VMNetworkAdapter -VMName $Server -SwitchName $VMSwitchName -Name "Ethernet 2" -DeviceNaming On
}

#Allow teaming and spoofing
Foreach($Server in $Servers){
    Get-VMNetworkAdapter -VMName $Server | Set-VMNetworkAdapter -AllowTeaming On -MacAddressSpoofing On
}

Get-VM $Servers | Set-VMNetworkAdapter -AllowTeaming On -MacAddressSpoofing On


#Configure network on St11
Invoke-Command -VMName ST11 -ScriptBlock {
    #Create team
    $TeamName = "Team1"
    $AllNics = Get-NetAdapter | Where-Object -Property Status -EQ -Value Up
    New-NetLbfoTeam $TeamName -TeamMembers $AllNics.name -TeamNicName $TeamName -Confirm:$false -Verbose
    do{}until((Get-NetLbfoTeam).Status -eq 'Up')

    #Create switch
    $SwitchName = "UpLinkSwitch" 
    New-VMSwitch -Name $SwitchName –NetAdapterName $TeamName –MinimumBandwidthMode Weight –AllowManagementOS $True -Verbose

    #Modify virtual network adapter for managment
    $NicToConfigName = "Management"
    $Nic = Get-VMNetworkAdapter -ManagementOS
    Rename-VMNetworkAdapter -VMNetworkAdapter $Nic -NewName $NicToConfigName
    Set-VMNetworkAdapter –ManagementOS –Name $NicToConfigName –MinimumBandwidthWeight 5 -Verbose

    #Set static IP for managment network adapter
    $Nic = Get-NetAdapter -Name *Management*
    New-NetIPAddress -IPAddress 192.168.1.21 -InterfaceAlias $nic.ifAlias -DefaultGateway 192.168.1.1 -AddressFamily IPv4 -PrefixLength 24
    Set-DnsClientServerAddress -InterfaceAlias $nic.ifAlias -ServerAddresses 192.168.1.200

    #Create new LiveMig Netadapter and set static IP
    Add-VMNetworkAdapter -ManagementOS -SwitchName $SwitchName -Name LiveMig
    $Nic = Get-NetAdapter -Name *LiveMig*
    New-NetIPAddress -IPAddress 192.168.2.21 -InterfaceAlias $nic.ifAlias -AddressFamily IPv4 -PrefixLength 24

    #Create new LiveMig Netadapter and set static IP
    Add-VMNetworkAdapter -ManagementOS -SwitchName $SwitchName -Name Cluster
    $Nic = Get-NetAdapter -Name *Cluster*
    New-NetIPAddress -IPAddress 192.168.3.21 -InterfaceAlias $nic.ifAlias -AddressFamily IPv4 -PrefixLength 24
} -Credential $domainCred

Copy-VMFile -VM (Get-VM -Name ST11) -SourcePath 'C:\Setup\ISO\Windows Server 2016 Eval.ISO' -DestinationPath 'C:\Setup\ISO\Windows Server 2016 Eval.ISO' -FileSource Host -CreateFullPath -Force


Remove-VIAVM $Servers -Verbose