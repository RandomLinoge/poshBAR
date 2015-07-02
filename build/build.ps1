$errorActionPreference = 'Stop'
$baseDir  = resolve-path ".\.."
$script:this = @{
    buildDir = "$baseDir\build-artifacts" 
    resultsDir = "$baseDir\build-artifacts\results"
    buildPublishDir = "$baseDir\build-artifacts\publish"
    packagesDir = "$baseDir\Packages"
    workingDir = "$baseDir\build-artifacts\Working"
    srcDir = "$baseDir\src\poshBAR"
    devopsNugetPackage = "$baseDir\nuspec\poshBAR.nuspec"
    devopsSummary = "Powershell Build `$amp; Release"
    testDir = "$baseDir\tests"
}

# Dogfood
Import-Module "$($this.srcDir)\poshBAR" -force -Global

Task default -depends Package

Task SetupPaths {
    Write-Host "Adding some of our tools to the Path so we can run them easier"
    $env:Path += ";$($this.packagesDir)\NuGet.CommandLine.2.8.3\tools"
}

Task MakeBuildDir {
    Write-Host "Creating new build-artifacts directory"
    $this.buildDir
    rm -r $this.buildDir -force -ea SilentlyContinue
    New-Item -ItemType Directory -Force -Path $this.buildPublishDir
    New-Item -ItemType Directory -Force -Path $this.workingDir
    New-Item -ItemType Directory -Force -Path "$($this.workingDir)\poshBar"
    New-Item -ItemType Directory -Force -Path $this.resultsDir
}

Task UpdateVersion -depends MakeBuildDir {
    copy "$($this.srcDir)\*" "$($this.workingDir)\poshBar"

    Push-Location "$($this.workingDir)\poshBar"

    $pattern = '^\$version = [''|"](\d.\d.\d.\d)[''|"] .*'
    $output = "`$version = '$version.$buildNumber' # contains the current version of poshBAR"
    ls -r -filter poshBAR.psm1 | % {
        $filename = $_.Directory.ToString() + '\' + $_.Name
        (Get-Content $filename) | % {
            % {$_ -replace $pattern, $output }
        } | Out-File "$filename.temp"

        rm $filename -force
        ren "$filename.temp" $filename
        "$filename - Updated to $version.$buildNumber"
    }
    Pop-Location
}

Task GenerateDocumentation -depends SetupPaths, UpdateVersion, MakeBuildDir -alias docs {
    Exec {.\out-html.ps1 -moduleName 'poshBAR' -outputDir "$baseDir"} -retry 10 # retry because of the build agent issues when committing multiple branches.
}

Task Package -depends SetupPaths, UpdateVersion, MakeBuildDir, RunPesterTests, GenerateDocumentation {

    Update-XmlConfigValues $this.devopsNugetPackage "//*[local-name() = 'summary']" "$($this.devopsSummary) v-$version"
    exec { NuGet.exe Pack $this.devopsNugetPackage -Version "$version.$buildNumber" -OutputDirectory $this.buildPublishDir -NoPackageAnalysis } "Failed to package the Devops Scripts."
}

Task RunPesterTests -depends MakeBuildDir -alias tests {
    $tmp = $env:TEMP
    $env:TEMP = $this.workingDir
    
    Import-Module "$($this.packagesDir)\pester.*\tools\pester.psm1" -force  -Global
    $results = Invoke-Pester -relative_path $this.testDir -PassThru  -OutputFile "$($this.resultsDir)\pester.xml" -OutputFormat NUnitXml
    if($results.FailedCount -gt 0) {
        throw "$($results.FailedCount) Tests Failed."
    }
    
    $env:TEMP = $tmp
}

FormatTaskName {
    param($taskName)
    Format-TaskNameToHost $taskName
}