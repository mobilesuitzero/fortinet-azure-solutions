#Requires -Modules Pester
<#
.SYNOPSIS
    Tests a specific ARM template
.EXAMPLE
    Invoke-Pester
.NOTES
    This file has been created as an example of using Pester to evaluate ARM templates
#>

Function random-password ($length = 15) {
    $punc = 46..46
    $digits = 48..57
    $letters = 65..90 + 97..122

    # Thanks to
    # https://blogs.technet.com/b/heyscriptingguy/archive/2012/01/07/use-pow
    $password = get-random -count $length `
        -input ($punc + $digits + $letters) |
        % -begin { $aa = $null } `
        -process {$aa += [char]$_} `
        -end {$aa}

    return $password
}

$templateName = "single-1nic"
$sourcePath = "$env:BUILD_SOURCESDIRECTORY\FortiManager\$templateName"
$scriptPath = "$env:BUILD_SOURCESDIRECTORY\FortiManager\$templateName\test"
$templateFileName = "azuredeploy.json"
$templateFileLocation = "$sourcePath\$templateFileName"
$templateMetadataFileName = "metadata.json"
$templateMetadataFileLocation = "$sourcePath\$templateMetadataFileName"
$templateParameterFileName = "azuredeploy.parameters.json"
$templateParameterFileLocation = "$sourcePath\$templateParameterFileName"

# Basic Variables
$testsRandom = Get-Random 10001
$testsPrefix = "FORTIQA"
$testsResourceGroupName = "FORTIQA-$testsRandom-$templateName"
$testsAdminUsername = "azureuser"
$testsResourceGroupLocation = "westeurope"

Describe 'ARM template' {
    Context 'validation' {
        It 'Has a JSON template' {
            $templateFileLocation | Should Exist
        }

        It 'Has a parameters file' {
            $templateParameterFileLocation | Should Exist
        }

        It 'Converts from JSON and has the expected properties' {
            $expectedProperties = '$schema',
            'contentVersion',
            'parameters',
            'resources',
            'variables'
            $templateProperties = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue) | Get-Member -MemberType NoteProperty | % Name
            $templateProperties | Should Be $expectedProperties
        }

        It 'Creates the expected Azure resources' {
            $expectedResources = 'Microsoft.Resources/deployments',
                                 'Microsoft.Network/virtualNetworks',
                                 'Microsoft.Network/networkSecurityGroups',
                                 'Microsoft.Network/publicIPAddresses',
                                 'Microsoft.Network/networkInterfaces',
                                 'Microsoft.Compute/virtualMachines'
            $templateResources = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue).Resources.type
            $templateResources | Should Be $expectedResources
        }

        It 'Contains the expected parameters' {
            $expectedTemplateParameters = 'adminPassword',
                                          'adminUsername',
                                          'dataDiskSize',
                                          'FortinetTags',
                                          'imageSKU',
                                          'imageVersion',
                                          'instanceType',
                                          'location',
                                          'namePrefix',
                                          'publicIPAddressType',
                                          'publicIPName',
                                          'publicIPNewOrExisting',
                                          'publicIPResourceGroup',
                                          'subnet1Name',
                                          'subnet1Prefix',
                                          'vnetAddressPrefix',
                                          'vnetName',
                                          'vnetNewOrExisting',
                                          'vnetResourceGroup'
            $templateParameters = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue).Parameters | Get-Member -MemberType NoteProperty | % Name | Sort-Object
            $templateParameters | Should Be $expectedTemplateParameters
        }

    }

    Context 'deployment' {

        # Set working directory & create resource group
        Set-Location $sourcePath
        New-AzureRmResourceGroup -Name $testsResourceGroupName -Location "$testsResourceGroupLocation"

        # Validate all ARM templates one by one
        $testsErrorFound = $false

        $params = @{ 'adminUsername'=$testsAdminUsername
                     'adminPassword'=$testsResourceGroupName
                     'namePrefix'=$testsPrefix
                    }
        $publicIPName = "FMGPublicIP"

        It "Test Deployment $templateFileName" {
            (Test-AzureRmResourceGroupDeployment -ResourceGroupName "$testsResourceGroupName" -TemplateFile "$templateFileName" -TemplateParameterObject $params).Count | Should not BeGreaterThan 0
        }
        It "Deployment $templateFileName" {
            $resultDeployment = New-AzureRmResourceGroupDeployment -ResourceGroupName "$testsResourceGroupName" -TemplateFile "$templateFileName" -TemplateParameterObject $params
            Write-Host ($resultDeployment | Format-Table | Out-String)
            Write-Host ("Deployment state: " + $resultDeployment.ProvisioningState | Out-String)
            $resultDeployment.ProvisioningState | Should Be "Succeeded"
        }
        It "Find deployment" {
            $result = Get-AzureRmVM | Where-Object { $_.Name -like "$testsPrefix*" }
            Write-Host ($result | Format-Table | Out-String)
            $result | Should Not Be $null
        }

        443, 22 | Foreach-Object {
            It "Port [$_] is listening" {
                $result = Get-AzureRmPublicIpAddress -Name $publicIPName -ResourceGroupName $testsResourceGroupName
                $portListening = (Test-NetConnection -Port $_ -ComputerName $result.IpAddress).TcpTestSucceeded
                $portListening | Should -Be $true
            }
        }
    }

    Context 'cleanup' {
        It "remove resource group" {
            Remove-AzureRmResourceGroup -Name $testsResourceGroupName -Force
        }
    }
}
