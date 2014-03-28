@{
Description = 'Provides Cmdlets that can assist in a Continuous Integration environment for Chocolatey packages'
# Script module or binary module file associated with this manifest.
ModuleToProcess = './boxstarter.CI.psm1'

# Version number of this module.
ModuleVersion = '2.3.24'

# ID used to uniquely identify this module
GUID = '087b5fe9-4a6e-40b5-a0fb-e670b86563b3'

# Author of this module
Author = 'Matt Wrock'

# Copyright statement for this module
Copyright = '(c) 2014 Matt Wrock'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '2.0'

# Minimum version of the .NET Framework required by this module
DotNetFrameworkVersion = '2.0'

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
NestedModules = @('..\Boxstarter.Common\Boxstarter.Common.psd1','..\Boxstarter.Chocolatey\Boxstarter.Chocolatey.psd1')

# Functions to export from this module
FunctionsToExport = '*'

# Cmdlets to export from this module
CmdletsToExport = '*'

# Variables to export from this module
VariablesToExport = '*'

# Aliases to export from this module
AliasesToExport = '*'

# List of all modules packaged with this module.
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess
PrivateData = '75238267fbd770b8449ed3709e568bb41de616b2'

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}
