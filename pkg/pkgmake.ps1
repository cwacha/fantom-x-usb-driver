param (
    [string]$rule = ""
)

$BASEDIR = $PSScriptRoot
#echo BASEDIR=$BASEDIR
$CA_NAME = "Fantom-X Custom Driver CA"

function all {
    "# building: $app_pkgname"
    clean
    import
    setupcert
    sign
    pkg
}

function _init {
    $global:app_pkgid = "fantom-x-usb-driver-win11"
    $global:app_displayname = "Fantom X USB Driver for Windows 10/11"
    $global:app_version = "1.0.0"
    $global:app_revision = git rev-list --count HEAD
    $global:app_build = git rev-parse --short HEAD

    $global:app_pkgname = "$app_pkgid-$app_version-$app_revision-$app_build"
}

function _template {
    param (
        [string] $inputfile
    )
    Get-Content $inputfile | % { $_ `
            -replace "%app_pkgid%", "$app_pkgid" `
            -replace "%app_version%", "$app_version" `
            -replace "%app_displayname%", "$app_displayname" `
            -replace "%app_revision%", "$app_revision" `
            -replace "%app_build%", "$app_build"
    }
}

function _isAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function import {
    "# import ..."
    mkdir BUILD -ea SilentlyContinue *> $null

    Expand-Archive -Path $BASEDIR\..\ext\*.zip -DestinationPath BUILD
    mv BUILD\fanx_* BUILD\root
    cd BUILD\root
    rm Setup.exe
    rm Uninstall.exe
    rm Readme.htm
    rm -r -fo Readme
    cp -r -fo Files\64bit\Files\* .
    rm -r -fo Files
    rm RdDrvInf.dat
    rm RdUninst.dat
    rm Setup.dat
    cd ../..

    cp -r -fo ..\src\* BUILD/root
}

function setupcert {
    "# setupcert ..."

    # Check if CA exists and create if is necessary
    $cacert = Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like "CN=$CA_NAME"
    if (!($cacert)) {
        if (!(_isAdmin)) {
            "### ERROR: The CA certificate '$CA_NAME' is missing, but you are not running as Admin"
            exit 1
        }

        "# creating new CA for '$CA_NAME'"
        $params = @{
            Type              = 'Custom'
            Subject           = "CN=$CA_NAME"
            KeyUsage          = 'DigitalSignature'
            CertStoreLocation = 'Cert:\LocalMachine\Root'
        }
        $cacert = New-SelfSignedCertificate @params
        Export-Certificate -Cert $cacert -FilePath tmp.cer
        Import-Certificate -StoreLocation Cert:\LocalMachine\TrustedPublisher -CertFilePath tmp.cer
        Remove-Item tmp.cer
    }
    Export-Certificate -Cert $cacert -FilePath BUILD\root\CA_certificate.cer *> $null
}

function sign {
    "# sign ..."

    # check inf2cat.exe is available
    if (!(Get-Command "inf2cat.exe" -ea SilentlyContinue)) {
        "### ERROR: inf2cat.exe is missing in the path. Download and install the Windows Driver Kit (WDK) and setup the path correctly."
        exit 1
    }

    & Inf2Cat.exe /os:10_x64 /driver:$BASEDIR\BUILD\root

    # check signtool is available
    if (!(Get-Command "signtool.exe" -ea SilentlyContinue)) {
        "### ERROR: signtool.exe is missing in the path. Download and install the Windows Driver Kit (WDK) and setup the path correctly."
        exit 1
    }

    # sign drivers
    $files = @(
        "*.cat",
        "*.dll",
        "*.exe",
        "*.sys"
    )
    foreach ($file in $files) {
        & signtool.exe sign /fd SHA256 /sm /s Root /n $CA_NAME /t http://timestamp.digicert.com BUILD\root\$file
    }
    ""
}

function pkg {
    "# packaging ..."
    mkdir PKG *> $null
    
    cd BUILD
    Compress-Archive -Path root\* -DestinationPath ..\PKG\$app_pkgname.zip
    cd ..
    "## created $BASEDIR\PKG\$app_pkgname.zip"
}

function clean {
    "# clean ..."
    rm -r -fo -ea SilentlyContinue PKG
    rm -r -fo -ea SilentlyContinue BUILD
}

$funcs = Select-String -Path $MyInvocation.MyCommand.Path -Pattern "^function ([^_]\S+) " | % { $_.Matches.Groups[1].Value }
if (! $funcs.contains($rule)) {
    "no such rule: '$rule'"
    ""
    "RULES"
    $funcs | % { "    $_" }
    exit 1
}

Push-Location
cd "$BASEDIR"
_init

"##### Executing rule '$rule'"
& $rule $args
"##### done"

Pop-Location
