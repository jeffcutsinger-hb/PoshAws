# This allows you work on the file as a script
$_privateCommand = Get-Command -Name "__MakeWildcard"
if (!$_privateCommand) {
    . "$PSScriptRoot\QuotePrivateUnquoteFunctions.ps1"
}

#region Private things

$_cfResourceTypes = @{
    "S3Bucket" = "AWS::S3::Bucket"
}

$_cfStackStatuses = @{
    "CREATE_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $true };
    "CREATE_COMPLETE" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $false };
    "CREATE_FAILED" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "ROLLBACK_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $true };
    "ROLLBACK_FAILED" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "ROLLBACK_COMPLETE" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "DELETE_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $true };
    "DELETE_FAILED" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "DELETE_COMPLETE" = @{ "Active" = $false; "Failed" = $false; "InFlux" = $false };
    "UPDATE_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $true };
    "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $true };
    "UPDATE_COMPLETE" = @{ "Active" = $true; "Failed" = $false; "InFlux" = $false };
    "UPDATE_ROLLBACK_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $true };
    "UPDATE_ROLLBACK_FAILED" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
    "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $true };
    "UPDATE_ROLLBACK_COMPLETE" = @{ "Active" = $true; "Failed" = $true; "InFlux" = $false };
}

function __StackStatusMap([string]$StackStatus) {
    if(!$_cfStackStatuses.ContainsKey($StackStatus)) {
        throw "$StackStatus is not a recognized stack status."
    }
    $_cfStackStatuses[$StackStatus]
}

function __IsStackActive([string]$StackStatus) {
    $_map = __StackStatusMap($StackStatus)
    $_map["Active"]
}

function __IsStackFailed([string]$StackStatus) {
    $_map = __StackStatusMap($StackStatus)
    $_map["Failed"]
}

#endregion

function Remove-CFStack {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName = "ByStackSummary", ValueFromPipeline = $true)]
        [Amazon.CloudFormation.Model.StackSummary]$StackSummary,
        [Parameter(Mandatory=$true, ParameterSetName = "ByName", ValueFromPipeline = $true)]
        [string]$StackName,
        [switch]$SkipConfirmation,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    BEGIN {
        if ($Credentials) {
            $_creds = $Credentials
        }
        else {
            $_creds = Get-AwsCredentials
        }

        $_region = __RegionFromName $Region

        $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)
    }
    PROCESS {

        if ($StackSummary) {
            Write-Debug "Using stack summary."
            $_stackName = $StackSummary | Select-Object -ExpandProperty StackName
        }
        elseif ($StackName) {
            Write-Debug "Using stack name."
            $_stackName = $StackName
        }
        else {
            throw "Wha?!"
        }
        
        $_stackName `
            | ForEach-Object {

                if (!$SkipConfirmation) {
                    Write-Host "You are about to remove a CloudFormation stack, which is potentially very, very bad." `
                        -ForegroundColor White `
                        -BackgroundColor Red
                    Write-Host "Please confirm you want the stack removed by typing the stack name exactly." `
                        -ForegroundColor White `
                        -BackgroundColor Red
                    $_confirmed = Read-Host "Stack Name"
                    if ($_confirmed -cne $_) {
                        throw "Confirmation did not match stack name!"
                    }
                }

                $_req = New-Object Amazon.CloudFormation.Model.DeleteStackRequest
                $_req.StackName = $_
                $_cfClient.DeleteStack($_req)
            }
    }
    END {
    }

}

function Get-CFStackResources {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName = "ByStackSummary", ValueFromPipeline = $true)]
        [Amazon.CloudFormation.Model.StackSummary]$StackSummary,
        [Parameter(Mandatory=$true, ParameterSetName = "ByName", ValueFromPipeline = $true)]
        [string]$StackName,
        [string]$LogicalId,
        [string]$ResourceType,
        [string]$ResourceStatus,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    BEGIN {
        if ($Credentials) {
            $_creds = $Credentials
        }
        else {
            $_creds = Get-AwsCredentials
        }

        $_region = __RegionFromName $Region

        $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)
    }
    PROCESS {

        if ($StackSummary) {
            Write-Debug "Using stack summary."
            $_stackName = $StackSummary | Select-Object -ExpandProperty StackName
        }
        elseif ($StackName) {
            Write-Debug "Using stack name."
            $_stackName = $StackName
        }
        else {
            throw "Wha?!"
        }
        
        $_stackName `
            | ForEach-Object {
                $_req = New-Object Amazon.CloudFormation.Model.ListStackResourcesRequest
                $_req.StackName = $_
                $_resp = $_cfClient.ListStackResources($_req)

                $_logicalWildcard = __MakeWildcard($LogicalId)
                $_typeWildcard = __MakeWildcard($ResourceType)
                $_statusWildcard = __MakeWildcard($ResourceStatus)

                $_resp.ListStackResourcesResult.StackResourceSummaries `
                    | Where-Object {
                        $_logicalWildcard.IsMatch($_.LogicalResourceId)
                    } `
                    | Where-Object {
                        $_typeWildcard.IsMatch($_.ResourceType)
                    } `
                    | Where-Object {
                        $_statusWildcard.IsMatch($_.ResourceStatus)
                    }
            }
    }
    END {
    }

}

function Get-CFStacks {

    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$ExactName,
        [switch]$IncludeInactive,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    if ($Credentials) {
        $_creds = $Credentials
    }
    else {
        $_creds = Get-AwsCredentials
    }

    $_region = __RegionFromName $Region

    $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)

    $_req = New-Object -TypeName Amazon.CloudFormation.Model.ListStacksRequest

    $_resp = $_cfClient.ListStacks($_req)

    $_nameWildcard = __MakeWildcard($Name)

    $_resp.ListStacksResult.StackSummaries `
        | Where-Object {
            if ($IncludeInactive) {
                $true
            }
            else {
                __IsStackActive($_.StackStatus)
            }
        } `
        | Where-Object {
            !$ExactName -or ($ExactName -eq $_.StackName)
        } `
        | Where-Object {
            $_nameWildcard.IsMatch($_.StackName)
        }

}

function Test-CFTemplate {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TemplatePath,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    $_region = __RegionFromName($Region)

    Write-Verbose "Validating $TemplatePath ..."

    if (!(Test-Path $TemplatePath)) {
        throw "Template not found at $TemplatePath!"
    }

    if ($Credentials) {
        $_creds = $Credentials
    }
    else {
        $_creds = Get-AwsCredentials
    }    

    $_templateBody = Get-Content $TemplatePath

    $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)

    $_req = New-Object Amazon.CloudFormation.Model.ValidateTemplateRequest
    $_req.TemplateBody = $_templateBody
    
    $_cfClient.ValidateTemplate($_req) `
        | Select-Object -ExpandProperty ValidateTemplateResult `
        | Select-Object -Property Capabilities, Parameters
}

