# Generates and trusts a short-lived certificate only on a disposable hosted CI
# runner. Never export its private key or publish the packages signed with it.
param(
    [Parameter(Mandatory)][string]$Stage,
    [Parameter(Mandatory)][string]$Output
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Deployment testing is restricted to disposable GitHub-hosted Windows runners.'
}
if (Get-AppxPackage -Name Pairwise.Desktop) {
    throw 'An existing Pairwise installation must not be modified by this test.'
}
New-Item -ItemType Directory -Force $Output | Out-Null
$Output = (Resolve-Path $Output).Path
$publisher = 'CN=Pairwise Disposable CI Test'
$certificate = $null
$results = [System.Collections.Generic.List[object]]::new()
$report = [ordered]@{
    schemaVersion = 1
    osBuild = [Environment]::OSVersion.Version.ToString()
    classification = 'disposable-ci-test-certificate; not production signing or Windows 10/11 acceptance'
    startedAt = [DateTime]::UtcNow.ToString('o')
    steps = $results
    success = $false
    temporaryTrustRemoved = $false
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPairwiseActivationManager {
    [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appId,
        [MarshalAs(UnmanagedType.LPWStr)] string arguments, uint options, out uint processId);
    [PreserveSig] int ActivateForFile([MarshalAs(UnmanagedType.LPWStr)] string appId, IntPtr files,
        [MarshalAs(UnmanagedType.LPWStr)] string verb, out uint processId);
    [PreserveSig] int ActivateForProtocol([MarshalAs(UnmanagedType.LPWStr)] string appId, IntPtr items, out uint processId);
}
public static class PairwisePackageActivation {
    public static uint Launch(string appId) {
        var type = Type.GetTypeFromCLSID(new Guid("45ba127d-10a8-46ea-8ab7-56ea9078943c"));
        var manager = (IPairwiseActivationManager)Activator.CreateInstance(type);
        try {
            uint processId;
            Marshal.ThrowExceptionForHR(manager.ActivateApplication(appId, "--smoke-test", 2, out processId));
            return processId;
        } finally { Marshal.FinalReleaseComObject(manager); }
    }
}
'@
try {
    $certificate = New-SelfSignedCertificate -Type Custom -KeyUsage DigitalSignature `
        -CertStoreLocation 'Cert:\CurrentUser\My' -KeyAlgorithm RSA -KeyLength 2048 `
        -KeyExportPolicy NonExportable -HashAlgorithm SHA256 -Subject $publisher `
        -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={text}') `
        -NotAfter (Get-Date).AddDays(1) -FriendlyName 'Pairwise disposable package test'
    $publicCertificate = Join-Path $Output 'ci-test-public.cer'
    Export-Certificate -Cert $certificate -FilePath $publicCertificate | Out-Null
    # MSIX deployment checks machine trust. Only the public certificate is imported.
    Import-Certificate -FilePath $publicCertificate -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
    Import-Certificate -FilePath $publicCertificate -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
    $family = $null
    foreach ($version in @('0.1.0.0','0.1.0.1')) {
        & "$PSScriptRoot/package.ps1" -Stage $Stage -Output $Output -Version $version `
            -Publisher $publisher -CertificateThumbprint $certificate.Thumbprint `
            -UpdateBaseUrl 'https://pairwise-ci.invalid'
        $file = Join-Path $Output "Pairwise-$version-x64.msix"
        Add-AppxPackage -Path $file -ForceApplicationShutdown
        $installed = Get-AppxPackage -Name Pairwise.Desktop
        if (!$installed -or $installed.Publisher -ne $publisher -or $installed.Version -ne [version]$version) {
            throw "Installed identity/version mismatch for $version."
        }
        if ($family -and $installed.PackageFamilyName -ne $family) {
            throw 'Package identity changed across the update.'
        }
        $family = $installed.PackageFamilyName
        $processId = [PairwisePackageActivation]::Launch("${family}!Pairwise")
        $process = Get-Process -Id $processId -ErrorAction Stop
        if (!$process.WaitForExit(30000)) {
            $process.Kill()
            throw 'Installed native app startup/shutdown timed out.'
        }
        if ($process.ExitCode -ne 0) { throw "Installed native app failed with exit code $($process.ExitCode)." }
        $results.Add([ordered]@{version=$version; installed=$true; activatedWithPackageIdentity=$true; smokeExitCode=0})
    }
    Remove-AppxPackage -Package $installed.PackageFullName
    if (Get-AppxPackage -Name Pairwise.Desktop) { throw 'Package remained installed after removal.' }
    $results.Add([ordered]@{uninstalled=$true})
    $report.success = $true
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    # Cleanup executes on install, activation, update and assertion failures too.
    Get-AppxPackage -Name Pairwise.Desktop | Where-Object { $_.Publisher -eq $publisher } | ForEach-Object {
        Remove-AppxPackage -Package $_.PackageFullName -ErrorAction Continue
    }
    if ($certificate) {
        $thumbprint = $certificate.Thumbprint
        foreach ($store in @('Cert:\LocalMachine\TrustedPeople','Cert:\LocalMachine\Root')) {
            Remove-Item "$store\$thumbprint" -Force -ErrorAction SilentlyContinue
        }
        Remove-Item "Cert:\CurrentUser\My\$thumbprint" -DeleteKey -Force -ErrorAction SilentlyContinue
        $report.temporaryTrustRemoved = (
            !(Test-Path "Cert:\LocalMachine\TrustedPeople\$thumbprint") -and
            !(Test-Path "Cert:\LocalMachine\Root\$thumbprint") -and
            !(Test-Path "Cert:\CurrentUser\My\$thumbprint")
        )
    }
    $report.finishedAt = [DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Output 'deployment-result.json') -Encoding UTF8
    if ($certificate -and !$report.temporaryTrustRemoved) { throw 'Temporary signing trust cleanup failed.' }
}
