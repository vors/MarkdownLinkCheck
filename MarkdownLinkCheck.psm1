function Get-MarkdownLink
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [string[]]$Path = '.',

        [switch]$ThrowOnBroken,

        [switch]$BrokenOnly
    )

    begin
    {
        $builder = [Markdig.MarkdownPipelineBuilder]::new()
        # use UsePreciseSourceLocation for better error reporting
        $pipeline = [Markdig.MarkdownExtensions]::UsePreciseSourceLocation($builder).Build()
        $hasBroken = @($false)
    }

    process
    {
        function handleOneFile
        {
            param(
                [string]$File
            )

            Write-Verbose "Process $File"

            $root = Split-Path $File
            $s = Get-Content -Raw $File
            $ast = [Markdig.Markdown]::Parse($s, $pipeline)
            $links = $ast.Inline | ? {$_ -is [Markdig.Syntax.Inlines.LinkInline]}
            $links | % {
                $url = $_.Url
                $isBroken = if (Test-LinkAsUri $url) { 
                    $false 
                }
                else {
                    -not (Test-LinkAsRelative $url $root)
                }

                Add-Member -InputObject $_ -MemberType NoteProperty -Name IsBroken -Value $isBroken
            }

            $brokenLinks = $links | ? {$_.IsBroken}

            if ($brokenLinks)
            {
                Write-Verbose "Found $($brokenLinks.Count) broken links in $File"
                $hasBroken[0] = $true
            }
            else 
            {
                Write-Verbose "Found no broken links in $File"
            }

            # format and return
            if ($BrokenOnly)
            {
                $links = $brokenLinks
            }
            $result = $links | Select-Object -Property Content, Url, IsBroken, Line, Column, Span
            $result | Add-Member -MemberType NoteProperty -Name Path -Value $File
            $result
        }

        $Path | % {
            if (Test-Path $_ -PathType Container)
            {
                Get-ChildItem -Recurse -Filter '*.md' $_ | % {
                    handleOneFile $_.FullName
                }
            }
            elseif (Test-Path $_ -PathType Leaf)
            {
                handleOneFile $_
            }
            else 
            {
                throw "$_ is not a valid path"    
            }
        }
    }

    end 
    {
        if ($Throw -and $hasBroken[0])
        {
            throw "There are broken markdown links and Throw switch is specified"
        } 
    }
}

function Test-LinkAsUri
{
    param(
        [string]$link
    )

    try 
    {
        $uri = [uri]::new($link) 
        return $uri.IsAbsoluteUri
    }
    catch 
    {
        return $false    
    }
}

function Test-LinkAsRelative
{
    param(
        [string]$link,
        [string]$root
    )

    # ignore paragraph specification
    $link = $link.Split('#')[0]
    
    $relativePath = Join-Path $root $link
    return (Test-Path $relativePath)
}
