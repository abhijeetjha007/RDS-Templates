﻿<#
.SYNOPSIS
	This is a sample script for to deploy the required resources to execute scaling script in Microsoft Azure Automation Account.
.DESCRIPTION
	This sample script will create the scale script execution required resources in Microsoft Azure. Resources are resourcegroup,automation account,automation account runbook, 
    automation account webhook, workspace customtables and fieldnames, azure schedulerjob.
    Run this PowerShell script in adminstrator mode
    This script depends on two PowerShell modules: AzureRm and AzureAD . To install AzureRm and AzureAD modules execute the following commands. Use "-AllowClobber" parameter if you have more than one version of PowerShell modules installed.
	PS C:\>Install-Module AzureRm  -AllowClobber
    PS C:\>Install-Module AzureAD  -AllowClobber

.PARAMETER AzureADApplicationId
 Required
 Provide Azure AD Application Id and it must have 'Contributor' role at Subscription, "Azure Service Management" Api Permission and 'RDS Contributor/RDS Owner' at WVD Tenant.
.PARAMETER AzureADApplicationSecret
 Required
 Provide Azure AD Application Secret value.
.PARAMETER TenantGroupName
 Required
 Provide the name of the tenant group in the Windows Virtual Desktop deployment.
.PARAMETER TenantName
 Required
 Provide the name of the tenant in the Windows Virtual Desktop deployment.
.PARAMETER HostpoolName
 Required
 Provide the name of the WVD Host Pool.
.PARAMETER PeakLoadBalancingType
 Required
 Provide the peakLoadBalancingType. Hostpool session Load Balancing Type in Peak Hours.
.PARAMETER RecurrenceInterval
 Required
 Provide the RecurrenceInterval. Scheduler job will run recurrenceInterval basis, so provide recurrence in minutes.
.PARAMETER AADTenantId
 Required
 Provide Tenant ID of Azure Active Directory.
.PARAMETER SubscriptionId
 Required
 Provide Subscription Id of the Azure.
.PARAMETER BeginPeakTime
 Required
 Provide begin of the peak usage time.
.PARAMETER EndPeakTime
 Required
 Provide end of the peak usage time.
.PARAMETER TimeDifference
 Required
 Provide the Time difference between local time and UTC, in hours(Example: India Standard Time is +5:30).
.PARAMETER SessionThresholdPerCPU
 Required
 Provide the Maximum number of sessions per CPU threshold used to determine when a new RDSH server needs to be started.
.PARAMETER MinimumNumberOfRDSH
 Required
 Provide the Minimum number of host pool VMs to keep running during off-peak usage time.
.PARAMETER MaintenanceTagName
 Required
 Provide the name of the MaintenanceTagName.
.PARAMETER WorkspaceName
 Required
 Provide the name of the WorkspaceName.
.PARAMETER LimitSecondsToForceLogOffUser
 Required
 Provide the number of seconds to wait before forcing users to logoff. If 0, don't force users to logoff.
.PARAMETER Location
 Required
 Provide the name of the Location to create azure resources.
.PARAMETER LogOffMessageTitle
 Required
 Provide the Message title sent to a user before forcing logoff.
