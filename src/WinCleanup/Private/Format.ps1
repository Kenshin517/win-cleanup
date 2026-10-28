function Format-ByteSize {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [Nullable[long]] $Bytes
    )

    if ($null -eq $Bytes) { return 'unknown' }

    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $value = [double][Math]::Abs($Bytes)
    $index = 0
    while ($value -ge 1024 -and $index -lt $units.Count - 1) {
        $value /= 1024
        $index++
    }

    $sign = if ($Bytes -lt 0) { '-' } else { '' }
    $format = if ($index -eq 0) { '{0}{1:0} {2}' } else { '{0}{1:0.00} {2}' }
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture, $format, $sign, $value, $units[$index])
}
