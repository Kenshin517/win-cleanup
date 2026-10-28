@{
    Severity     = @('Error', 'Warning', 'Information')
    ExcludeRules = @(
        # Interactive console tool: coloured progress output is intentional.
        'PSAvoidUsingWriteHost'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
    }
}
