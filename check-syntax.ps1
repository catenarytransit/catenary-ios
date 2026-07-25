$failed = $false

$files = Get-ChildItem -Path . -Recurse -File -Filter *.swift |
    Where-Object {
        $_.FullName -notmatch '\\(\.git|\.build|build|DerivedData|Pods|Carthage)\\'
    }

foreach ($file in $files) {
    Write-Host "Checking $($file.FullName)"
    & swiftc -parse $file.FullName

    if ($LASTEXITCODE -ne 0) {
        $failed = $true
    }
}

if ($failed) {
    Write-Error "Swift syntax errors found."
    exit 1
}

Write-Host "All Swift files parsed successfully."