.PARAMETER LogOffMessageBody
 Required
 Provide the Message body to send to a user before forcing logoff.
 Example: .\scaledeployment.ps1  -AzureADApplicationId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -AzureAdApplicationSecret "Secret configured for Azure ApplicationId" -AADTenantID "Your Azure TenantID" -SubscriptionID "Your Azure SubscriptionID" -TenantGroupName "Name of the WVD Tenant Group Name" ` 
 -TenantName "Name of the WVD Tenant Name" -HostPoolName "Name of the HostPoolName" -PeakLoadBalancingType "Load balancing type in Peak hours" -MaintenanceTagName "Name of the Tag Name" -RecurrenceInterval "Repeat job every and select the appropriate period of time in minutes (Ex. 15)" ` 
 -WorkspaceName "Name of the Workspace" -BeginPeakTime "9:00" -EndPeakTime "18:00" -TimeDifference "+5:30" -SessionThresholdPerCPU 6 -MinimumNumberOfRDSH 2 -LimitSecondsToForceLogOffUser 20 –LogOffMessageTitle "System Under Maintenance" -LogOffMessageBody "Please save your work and logoff!" `
 –Location "Central US"

#>
param(
	[Parameter(mandatory = $True)]
	[string]$AzureADApplicationId,

	[Parameter(mandatory = $True)]
	[securestring]$AzureADApplicationSecret,

	[Parameter(mandatory = $True)]
	[string]$TenantGroupName,

	[Parameter(mandatory = $True)]
	[string]$TenantName,

	[Parameter(mandatory = $True)]
	[string]$HostpoolName,

	[Parameter(mandatory = $True)]
	[string]$PeakLoadBalancingType,

	[Parameter(mandatory = $True)]
	[int]$RecurrenceInterval,

	[Parameter(mandatory = $True)]
	[string]$AADTenantId,

	[Parameter(mandatory = $True)]
	[string]$SubscriptionId,

	[Parameter(mandatory = $True)]
	$BeginPeakTime,

	[Parameter(mandatory = $True)]
	$EndPeakTime,

	[Parameter(mandatory = $True)]
	$TimeDifference,

	[Parameter(mandatory = $True)]
	[int]$SessionThresholdPerCPU,

	[Parameter(mandatory = $True)]
	[int]$MinimumNumberOfRDSH,

	[Parameter(mandatory = $True)]
	[string]$MaintenanceTagName,

	[Parameter(mandatory = $True)]
	[string]$WorkspaceName,

	[Parameter(mandatory = $True)]
	[int]$LimitSecondsToForceLogOffUser,

	[Parameter(mandatory = $True)]
	[string]$Location,

	[Parameter(mandatory = $True)]
	[string]$LogOffMessageTitle,

	[Parameter(mandatory = $True)]
	[string]$LogOffMessageBody
)
#Initializing variables
$ResourceGroupName = "WVDAutoScaleResourceGroup-test01"
$AutomationAccountName = "WVDAutoScaleAutomationAccount-test01"
$RunbookName = "WVDAutoScaleRunbook"
$WebhookName = "WVDAutoScaleWebhook"
$CredentialsAssetName = "WVDAutoScaleSvcPrincipalAsset"
[System.Collections.Generic.List[System.Object]]$HostpoolNames = $HostpoolName.Split(",")

Import-Module Az.Resources
Import-Module Az.Automation
Import-Module Az.Accounts
Import-Module Az.LogicApp
Import-Module Az.OperationalInsights


$RequiredModules = @(
	[pscustomobject]@{ ModuleName = 'Az.Accounts'; ModuleVersion = '1.6.4' }
	[pscustomobject]@{ ModuleName = 'Microsoft.RDInfra.RDPowershell'; ModuleVersion = '1.0.1288.1' }
	[pscustomobject]@{ ModuleName = 'OMSIngestionAPI'; ModuleVersion = '1.6.0' }
	[pscustomobject]@{ ModuleName = 'Az.Compute'; ModuleVersion = '3.0.0' }
	[pscustomobject]@{ ModuleName = 'Az.Resources'; ModuleVersion = '1.7.1' }
	[pscustomobject]@{ ModuleName = 'Az.Automation'; ModuleVersion = '1.3.4' }
)

$RDBrokerURL = "https://rdbroker.wvd.microsoft.com"
$ScriptRepoLocation = "https://raw.githubusercontent.com/Azure/RDS-Templates/ptg-wvdautoscaling-automation/wvd-templates/wvd-scaling-script/wvdscaling-automation"
$ServicePrincipalCredentials = New-Object System.Management.Automation.PSCredential ($AzureADApplicationID,$AzureADApplicationSecret)

#Function to add Required modules to Azure Automation account
function AddingModules-toAutomationAccount {
	param(
		[Parameter(mandatory = $true)]
		[string]$ResourceGroupName,

		[Parameter(mandatory = $true)]
		[string]$AutomationAccountName,

		[Parameter(mandatory = $true)]
		[string]$ModuleName,

		# if not specified latest version will be imported
		[Parameter(mandatory = $false)]
		[string]$ModuleVersion
	)


	$Url = "https://www.powershellgallery.com/api/v2/Search()?`$filter=IsLatestVersion&searchTerm=%27$ModuleName $ModuleVersion%27&targetFramework=%27%27&includePrerelease=false&`$skip=0&`$top=40"

	[array]$SearchResult = Invoke-RestMethod -Method Get -Uri $Url
	if ($SearchResult.Count -ne 1) {
		$SearchResult = $SearchResult[0]
	}

	if (!$SearchResult) {
		Write-Error "Could not find module '$ModuleName' on PowerShell Gallery."
	}
	elseif ($SearchResult.Count -and $SearchResult.Length -gt 1) {
		Write-Error "Module name '$ModuleName' returned multiple results. Please specify an exact module name."
	}
	else {
		$PackageDetails = Invoke-RestMethod -Method Get -Uri $SearchResult.Id

		if (!$ModuleVersion) {
			$ModuleVersion = $PackageDetails.entry.properties.version
		}

		$ModuleContentUrl = "https://www.powershellgallery.com/api/v2/package/$ModuleName/$ModuleVersion"

		# Test if the module/version combination exists
		try {
			Invoke-RestMethod $ModuleContentUrl -ErrorAction Stop | Out-Null
			$Stop = $False
		}
		catch {
			Write-Error "Module with name '$ModuleName' of version '$ModuleVersion' does not exist. Are you sure the version specified is correct?"
			$Stop = $True
		}

		if (!$Stop) {

			# Find the actual blob storage location of the module
			do {
				$ActualUrl = $ModuleContentUrl
				$ModuleContentUrl = (Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Ignore).Headers.Location
			} while ($ModuleContentUrl -ne $Null)

			New-AzAutomationModule `
 				-ResourceGroupName $ResourceGroupName `
 				-AutomationAccountName $AutomationAccountName `
 				-Name $ModuleName `
 				-ContentLink $ActualUrl
		}
	}
}

