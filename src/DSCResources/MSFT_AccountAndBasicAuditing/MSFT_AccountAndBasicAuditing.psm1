function IsNumeric
{
    param($Value)
    try
    {
        0 + $Value | Out-Null
        $IsNumeric = 1
    }
    catch
    {
        $IsNumeric = 0
    }

    if($IsNumeric){
        $IsNumeric = 1
        if($Boolean) { $Isnumeric = $True }
    }else{
        $IsNumeric = 0
        if($Boolean) { $IsNumeric = $False }
    }
    return $IsNumeric
}

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Enable,

        [parameter(Mandatory = $true)]
        $AccountAndBasicAuditing
    )
    $ErrorActionPreference = 'Stop'
    #Write-Verbose "Use this cmdlet to deliver information about command processing."
    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."
    
    $temp = "C:\Windows\security\database"
    $file = "$temp\cSecurityOptions_module_temppol.inf"
    $outHash = @{}

    $ps = new-object System.Diagnostics.Process
    $ps.StartInfo.Filename = "secedit.exe"
    $ps.StartInfo.Arguments = " /export /cfg $file /areas securitypolicy"
    $ps.StartInfo.RedirectStandardOutput = $True
    $ps.StartInfo.UseShellExecute = $false
    [void]$ps.start()
    [void]$ps.WaitForExit('10')
    [string] $process = $ps.StandardOutput.ReadToEnd();

    $in = get-content $file
    Remove-Item $file -Force

    # I now have the configuration options, now need to assemble into a hash table
    foreach ($line in $in)
    {
        if ($line.Contains("=") -and $line -notlike "Unicode*" -and $line -notlike "signature*" -and $line -notlike "Revision*" -and $line -notlike "Audit*")
        {
            if (!($line.Contains("MACHINE")))
            {
                $policy = $line.substring(0,$line.IndexOf("=") - 1)
                $values = ($line.substring($line.IndexOf("=") + 1,$line.Length - ($line.IndexOf("=") + 1))).trim()
                if ($values.Contains("`"")){
                    $outHash.Add($policy,($values.Substring(1)).substring(0,$values.Length - 2))
                } else {
                    $outHash.Add($policy,$values)
                }
            } else {
                <#
                # These are for registry settings
                if ($line.Contains("`""))
                {
                    $policy = $line.split("=")[0]
                    $values = $line.split("=")[1] -replace "`"", ""
                    $outHash.Add($policy,$values)
                } else {
                    $policy = $line.split("=")[0]
                    $values = $line.split("=")[1]
                    $outHash.Add($policy,$values)
                }
                #>
            }
        }
    }

    $returnValue = @{
                     Enable = $Enable
                     AccountAndBasicAuditing = $outHash
                    }

    $returnValue
}

# This will run ONLY if Test-TargetResource is $false
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Enable,

        [parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance[]]
        $AccountAndBasicAuditing
    )
    $ErrorActionPreference = 'Stop'
    #Write-Verbose "Use this cmdlet to deliver information about command processing."
    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."
    
    $temp = "C:\Windows\security\database"
    $newfile = "$temp\cSecurityOptions_module_newpol.inf"
    $new_secdb = "$temp\cSecurityOptions_secedit.sdb"
    
    if (test-path $newfile){Remove-Item $newfile -Force}
    $EventAudit = @{}
    $SystemAccess = @{}
    
    foreach ($configSecOption in $AccountAndBasicAuditing.GetEnumerator())
    {
        #write-debug "What is this single thing? $($configSecOption)"
        #write-debug "!!!line 122 $($configSecOption.Key) and $($configSecOption.Value)"
        if ($configSecOption.Key.contains("Audit"))
        {
            $EventAudit.Add($configSecOption.Key, $configSecOption.Value)
        } else {
            $SystemAccess.Add($configSecOption.Key, $configSecOption.Value)
        }
    }
    
    "[Unicode]" | Out-File $newfile
    "Unicode=yes" | Out-File $newfile -Append
    "[System Access]" | Out-File $newfile -Append
    foreach ($configSecOption in $SystemAccess.GetEnumerator())
    {
        if (IsNumeric($configSecOption.Value))
        {"$($configSecOption.Name) = $($configSecOption.Value)" | Out-File $newfile -Append
        } else {"$($configSecOption.Name) = `"$($configSecOption.Value)`"" | Out-File $newfile -Append}
    }
    
    # Disabled this in favor of Advanced Audit Policies (use AuditPol.exe)
    "[Event Audit]" | Out-File $newfile -Append
    foreach ($configSecOption in $EventAudit.GetEnumerator()){"$($configSecOption.Name) = $($configSecOption.Value)" | Out-File $newfile -Append}
    "[Version]" | Out-File $newfile -Append
    "signature=`"`$CHICAGO`$`"" | Out-File $newfile -Append
    "Revision=1" | Out-File $newfile -Append
    
    $ps = new-object System.Diagnostics.Process
    $ps.StartInfo.Filename = "secedit.exe"
    $ps.StartInfo.Arguments = " /configure /db $new_secdb /cfg $newfile /overwrite /quiet"
    $ps.StartInfo.RedirectStandardOutput = $True
    $ps.StartInfo.UseShellExecute = $false
    [void]$ps.start()
    [void]$ps.WaitForExit('10')
    [string] $process = $ps.StandardOutput.ReadToEnd();
    
    Remove-Item $newfile -Force
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Enable,

        [parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance[]]
        $AccountAndBasicAuditing
    )
    $ErrorActionPreference = 'Stop'
    #Write-Verbose "Use this cmdlet to deliver information about command processing."
    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."
 
    $CurrentSetting = Get-TargetResource -Enable $true -AccountAndBasicAuditing $true

    # Start with $true, assuming that there are no differences, but if there is a difference, flip it.
    # Set-TargetResource only is triggered on $false - should be seldom
    $diffFound = $true
    foreach ($configSecOption in $AccountAndBasicAuditing.GetEnumerator())
    {
        foreach ($existConfig in $CurrentSetting.AccountAndBasicAuditing.GetEnumerator())
        {
            if ($configSecOption.Key -eq $existConfig.Name)
            {
                if ($configSecOption.value -ne $existConfig.value)
                {
                    $diffFound = $false
                }
            }
        }
    }
    Write-Verbose "This is the value: $($diffFound)"
    return $diffFound
}

Export-ModuleMember -Function *-TargetResource
