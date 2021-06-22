# Purpose: patch termsrv.dll on Windows 10 client to enable concurrent RDP sessions

Get-ComputerInfo -Property WindowsInstallationType, WindowsVersion | select-object -Property WindowsInstallationType, WindowsVersion -OutVariable CompInfo | Out-Null
if ($CompInfo.WindowsInstallationType -eq "Client") {
    Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Patching termsrv.dll to allow concurrent RDP - detected Windows version $($CompInfo.WindowsVersion)..."

    . "c:\vagrant\resources\windows\ConvertTo-String.ps1"
    $TermSrvPattern = [Regex] "WONTFINDTHIS"
    $PatchBytes = [byte[]] (0xB8, 0x00, 0x01, 0x00, 0x00, 0x89, 0x81, 0x38, 0x06, 0x00, 0x00, 0x90)
    if ($CompInfo.WindowsVersion -eq 1909) {
        $TermSrvPattern = [Regex] "\x39\x81\x3C\x06\x00\x00\x0F\x84\x5D\x61\x01\x00"
    }

    $TermSrvStr = ConvertTo-String "C:\Windows\System32\termsrv.dll"
    $TermSrvBytes = Get-Content "C:\Windows\System32\termsrv.dll" -Encoding Byte -Raw
    $TermSrvMatches = $TermSrvPattern.Matches($TermSrvStr)
    if ($TermSrvMatches.count -eq 1) {
        Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Found a match for pattern $TermSrvPattern at index $($TermSrvMatches.index)"

        for ($i = 0; $i -lt $PatchBytes.length; ++$i) {
            $TermSrvBytes[$TermSrvMatches.index + $i] = $PatchBytes[$i]
        }

        Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Stopping RDP service..."
        Stop-Service TermService -Force -ErrorAction Stop

        Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Adjusting termsrv.dll permissions..."
        $NewAcl = Get-Acl -Path "C:\Windows\System32\termsrv.dll"
        $identity = "BUILTIN\Administrators"
        $fileSystemRights = "FullControl"
        $type = "Allow"
        $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
        $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
        $NewAcl.SetAccessRule($fileSystemAccessRule)
        Set-Acl -Path "C:\Windows\System32\termsrv.dll" -AclObject $NewAcl
        Copy-Item "C:\Windows\System32\termsrv.dll" "C:\Windows\System32\termsrv.bak.dll"

        Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Writing patched DLL to disk..."
        $TermSrvBytes | Set-Content "C:\Windows\System32\termsrv.dll" -Encoding Byte -Force

        Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Restarting RDP service..."
        Start-Service TermService
    } else {
        Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Found $($TermSrvMatches.count) match(es) for pattern $TermSrvPattern; aborting..."
    }
}