#Function to check if the module is imported
function Check-IfModuleIsImported {
	param(
		[Parameter(mandatory = $true)]
		[string]$ResourceGroupName,

		[Parameter(mandatory = $true)]
		[string]$AutomationAccountName,

		[Parameter(mandatory = $true)]
		[string]$ModuleName
	)

	$IsModuleImported = $false
	while (!$IsModuleImported) {
		$IsModule = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleName -ErrorAction SilentlyContinue
		if ($IsModule.ProvisioningState -eq "Succeeded") {
			$IsModuleImported = $true
			Write-Output "Successfully $ModuleName module imported into Automation Account Modules..."
		}
		else {
			Write-Output "Waiting for to import module $ModuleName into Automation Account Modules ..."
		}
	}
}
#Authenticate to Azure
try {
	$AZAuthentication = Add-AzAccount -Subscription $SubscriptionId -Tenant $AADTenantId -Credential $ServicePrincipalCredentials -ServicePrincipal
}
catch {
	Write-Output "Failed to authenticate Azure: $($_.exception.message)"
	throw $_
	exit
}
$AzObj = $AZAuthentication | Out-String
Write-Output "Azure authentication successfully Done. Result: `n$AzObj"

#Authenticating to WVD
try {
	$WVDAuthentication = Add-RdsAccount -DeploymentUrl $RDBrokerURL -Credential $ServicePrincipalCredentials -TenantId $AADTenantId -ServicePrincipal
}
catch {
	Write-Output "Failed to authenticate WVD: $($_.exception.message)"
	exit
}
$WVDObj = $WVDAuthentication | Out-String
Write-Output "Authenticating as service principal for WVD. Result: `n$WVDObj"
$RmHostpoolnames = 0
$RmHostpoolnames = @()