function Set-CFStack {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$TemplatePath,
        [switch]$Force,
        [hashtable]$TemplateParams,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    if (!(Test-Path $TemplatePath)) {
        throw "Template not found at $TemplatePath!"
    }

    if ($Credentials) {
        $_creds = $Credentials
    }
    else {
        $_creds = Get-AwsCredentials
    }

    $_region = __RegionFromName($Region)

    $_templateBody = Get-Content $TemplatePath

    $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)

    $_alreadyExists = Get-CFStacks -ExactName $Name -Credentials $_creds

    if ($_alreadyExists -and -not $Force) {
        throw "Stack '$Name' already exists. Use -Force to update an existing stack."
    }

    $_testedTemplate = Test-CFTemplate -TemplatePath $TemplatePath -Credentials $_creds
    
    $_capabilities = $_testedTemplate.Capabilities
    $_foundParameters = $_testedTemplate.Parameters

    # PS and generic lists. Whee.
    $_parameterType = [Amazon.CloudFormation.Model.Parameter]
    $_parameterListType = [System.Collections.Generic.List``1].MakeGenericType(@($_parameterType))
    $_parameterList = [Activator]::CreateInstance($_parameterListType)

    $_foundParameters | ForEach-Object {

        $_currParam = New-Object -TypeName Amazon.CloudFormation.Model.Parameter
        $_currParam.ParameterKey = $_.ParameterKey

        if ($TemplateParams -and $TemplateParams.ContainsKey($_currParam.ParameterKey)) {
            $_currParam.ParameterValue = $TemplateParams[$_currParam.ParameterKey]
        } elseif ($_.DefaultValue -and $_.DefaultValue -ne "") {
            $_currParam.ParameterValue = $_.DefaultValue
        } else {
            throw "Missing parameter value for " + $_currParam.ParameterKey
        }

        $_parameterList.Add($_currParam)
    }

    if ($_alreadyExists) {
        
        Write-Host "Updating stack $Name ..."

        $_updateRequest = New-Object -TypeName Amazon.CloudFormation.Model.UpdateStackRequest
        $_updateRequest.Capabilities = $_capabilities
        $_updateRequest.StackName = $Name
        $_updateRequest.TemplateBody = $_templateBody
        $_updateRequest.Parameters = $_parameterList

        $_updateResponse = $_cfClient.UpdateStack($_updateRequest)

        Write-Host "Updated " + $_updateResponse.UpdateStackResult.StackId

    } else {

        Write-Host "Creating stack $Name ..."

        $_createRequest = New-Object -TypeName Amazon.CloudFormation.Model.CreateStackRequest
        $_createRequest.Capabilities = $_capabilities
        $_createRequest.StackName = $Name
        $_createRequest.TemplateBody = $_templateBody
        $_createRequest.Parameters = $_parameterList

        $_createResponse = $_cfClient.CreateStack($_createRequest)

        Write-Host "Created " + $_createResponse.CreateStackResult.StackId

    }
}

function Get-CFStackOutputs {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "BySummary", ValueFromPipeline = $true)]
        [Amazon.CloudFormation.Model.StackSummary]$StackSummary,
        [Parameter(Mandatory = $true, ParameterSetName = "ByName", ValueFromPipeline = $true)]
        [string]$StackName,
        [string]$Key,
        [Amazon.Runtime.AWSCredentials]$Credentials,
        [string]$Region
    )

    $_region = __RegionFromName($Region)

    if ($Credentials) {
        $_creds = $Credentials
    }
    else {
        $_creds = Get-AwsCredentials
    }
    
    if ($StackSummary) {
        Write-Debug "By summary."
        $_stackName = $StackSummary.StackName
    }
    elseif ($StackName) {
        Write-Debug "By name."
        $_stackName = $StackName
    }

    $_cfClient = [Amazon.AWSClientFactory]::CreateAmazonCloudFormationClient($_creds, $_region)

    $_outputReq = New-Object -TypeName Amazon.CloudFormation.Model.DescribeStacksRequest
    $_outputReq.StackName = $_stackName

    [Amazon.CloudFormation.Model.Stack]$_stack = $_cfClient.DescribeStacks($_outputReq).DescribeStacksResult.Stacks `
                                                    | Select-Object -First 1

    if (!$_stack) {
        throw "Stack $Name not found."
    }

    $_keyWildcard = __MakeWildcard($Key)

    $_stack.Outputs | Where-Object { $_keyWildcard.IsMatch($_.OutputKey) }
}