foreach($HPName in $HostpoolNames){
# Check if the hostpool load balancer type is persistent.
$HostPoolInfo = Get-RdsHostPool -TenantName $TenantName -Name $HPName

if($HostpoolInfo.LoadBalancerType -eq "Persistent"){
Write-Output "$HPName hostpool configured with Persistent Load balancer.So scale script doesn't apply for this load balancertype.Scale script will execute only with these load balancer types BreadthFirst, DepthFirst. Please remove the from 'HostpoolName' input and try again"
Exit
}

$SessionHostsList = Get-RDSSessionHost -Tenantname $TenantName -HostPoolName $HPName
$SessionHostCount = ($SessionHostsList).count


#Check if the hostpool have session hosts and compare count with minimum number of rdsh value
if($SessionHostsList -eq $Null){
Write-Output "Hostpool '$HPName' doesn't have session hosts. Deployment Script will skip the basic scale script configuration for this hostpool."
$RmHostpoolnames += $HPName
}
elseif($SessionHostCount -le $MinimumNumberOfRDSH){
Write-Output "Hostpool '$HPName' has less than the minimum number of session host required."
$Confirmation = Read-Host "Do you wish to continue configuring the scale script for these available session hosts? [y/n]"
if ($Confirmation -eq 'n') {
Write-Output "Configuring the scale script is skipped for this hostpool '$HPName'."
$RmHostpoolnames += $HPName
}
else{Write-Output "Configuring the scale script for the hostpool : '$HPName' and will keep the minimum required session hosts in running mode."}
}
}

[array]$HostpoolNames = (Compare-Object -ReferenceObject $HostpoolNames -DifferenceObject $RmHostpoolnames).InputObject

#Convert to local time to UTC time
$CurrentDateTime = Get-Date
$CurrentDateTime = $CurrentDateTime.ToUniversalTime()
$HostpoolNames

#Check If the resourcegroup exist
$ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue
if (!$ResourceGroup) {
	New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force -Verbose
	Write-Output "Resource Group was created with name $ResourceGroupName"
}



#Check if the Automation Account exist
$AutomationAccount = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -ErrorAction SilentlyContinue
if (!$AutomationAccount) {
	New-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -Location $Location -Plan Free -Verbose
	Write-Output "Automation Account was created with name $AutomationAccountName"
}

#$Runbook = Get-AzAutomationRunbook -Name $RunbookName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue
#if($Runbook -eq $null){
#Creating a runbook and published the basic Scale script file
$DeploymentStatus = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateUri "$ScriptRepoLocation/runbookCreationTemplate.json" -DeploymentDebugLogLevel All -existingAutomationAccountName $AutomationAccountName -RunbookName $RunbookName -Force -Verbose
if ($DeploymentStatus.ProvisioningState -eq "Succeeded") {

	#Check if the Webhook URI exists in automation variable
	$WebhookURI = Get-AzAutomationVariable -Name "WebhookURI" -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue
	if (!$WebhookURI) {
		$Webhook = New-AzAutomationWebhook -Name $WebhookName -RunbookName $runbookName -IsEnabled $True -ExpiryTime (Get-Date).AddYears(5) -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Force
		Write-Output "Automation Account Webhook is created with name '$WebhookName'"
		$URIofWebhook = $Webhook.WebhookURI | Out-String
		New-AzAutomationVariable -Name "WebhookURI" -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Value $URIofWebhook
		Write-Output "Webhook URI stored in Azure Automation Acccount variables"
		$WebhookURI = Get-AzAutomationVariable -Name "WebhookURI" -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue
		New-AzAutomationCredential -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $CredentialsAssetName -Value $ServicePrincipalCredentials -Verbose
		Write-Output "Service principal credentials stored into Azure Automation Account credentials asset"
	}
}
#}
# Required modules imported from Automation Account Modules gallery for Scale Script execution
foreach ($Module in $RequiredModules) {
	# Check if the required modules are imported 
	$ImportedModule = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Module.ModuleName -ErrorAction SilentlyContinue
	if ($ImportedModule -eq $Null) {
		AddingModules-toAutomationAccount -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ModuleName $Module.ModuleName
		Check-IfModuleIsImported -ModuleName $Module.ModuleName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
	}
	elseif ($ImportedModule.version -ne $Module.ModuleVersion) {
		AddingModules-toAutomationAccount -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ModuleName $Module.ModuleName
		Check-IfModuleIsImported -ModuleName $Module.ModuleName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
	}
}

#Check if the log analytic workspace is exist
$LAWorkspace = Get-AzOperationalInsightsWorkspace | Where-Object { $_.Name -eq $WorkspaceName }
$WorkSpace = Get-AzOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $LAWorkspace.ResourceGroupName -Name $WorkspaceName
$LogAnalyticsPrimaryKey = $Workspace.PrimarySharedKey
$LogAnalyticsWorkspaceId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $LAWorkspace.ResourceGroupName -Name $workspaceName).CustomerId.GUID

# Create the function to create the authorization signature
function Build-Signature ($customerId,$sharedKey,$date,$contentLength,$method,$contentType,$resource)
{
	$xHeaders = "x-ms-date:" + $date
	$stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

	$bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
	$keyBytes = [Convert]::FromBase64String($sharedKey)

	$sha256 = New-Object System.Security.Cryptography.HMACSHA256
	$sha256.Key = $keyBytes
	$calculatedHash = $sha256.ComputeHash($bytesToHash)
	$encodedHash = [Convert]::ToBase64String($calculatedHash)
	$authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
	return $authorization
}

# Create the function to create and post the request
function Post-LogAnalyticsData ($customerId,$sharedKey,$body,$logType)
{
	$method = "POST"
	$contentType = "application/json"
	$resource = "/api/logs"
	$rfc1123date = [datetime]::UtcNow.ToString("r")
	$contentLength = $body.Length
	$signature = Build-Signature `
 		-customerId $customerId `
 		-sharedKey $sharedKey `
 		-Date $rfc1123date `
 		-contentLength $contentLength `
 		-FileName $fileName `
 		-Method $method `
 		-ContentType $contentType `
 		-resource $resource
	$uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

	$headers = @{
		"Authorization" = $signature;
		"Log-Type" = $logType;
		"x-ms-date" = $rfc1123date;
		"time-generated-field" = $TimeStampField;
	}

	$response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
	return $response.StatusCode

}

# Specify the name of the record type that you'll be creating
$TenantScaleLogType = "WVDTenantScale_CL"

# Specify a field with the created time for the records
$TimeStampField = Get-Date
$TimeStampField = $TimeStampField.GetDateTimeFormats(115)


# Submit the data to the API endpoint

#Custom WVDTenantScale Table
$CustomLogWVDTenantScale = @"
    [
      {
        "hostpoolName":" ",
        "logmessage": " "
      }
    ]
"@

Post-LogAnalyticsData -customerId $LogAnalyticsWorkspaceId -sharedKey $LogAnalyticsPrimaryKey -Body ([System.Text.Encoding]::UTF8.GetBytes($CustomLogWVDTenantScale)) -logType $TenantScaleLogType

#Creating Azure logic app to schedule job
foreach($HPName in $HostpoolNames){						   
$RequestBody = @{
	"RDBrokerURL" = $RDBrokerURL;
	"AADTenantId" = $AADTenantId;
	"subscriptionid" = $subscriptionid;
	"TimeDifference" = $TimeDifference;
	"TenantGroupName" = $TenantGroupName;
	"TenantName" = $TenantName;
	"HostPoolName" = $HPName;
	"peakLoadBalancingType" = $peakLoadBalancingType;
	"MaintenanceTagName" = $MaintenanceTagName;
	"LogAnalyticsWorkspaceId" = $LogAnalyticsWorkspaceId;
	"LogAnalyticsPrimaryKey" = $LogAnalyticsPrimaryKey;
	"CredentialAssetName" = $CredentialsAssetName;
	"BeginPeakTime" = $BeginPeakTime;
	"EndPeakTime" = $EndPeakTime;
	"MinimumNumberOfRDSH" = $MinimumNumberOfRDSH;
	"SessionThresholdPerCPU" = $SessionThresholdPerCPU;
	"LimitSecondsToForceLogOffUser" = $LimitSecondsToForceLogOffUser;
	"LogOffMessageTitle" = $LogOffMessageTitle;
	"AutomationAccountName" = $AutomationAccountName;
	"LogOffMessageBody" = $LogOffMessageBody }
$RequestBodyJson = $RequestBody | ConvertTo-Json
$LogicAppName = ($HPName+"_"+"Autoscale"+"_"+"Scheduler").Replace(" ","")
$SchedulerDeployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateUri "$ScriptRepoLocation/azureLogicAppCreation.json" -logicappname $LogicAppName -webhookURI $WebhookURI.Value.Replace("`n","").replace("`r","") -actionSettingsBody $RequestBodyJson -recurrenceInterval $RecurrenceInterval -DeploymentDebugLogLevel All -Verbose																		   
if ($SchedulerDeployment) {
	Write-Output "$HPName hostpool successfully configured with logic app scheduler"
}
}